import Foundation
import Combine
import AVFoundation
import UIKit
import os.log

/// Connection state of the Snapcast client engine.
enum SnapClientState: Int, Sendable {
    case disconnected = 0
    case connecting   = 1
    case connected    = 2
    case playing      = 3

    var displayName: String {
        switch self {
        case .disconnected: return "Disconnected"
        case .connecting:   return "Connecting…"
        case .connected:    return "Connected"
        case .playing:      return "Playing"
        }
    }

    var isActive: Bool {
        self == .connected || self == .playing
    }
}

private let log = Logger(subsystem: "com.snapforge.snapclient", category: "Engine")

/// Swift wrapper around the snapclient C++ core via the C bridge.
///
/// Usage:
/// ```swift
/// let engine = SnapClientEngine()
/// engine.start(host: "192.168.1.10", port: 1704)
/// engine.volume = 80
/// ```
@MainActor
final class SnapClientEngine: ObservableObject {

    // MARK: - Published state

    @Published private(set) var state: SnapClientState = .disconnected
    @Published var volume: Int = 100 {
        didSet { applyVolume() }
    }
    @Published var isMuted: Bool = false {
        didSet { applyMuted() }
    }
    @Published var latencyMs: Int = 0 {
        didSet { applyLatency() }
    }
    @Published private(set) var isPaused: Bool = false

    // MARK: - Server info

    @Published private(set) var connectedHost: String?
    @Published private(set) var connectedPort: Int?

    /// Bridge log messages forwarded from C++ (most recent first).
    @Published private(set) var bridgeLogs: [String] = []

    /// Last successfully connected server (persisted).
    var lastServer: (host: String, port: Int)? {
        get {
            guard let host = UserDefaults.standard.string(forKey: "lastServerHost"),
                  let port = UserDefaults.standard.object(forKey: "lastServerPort") as? Int else {
                return nil
            }
            return (host, port)
        }
        set {
            if let server = newValue {
                UserDefaults.standard.set(server.host, forKey: "lastServerHost")
                UserDefaults.standard.set(server.port, forKey: "lastServerPort")
            } else {
                UserDefaults.standard.removeObject(forKey: "lastServerHost")
                UserDefaults.standard.removeObject(forKey: "lastServerPort")
            }
        }
    }

    // MARK: - Configuration

    /// Enable automatic reconnection on disconnection.
    @Published var autoReconnect: Bool = true

    /// Force audio to local speaker (prevents AirPlay loop).
    @Published var forceLocalSpeaker: Bool = false {
        didSet {
            if state.isActive {
                configureAudioSession() // Re-apply
            }
        }
    }

    /// Warning: AirPlay output detected (potential loop).
    @Published private(set) var airPlayLoopWarning: Bool = false

    /// Error message from audio session configuration (nil if successful).
    @Published private(set) var audioSessionError: String?

    // MARK: - Private

    private var clientRef: SnapClientRef?
    private var reconnectTask: Task<Void, Never>?
    private var connectionTask: Task<Void, Never>?
    private var interruptionObserver: NSObjectProtocol?
    private var routeChangeObserver: NSObjectProtocol?

    // Exponential backoff for reconnection
    private var reconnectAttempts: Int = 0
    private let maxReconnectDelay: TimeInterval = 60.0
    private let baseReconnectDelay: TimeInterval = 2.0

    // Keep a max number of log lines
    private let maxLogLines = 200

    // Unique instance ID for debugging
    private let instanceId = UUID().uuidString.prefix(8)

    // MARK: - Lifecycle

    /// Unique client ID based on device vendor identifier
    private static var uniqueClientId: String {
        let vendorId = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        return "SnapForge-\(vendorId.prefix(8))"
    }

    init() {
        let id = instanceId  // capture before self is fully initialized
        log.info("SnapClientEngine[\(id)] init")
        clientRef = snapclient_create()
        guard clientRef != nil else {
            fatalError("Failed to create snapclient instance")
        }

        // Set unique client ID before registering callbacks
        let clientId = Self.uniqueClientId
        setName(clientId)

        registerCallbacks()
        registerLogCallback()
        setupAudioSessionObservers()

        // Sync pause state with C++ bridge
        isPaused = snapclient_is_paused(clientRef)

        log.info("SnapClientEngine[\(id)] ready, clientId=\(clientId), core version: \(snapclient_version().map(String.init(cString:)) ?? "?")")
    }

