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
    private var currentArtworkURL: String?

    // Remote command targets for proper cleanup in deinit
    // Marked nonisolated(unsafe) because deinit is always nonisolated, but we need to
    // access these properties for cleanup. This is safe because NowPlayingManager is only
    // created/destroyed on the main thread in practice.
    nonisolated(unsafe) private var playCommandTarget: Any?
    nonisolated(unsafe) private var pauseCommandTarget: Any?
    nonisolated(unsafe) private var toggleCommandTarget: Any?


    /// Our unique client ID - uses the shared static property from SnapClientEngine
    private var myClientId: String {
        SnapClientEngine.uniqueClientId
    }

    // MARK: - Lifecycle

    init() {
        setupRemoteCommandCenter()
    }

    deinit {
        // Clean up remote command handlers - remove only our targets, not all targets
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
        print("[NowPlaying] Configured with engine and RPC client, clientId=\(myClientId)")
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
        playCommandTarget = commandCenter.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                self?.engine?.resume()
            }
            return .success
        }

        pauseCommandTarget = commandCenter.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                self?.engine?.pause()
            }
            return .success
        }

        toggleCommandTarget = commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            #if DEBUG
            print("[NowPlaying] togglePlayPauseCommand received")
            #endif
            Task { @MainActor in
                self?.engine?.togglePlayback()
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

        guard engine.state.isActive else {
            // Clear now playing info when not connected
            #if DEBUG
            print("[NowPlaying] Clearing now playing info (not active)")
            #endif
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }

        // Get current stream metadata
        let metadata = currentStreamMetadata()

        var nowPlayingInfo: [String: Any] = [:]

        // Basic info
        nowPlayingInfo[MPMediaItemPropertyTitle] = metadata?.title ?? "Snapcast"
        nowPlayingInfo[MPMediaItemPropertyArtist] = metadata?.artist ?? "Unknown Artist"
        nowPlayingInfo[MPMediaItemPropertyAlbumTitle] = metadata?.album ?? ""
        nowPlayingInfo[MPMediaItemPropertyMediaType] = MPMediaType.anyAudio.rawValue

        // Playback state - set both rate AND explicitly mark as live stream
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = engine.isPaused ? 0.0 : 1.0
        nowPlayingInfo[MPNowPlayingInfoPropertyIsLiveStream] = true
        // For live streams, explicitly set no seekable duration and elapsed time
        nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = 0.0
        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = 0.0

        // Set the info
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
        #if DEBUG
        print("[NowPlaying] Set nowPlayingInfo: title='\(nowPlayingInfo[MPMediaItemPropertyTitle] ?? "nil")' artist='\(nowPlayingInfo[MPMediaItemPropertyArtist] ?? "nil")' playbackRate=\(nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] ?? "nil")")
        #endif

        // Load artwork if available
        if let artUrlString = metadata?.artUrl, !artUrlString.isEmpty {
            loadArtwork(from: artUrlString)
        }

        #if DEBUG
        print("[NowPlaying] Updated: \(metadata?.artist ?? "?") - \(metadata?.title ?? "?")")
        #endif
    }

    private func currentStreamMetadata() -> SnapcastStream.StreamMetadata? {
        guard let rpcClient,
              let status = rpcClient.serverStatus else {
            return nil
        }

        // Find our client by matching our unique client ID
        let ourClient = status.allClients.first { client in
            client.id == myClientId
        }

        guard let client = ourClient else {
            #if DEBUG
            print("[NowPlaying] Client not found for ID: \(myClientId)")
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

    private func loadArtwork(from urlString: String) {
        // Check cache first
        if let cached = artworkCache[urlString] {
            updateArtwork(cached)
            return
        }

        // Don't reload if already loading this URL
        guard urlString != currentArtworkURL else { return }
        currentArtworkURL = urlString

        guard let url = URL(string: urlString) else { return }

        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                guard let image = UIImage(data: data) else { return }

                let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }

                // Cache it
                artworkCache[urlString] = artwork

                // Update if still current
                if currentArtworkURL == urlString {
                    updateArtwork(artwork)
                }

                #if DEBUG
                print("[NowPlaying] Artwork loaded from \(urlString)")
                #endif
            } catch {
                #if DEBUG
                print("[NowPlaying] Failed to load artwork: \(error)")
                #endif
            }
        }
    }

    private func updateArtwork(_ artwork: MPMediaItemArtwork) {
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        info[MPMediaItemPropertyArtwork] = artwork
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
