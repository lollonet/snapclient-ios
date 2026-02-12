import Foundation
import MediaPlayer
import Combine
import UIKit
import AVFoundation

/// Manages MPNowPlayingInfoCenter and MPRemoteCommandCenter integration.
///
/// This provides:
/// - Lock screen / Control Center now playing info (artist, title, album art)
/// - Play/Pause buttons in Control Center
/// - Headphone/AirPods remote control support
@MainActor
final class NowPlayingManager: ObservableObject {

    // MARK: - Dependencies

    private weak var engine: SnapClientEngine?
    private weak var rpcClient: SnapcastRPCClient?

    // MARK: - Private

    private var cancellables = Set<AnyCancellable>()
    private var artworkCache: [String: MPMediaItemArtwork] = [:]
    private var artworkCacheOrder: [String] = []  // FIFO order for eviction
    private let maxArtworkCacheSize = 20
    private var currentArtworkURL: String?

    // Metadata persistence to prevent flicker during reconnections
    private var lastKnownTitle: String?
    private var lastKnownArtist: String?
    private var lastKnownAlbum: String?
    private var lastKnownArtworkURL: String?
    private var disconnectedSince: Date?
    private let metadataClearDelay: TimeInterval = 5.0  // Only clear after 5 seconds disconnected

    /// URLSession with shorter timeout for artwork requests
    private lazy var artworkSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10  // 10 second timeout
        return URLSession(configuration: config)
    }()

    // Remote command targets for proper cleanup in deinit
    // Marked nonisolated(unsafe) because deinit is always nonisolated, but we need to
    // access these properties for cleanup. This is safe because NowPlayingManager is only
    // created/destroyed on the main thread in practice.
    nonisolated(unsafe) private var playCommandTarget: Any?
    nonisolated(unsafe) private var pauseCommandTarget: Any?
    nonisolated(unsafe) private var toggleCommandTarget: Any?


    // MARK: - Lifecycle

    init() {
        setupRemoteCommandCenter()
    }

    deinit {
        // Clean up remote command handlers - remove only our targets, not all targets
        // Use MainActor.assumeIsolated to trap if unexpectedly called off main thread
        MainActor.assumeIsolated {
            let commandCenter = MPRemoteCommandCenter.shared()
            if let target = playCommandTarget {
                commandCenter.playCommand.removeTarget(target)
            }
            if let target = pauseCommandTarget {
                commandCenter.pauseCommand.removeTarget(target)
            }
            if let target = toggleCommandTarget {
                commandCenter.togglePlayPauseCommand.removeTarget(target)
            }
        }
        // Note: Don't call endReceivingRemoteControlEvents here - it's started in SnapClientApp.init
        // and should persist for the app's lifetime
    }

    /// Configure the manager with engine and RPC client.
    /// Call this after both are initialized.
    func configure(engine: SnapClientEngine, rpcClient: SnapcastRPCClient) {
        self.engine = engine
        self.rpcClient = rpcClient

        // Log audio session state for debugging
        #if DEBUG
        let session = AVAudioSession.sharedInstance()
        print("[NowPlaying] Audio session - category: \(session.category.rawValue), mode: \(session.mode.rawValue), isOtherAudioPlaying: \(session.isOtherAudioPlaying)")
        #endif

        // Note: beginReceivingRemoteControlEvents is called in SnapClientApp.init() at app launch
        // This ensures remote events are received from the very start of the app lifecycle

        // Subscribe to state changes
        setupObservers()

        // Initial update
        updateNowPlayingInfo()

        #if DEBUG
        print("[NowPlaying] Configured with engine and RPC client, clientId=\(SnapClientEngine.uniqueClientId)")
        #endif
    }

    // MARK: - Remote Command Center

    private func setupRemoteCommandCenter() {
        let commandCenter = MPRemoteCommandCenter.shared()

        // Enable play/pause commands
        commandCenter.playCommand.isEnabled = true
        commandCenter.pauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.isEnabled = true

        // Disable unsupported commands
        commandCenter.nextTrackCommand.isEnabled = false
        commandCenter.previousTrackCommand.isEnabled = false
        commandCenter.seekForwardCommand.isEnabled = false
        commandCenter.seekBackwardCommand.isEnabled = false
        commandCenter.changePlaybackPositionCommand.isEnabled = false

        // Add handlers and store targets for cleanup
        // Return .commandFailed if self or engine is nil to properly signal command failure
        playCommandTarget = commandCenter.playCommand.addTarget { [weak self] _ in
            guard let self = self, self.engine != nil else {
                return .commandFailed
            }
            Task { @MainActor in
                self.engine?.resume()
            }
            return .success
        }

        pauseCommandTarget = commandCenter.pauseCommand.addTarget { [weak self] _ in
            guard let self = self, self.engine != nil else {
                return .commandFailed
            }
            Task { @MainActor in
                self.engine?.pause()
            }
            return .success
        }

        toggleCommandTarget = commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self = self, self.engine != nil else {
                return .commandFailed
            }
            #if DEBUG
            print("[NowPlaying] togglePlayPauseCommand received")
            #endif
            Task { @MainActor in
                self.engine?.togglePlayback()
            }
            return .success
        }

        #if DEBUG
        print("[NowPlaying] Remote command center configured - play:\(commandCenter.playCommand.isEnabled) pause:\(commandCenter.pauseCommand.isEnabled) toggle:\(commandCenter.togglePlayPauseCommand.isEnabled)")
        #endif
    }

    // MARK: - Observers

    private func setupObservers() {
        guard let engine, let rpcClient else { return }

        // Observe engine state changes
        engine.$state
            .sink { [weak self] _ in
                self?.updateNowPlayingInfo()
            }
            .store(in: &cancellables)

        engine.$isPaused
            .sink { [weak self] _ in
                self?.updateNowPlayingInfo()
            }
            .store(in: &cancellables)

        // Observe server status changes (for metadata)
        rpcClient.$serverStatus
            .sink { [weak self] _ in
                self?.updateNowPlayingInfo()
            }
            .store(in: &cancellables)
    }

    // MARK: - Now Playing Info

    private func updateNowPlayingInfo() {
        guard let engine else {
            #if DEBUG
            print("[NowPlaying] updateNowPlayingInfo: engine is nil")
            #endif
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }

        #if DEBUG
        print("[NowPlaying] updateNowPlayingInfo: state=\(engine.state.displayName) isActive=\(engine.state.isActive)")
        #endif

        // Handle disconnected state with delayed clearing
        guard engine.state.isActive else {
            // Track when we became disconnected and schedule delayed clear
            if disconnectedSince == nil {
                disconnectedSince = Date()

                // Schedule a check after the delay to clear metadata if still disconnected
                // Capture delay value outside Task to avoid accessing self in sleep duration
                let delay = metadataClearDelay
                Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .seconds(delay))
                    // Re-trigger update which will clear if still disconnected
                    self?.updateNowPlayingInfo()
                }
            }

            // Only clear metadata after being disconnected for metadataClearDelay seconds
            if let since = disconnectedSince,
               Date().timeIntervalSince(since) > metadataClearDelay {
                #if DEBUG
                print("[NowPlaying] Clearing now playing info (disconnected > \(metadataClearDelay)s)")
                #endif
                MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
                lastKnownTitle = nil
                lastKnownArtist = nil
                lastKnownAlbum = nil
                lastKnownArtworkURL = nil
            } else {
                #if DEBUG
                print("[NowPlaying] Keeping cached metadata (disconnected < \(metadataClearDelay)s)")
                #endif
                // Keep showing last known info with paused state
                if lastKnownTitle != nil || lastKnownArtist != nil {
                    var nowPlayingInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
                    nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = 0.0
                    MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
                }
            }
            return
        }

        // We're active - clear disconnected timestamp
        disconnectedSince = nil

        // Get current stream metadata
        let metadata = currentStreamMetadata()

        // Use current metadata or fall back to cached
        let title = metadata?.title ?? lastKnownTitle ?? "Snapcast"
        let artist = metadata?.artist ?? lastKnownArtist ?? "Unknown Artist"
        let album = metadata?.album ?? lastKnownAlbum ?? ""

        // Cache valid metadata
        if let m = metadata {
            if let t = m.title, !t.isEmpty { lastKnownTitle = t }
            if let a = m.artist, !a.isEmpty { lastKnownArtist = a }
            if let al = m.album, !al.isEmpty { lastKnownAlbum = al }
            if let art = m.artUrl, !art.isEmpty { lastKnownArtworkURL = art }
        }

        var nowPlayingInfo: [String: Any] = [:]

        // Basic info
        nowPlayingInfo[MPMediaItemPropertyTitle] = title
        nowPlayingInfo[MPMediaItemPropertyArtist] = artist
        nowPlayingInfo[MPMediaItemPropertyAlbumTitle] = album
        nowPlayingInfo[MPMediaItemPropertyMediaType] = MPMediaType.anyAudio.rawValue

        // Playback state - only show rate of 1.0 if actually playing (connected + not paused)
        let isActuallyPlaying = engine.state == .playing && !engine.isPaused
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = isActuallyPlaying ? 1.0 : 0.0
        nowPlayingInfo[MPNowPlayingInfoPropertyIsLiveStream] = true
        // For live streams, explicitly set no seekable duration and elapsed time
        nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = 0.0
        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = 0.0

        // Set the info
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
        #if DEBUG
        print("[NowPlaying] Set nowPlayingInfo: title='\(title)' artist='\(artist)' playbackRate=\(nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] ?? "nil")")
        #endif

        // Load artwork: prefer embedded (base64) over URL
        if let artData = metadata?.artData, !artData.isEmpty {
            loadEmbeddedArtwork(base64: artData)
        } else {
            let artUrlString = metadata?.artUrl ?? lastKnownArtworkURL
            if let artUrl = artUrlString, !artUrl.isEmpty {
                loadArtwork(from: artUrl)
            }
        }

        #if DEBUG
        print("[NowPlaying] Updated: \(artist) - \(title)")
        #endif
    }

    private func currentStreamMetadata() -> SnapcastStream.StreamMetadata? {
        guard let rpcClient,
              let status = rpcClient.serverStatus else {
            return nil
        }

        // Find our client by matching our unique client ID
        let ourClient = status.allClients.first { client in
            client.id == SnapClientEngine.uniqueClientId
        }

        guard let client = ourClient else {
            #if DEBUG
            print("[NowPlaying] Client not found for ID: \(SnapClientEngine.uniqueClientId)")
            #endif
            return nil
        }

        // Find the group containing our client, then get its stream
        for group in status.groups {
            if group.clients.contains(where: { $0.id == client.id }) {
                if let stream = status.streams.first(where: { $0.id == group.stream_id }) {
                    return stream.properties?.metadata
                }
            }
        }

        return nil
    }

    // MARK: - Artwork Loading

    /// Load artwork from embedded base64 data (from MPD, AirPlay, etc.)
    private func loadEmbeddedArtwork(base64: String) {
        // Use hash of base64 as cache key (base64 itself is too long)
        let cacheKey = "embedded:\(base64.hashValue)"

        // Check cache first
        if let cached = artworkCache[cacheKey] {
            updateArtwork(cached)
            return
        }

        // Don't reload if already loading this artwork
        guard cacheKey != currentArtworkURL else { return }
        currentArtworkURL = cacheKey

        // Decode base64 on background thread
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let data = Data(base64Encoded: base64),
                  let image = UIImage(data: data) else {
                #if DEBUG
                print("[NowPlaying] Failed to decode embedded artwork")
                #endif
                return
            }

            // Decompress image - use explicit format to avoid UIScreen.main access on background thread
            let format = UIGraphicsImageRendererFormat.preferred()
            format.scale = image.scale
            format.opaque = false
            format.preferredRange = .standard  // Prevent 'visual style' warnings

            let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
            let decompressedImage = renderer.image { context in
                image.draw(at: .zero)
            }

            let finalImage: UIImage
            if #available(iOS 15.0, *) {
                finalImage = await decompressedImage.byPreparingForDisplay() ?? decompressedImage
            } else {
                finalImage = decompressedImage
            }

            await MainActor.run { [weak self, cacheKey] in
                guard let self else { return }
                let artwork = MPMediaItemArtwork(boundsSize: finalImage.size) { _ in finalImage }
                cacheArtwork(artwork, for: cacheKey)

                if currentArtworkURL == cacheKey {
                    updateArtwork(artwork)
                }

                #if DEBUG
                print("[NowPlaying] Loaded embedded artwork")
                #endif
            }
        }
    }

    /// Load artwork from URL (fallback when embedded not available)
    private func loadArtwork(from urlString: String) {
        // Convert HTTP to HTTPS using shared utility
        guard let url = URL.secureURL(from: urlString) else { return }
        let cacheKey = url.absoluteString

        // Check cache first
        if let cached = artworkCache[cacheKey] {
            updateArtwork(cached)
            return
        }

        // Don't reload if already loading this URL
        guard cacheKey != currentArtworkURL else { return }
        currentArtworkURL = cacheKey

        Task {
            do {
                // Use artwork session with shorter timeout
                let (data, _) = try await artworkSession.data(from: url)

                // PERFORMANCE FIX: Decompress image on background thread
                // This prevents UI hitches from 4K album art blocking the Main Actor
                let preparedImage: UIImage? = await Task.detached(priority: .userInitiated) {
                    guard let image = UIImage(data: data) else { return nil }

                    // Force decompression by drawing into a graphics context
                    // This ensures the expensive JPEG/PNG decode happens off MainActor
                    // Use preferred() and explicit preferredRange to avoid UIScreen.main access
                    let format = UIGraphicsImageRendererFormat.preferred()
                    format.scale = image.scale
                    format.opaque = false
                    format.preferredRange = .standard  // Prevent 'visual style' warnings

                    let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
                    let decompressedImage = renderer.image { context in
                        image.draw(at: .zero)
                    }

                    // Use preparingForDisplay for additional optimization if available
                    if #available(iOS 15.0, *) {
                        return await decompressedImage.byPreparingForDisplay()
                    }
                    return decompressedImage
                }.value

                guard let preparedImage else { return }

                // Now on MainActor, the image is fully decoded and ready
                await MainActor.run { [cacheKey] in
                    // Capture prepared image - it's already decompressed
                    let capturedImage = preparedImage
                    let artwork = MPMediaItemArtwork(boundsSize: capturedImage.size) { _ in capturedImage }

                    // Cache it with FIFO eviction
                    cacheArtwork(artwork, for: cacheKey)

                    // Update if still current
                    if currentArtworkURL == cacheKey {
                        updateArtwork(artwork)
                    }

                    #if DEBUG
                    print("[NowPlaying] Artwork loaded from \(cacheKey)")
                    #endif
                }
            } catch {
                #if DEBUG
                print("[NowPlaying] Failed to load artwork: \(error)")
                #endif
            }
        }
    }

    /// Cache artwork with FIFO eviction when cache is full
    private func cacheArtwork(_ artwork: MPMediaItemArtwork, for url: String) {
        // Remove existing entry from order list to prevent duplicates
        if artworkCache[url] != nil {
            artworkCacheOrder.removeAll { $0 == url }
        }

        artworkCache[url] = artwork
        artworkCacheOrder.append(url)

        // Evict oldest entries if cache is too large
        while artworkCache.count > maxArtworkCacheSize, let oldest = artworkCacheOrder.first {
            artworkCacheOrder.removeFirst()
            artworkCache.removeValue(forKey: oldest)
        }
    }

    private func updateArtwork(_ artwork: MPMediaItemArtwork) {
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        info[MPMediaItemPropertyArtwork] = artwork
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