    deinit {
        // Cancel any pending reconnect or in-progress connection
        reconnectTask?.cancel()
        connectionTask?.cancel()

        // Remove audio session observers
        if let observer = interruptionObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = routeChangeObserver {
            NotificationCenter.default.removeObserver(observer)
        }

        // Unregister log callback
        snapclient_set_log_callback(nil, nil)

        // Must be called from any context, so we capture the ref
        let ref = clientRef
        clientRef = nil
        if let ref {
            // Unregister callbacks before destroying to prevent use-after-free
            snapclient_set_state_callback(ref, nil, nil)
            snapclient_set_settings_callback(ref, nil, nil)
            snapclient_destroy(ref)
        }
    }

    // MARK: - Connection

    /// Connect to a Snapserver and start audio playback.
    /// The connection is performed on a background thread to avoid blocking the UI.
    /// Connection attempts are serialized - a new start() cancels any in-progress connection.
    func start(host: String, port: Int = 1704) {
        // Debug: log raw bytes of host string
        let hostBytes = Array(host.utf8)
        log.info("[\(self.instanceId)] start: host='\(host)' bytes=\(hostBytes) len=\(host.count) port=\(port) state=\(self.state.displayName)")

        // Cancel any pending auto-reconnect to prevent race condition
        reconnectTask?.cancel()
        reconnectTask = nil
        reconnectAttempts = 0

        // Cancel any in-progress connection attempt to prevent racing
        connectionTask?.cancel()

        // Clear connection info immediately to prevent auto-reconnect to old server
        connectedHost = nil
        connectedPort = nil

        // Configure audio session on main thread (AVAudioSession requirement)
        configureAudioSession()

        // Capture values for the background task
        let hostCopy = host
        let portCopy = port
        let instanceId = self.instanceId

        // Store the new connection task so we can cancel it if user switches again
        connectionTask = Task.detached { [self] in
            // Check cancellation early
            guard !Task.isCancelled else {
                await MainActor.run {
                    log.info("[\(instanceId)] connection cancelled before starting")
                }
                return
            }

            // Get ref on MainActor since clientRef is accessed from @MainActor context
            guard let ref = await MainActor.run(body: { self.clientRef }) else {
                await MainActor.run {
                    log.error("[\(instanceId)] start: clientRef is nil!")
                }
                return
            }

            // Stop any existing connection first (C++ returns false if already connected)
            let currentState = snapclient_get_state(ref)
            if currentState != SNAPCLIENT_STATE_DISCONNECTED {
                await MainActor.run {
                    log.info("[\(instanceId)] stopping existing connection before starting new one")
                }
                snapclient_stop(ref)

                // Wait for clean state transition
                try? await Task.sleep(for: .milliseconds(150))

                // Check cancellation after stop - user may have switched servers again
                guard !Task.isCancelled else {
                    await MainActor.run {
                        log.info("[\(instanceId)] connection cancelled after stop")
                    }
                    return
                }
            }

            let success = hostCopy.withCString { cHost in
                snapclient_start(ref, cHost, Int32(portCopy))
            }

            // Check cancellation after connect attempt
            guard !Task.isCancelled else {
                await MainActor.run {
                    log.info("[\(instanceId)] connection cancelled after start, stopping")
                }
                // If we connected but were cancelled, stop immediately
                if success {
                    snapclient_stop(ref)
                }
                return
            }

            // Update state on main thread
            await MainActor.run {
                log.info("[\(instanceId)] snapclient_start returned \(success)")

                if success {
                    self.connectedHost = hostCopy
                    self.connectedPort = portCopy
                    self.lastServer = (hostCopy, portCopy)
                }
            }
        }
    }

    /// Connect to the last saved server, if any.
    func connectToLastServer() {
        guard let server = lastServer else { return }
        start(host: server.host, port: server.port)
    }

    /// Disconnect from the server.
    /// This runs the blocking C++ stop on a background thread to avoid freezing the UI.
    func stop() {
        guard let ref = clientRef else { return }
        log.info("stop: calling snapclient_stop (async)")

        // Cancel any pending reconnect or in-progress connection
        reconnectTask?.cancel()
        reconnectTask = nil
        connectionTask?.cancel()
        connectionTask = nil
        reconnectAttempts = 0

        // Clear state immediately for responsive UI
        connectedHost = nil
        connectedPort = nil

        // Run blocking stop on background thread
        Task.detached {
            snapclient_stop(ref)
        }
    }

    /// Reconnect to the last server.
    func reconnect() {
        guard let host = connectedHost, let port = connectedPort else { return }
        log.info("reconnect: \(host):\(port)")
        // start() already handles stopping if connected
        start(host: host, port: port)
    }

