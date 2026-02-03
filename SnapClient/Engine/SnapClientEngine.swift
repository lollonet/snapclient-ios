import Foundation
import Combine

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

    // MARK: - Server info

    @Published private(set) var connectedHost: String?
    @Published private(set) var connectedPort: Int?

    // MARK: - Private

    private var clientRef: SnapClientRef?

    // MARK: - Lifecycle

    init() {
        clientRef = snapclient_create()
        guard clientRef != nil else {
            fatalError("Failed to create snapclient instance")
        }
        registerCallbacks()
    }

    deinit {
        // Must be called from any context, so we capture the ref
        let ref = clientRef
        clientRef = nil
        if let ref {
            snapclient_destroy(ref)
        }
    }

    // MARK: - Connection

    /// Connect to a Snapserver and start audio playback.
    func start(host: String, port: Int = 1704) {
        guard let ref = clientRef else { return }

        // Configure audio session for background playback
        snapclient_configure_audio_session()

        let success = host.withCString { cHost in
            snapclient_start(ref, cHost, Int32(port))
        }

        if success {
            connectedHost = host
            connectedPort = port
        }
    }

    /// Disconnect from the server.
    func stop() {
        guard let ref = clientRef else { return }
        snapclient_stop(ref)
        connectedHost = nil
        connectedPort = nil
    }

    /// Reconnect to the last server.
    func reconnect() {
        guard let host = connectedHost, let port = connectedPort else { return }
        stop()
        start(host: host, port: port)
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

    // MARK: - Private helpers

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
                engine.state = newState
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
}