    // MARK: - Playback Control

    /// Pause audio playback while keeping the connection alive.
    /// The client continues to receive audio data and sync with the server.
    func pause() {
        guard let ref = clientRef else { return }
        log.info("pause: pausing audio playback")
        snapclient_pause(ref)
        isPaused = snapclient_is_paused(ref)  // Query actual state
    }

    /// Resume audio playback after a pause.
    func resume() {
        guard let ref = clientRef else { return }
        log.info("resume: resuming audio playback")
        snapclient_resume(ref)
        isPaused = snapclient_is_paused(ref)  // Query actual state
    }

    /// Toggle pause/resume state.
    func togglePlayback() {
        if isPaused {
            resume()
        } else {
            pause()
        }
    }

    // MARK: - Identity

    /// Set the client display name visible on the server.
    func setName(_ name: String) {
        guard let ref = clientRef else { return }
        name.withCString { snapclient_set_name(ref, $0) }
    }

    /// Set instance ID (for multiple clients on the same device).
    func setInstance(_ id: Int) {
        guard let ref = clientRef else { return }
        snapclient_set_instance(ref, Int32(id))
    }

    // MARK: - Version

    /// Snapclient core version string.
    var coreVersion: String {
        String(cString: snapclient_version())
    }

    /// Snapcast protocol version.
    var protocolVersion: Int {
        Int(snapclient_protocol_version())
    }

    /// Test raw TCP connection (bypasses Snapcast protocol).
    /// Returns 0 on success, errno on failure. Check bridgeLogs for details.
    /// Runs on background thread to avoid blocking UI.
    func testTCP(host: String, port: Int = 1704) async -> Int32 {
        log.info("testTCP: \(host):\(port)")
        return await Task.detached {
            host.withCString { cHost in
                snapclient_test_tcp(cHost, Int32(port))
            }
        }.value
    }

    // MARK: - Private helpers

    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            // Use playback category for background audio
            // IMPORTANT: Do NOT use .mixWithOthers or .duckOthers - these are "mixable" options
            // that prevent the app from becoming the "Now Playing" app (per WWDC22 session 110338)
            try session.setCategory(.playback, mode: .default)
            // Request larger IO buffer for more stable playback
            try session.setPreferredIOBufferDuration(0.01) // 10ms

            // Force output to speaker to avoid AirPlay loop
            // (when Tidal sends to Snapserver via AirPlay, we don't want our output going back)
            if forceLocalSpeaker {
                try session.overrideOutputAudioPort(.speaker)
                log.info("Audio forced to local speaker (loop prevention)")
            }

            try session.setActive(true, options: .notifyOthersOnDeactivation)

            // Check for AirPlay output and warn
            checkForAirPlayLoop()

            audioSessionError = nil
            log.info("Audio session configured: sampleRate=\(session.sampleRate), ioBuffer=\(session.ioBufferDuration * 1000)ms")
        } catch {
            log.error("Audio session setup failed: \(error.localizedDescription)")
            audioSessionError = error.localizedDescription
        }
    }

    /// Check if audio is routing to AirPlay (potential loop)
    private func checkForAirPlayLoop() {
        let session = AVAudioSession.sharedInstance()
        let outputs = session.currentRoute.outputs
        let hasAirPlay = outputs.contains { $0.portType == .airPlay }

        if hasAirPlay {
            log.warning("Audio routing to AirPlay detected - may cause loop if Snapserver receives from AirPlay")
            airPlayLoopWarning = true
        } else {
            airPlayLoopWarning = false
        }
    }

    private func applyVolume() {
        guard let ref = clientRef else { return }
        snapclient_set_volume(ref, Int32(volume))
    }

    private func applyMuted() {
        guard let ref = clientRef else { return }
        snapclient_set_muted(ref, isMuted)
    }

    private func applyLatency() {
        guard let ref = clientRef else { return }
        snapclient_set_latency(ref, Int32(latencyMs))
    }

    private func registerCallbacks() {
        guard let ref = clientRef else { return }

        // State callback
        let stateCtx = Unmanaged.passUnretained(self).toOpaque()
        snapclient_set_state_callback(ref, { ctx, rawState in
            guard let ctx else { return }
            let engine = Unmanaged<SnapClientEngine>.fromOpaque(ctx)
                .takeUnretainedValue()
            let newState = SnapClientState(rawValue: Int(rawState.rawValue))
                ?? .disconnected
            Task { @MainActor in
                engine.handleStateChange(newState)
            }
        }, stateCtx)

        // Settings callback (server pushes volume/mute/latency changes)
        snapclient_set_settings_callback(ref, { ctx, vol, muted, latency in
            guard let ctx else { return }
            let engine = Unmanaged<SnapClientEngine>.fromOpaque(ctx)
                .takeUnretainedValue()
            Task { @MainActor in
                engine.volume = Int(vol)
                engine.isMuted = muted
                engine.latencyMs = Int(latency)
            }
        }, stateCtx)
    }

    private func registerLogCallback() {
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        snapclient_set_log_callback({ ctx, level, msg in
            guard let ctx, let msg else { return }
            let engine = Unmanaged<SnapClientEngine>.fromOpaque(ctx)
                .takeUnretainedValue()
            let message = String(cString: msg)
            let prefix: String
            switch level {
            case SNAPCLIENT_LOG_DEBUG:   prefix = "[D]"
            case SNAPCLIENT_LOG_INFO:    prefix = "[I]"
            case SNAPCLIENT_LOG_WARNING: prefix = "[W]"
            case SNAPCLIENT_LOG_ERROR:   prefix = "[E]"
            default:                     prefix = "[?]"
            }
            let line = "\(prefix) \(message)"
            #if DEBUG
            // Also print to stdout for Xcode console
            print("[SnapBridge] \(line)")
            #endif
            Task { @MainActor in
                engine.bridgeLogs.insert(line, at: 0)
                if engine.bridgeLogs.count > engine.maxLogLines {
                    engine.bridgeLogs.removeLast()
                }
            }
        }, ctx)
    }

    private func handleStateChange(_ newState: SnapClientState) {
        let oldState = state
        state = newState
        log.info("state: \(oldState.displayName) -> \(newState.displayName)")

        // Reset reconnect attempts on successful connection
        if newState == .connected || newState == .playing {
            reconnectAttempts = 0
        }

        // Auto-reconnect if we were connected and got disconnected unexpectedly
        if oldState.isActive && newState == .disconnected &&
           autoReconnect && connectedHost != nil {
            log.info("scheduling auto-reconnect (attempt \(self.reconnectAttempts + 1))")
            scheduleReconnect()
        }
    }

    private func scheduleReconnect() {
        reconnectTask?.cancel()

        // Exponential backoff: 2, 4, 8, 16, 32, 60 (capped)
        let delay = min(baseReconnectDelay * pow(2.0, Double(reconnectAttempts)), maxReconnectDelay)
        reconnectAttempts += 1

        reconnectTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self.reconnect()
            }
        }
    }

    private func setupAudioSessionObservers() {
        // Remove existing observers if any (prevents duplicates)
        if let observer = interruptionObserver {
            NotificationCenter.default.removeObserver(observer)
            interruptionObserver = nil
        }
        if let observer = routeChangeObserver {
            NotificationCenter.default.removeObserver(observer)
            routeChangeObserver = nil
        }

        // Audio interruption (phone call, Siri, etc.)
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                self?.handleAudioInterruption(notification)
            }
        }

        // Audio route change (Bluetooth disconnect, headphones unplugged, etc.)
        routeChangeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                self?.handleRouteChange(notification)
            }
        }
    }

    private func handleRouteChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return
        }

        log.info("Audio route changed: \(reason.rawValue)")

        switch reason {
        case .oldDeviceUnavailable:
            // Headphones/Bluetooth disconnected - keep playing through speaker
            log.info("Audio device disconnected, continuing playback")
            // Re-activate audio session to ensure audio continues
            try? AVAudioSession.sharedInstance().setActive(true)

        case .categoryChange:
            // Category changed, might need to reconfigure
            log.info("Audio category changed")

        case .newDeviceAvailable:
            // New device connected (e.g., Bluetooth headphones)
            log.info("New audio device available")
            checkForAirPlayLoop()

        default:
            break
        }
    }

    private func handleAudioInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }

        switch type {
        case .began:
            log.info("Audio interrupted (e.g., phone call)")
            // Don't pause - let the C++ player continue buffering
            // It will output silence during interruption

        case .ended:
            // Interruption ended — check if we should resume
            log.info("Audio interruption ended")
            if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                if options.contains(.shouldResume) && connectedHost != nil {
                    log.info("Resuming after interruption")
                    try? AVAudioSession.sharedInstance().setActive(true)
                }
            }

        @unknown default:
            break
        }
    }
}
