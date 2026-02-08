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


    /// Our unique client ID (matches what engine sets and ContentView uses)
    private var myClientId: String {
        let vendorId = UIDevice.current.identifierForVendor?.uuidString ?? ""
        return "SnapForge-\(vendorId.prefix(8))"
    }

    // MARK: - Lifecycle

    init() {
        setupRemoteCommandCenter()
    }

    deinit {
        // Clean up remote command handlers
        let commandCenter = MPRemoteCommandCenter.shared()
        commandCenter.playCommand.removeTarget(nil)
        commandCenter.pauseCommand.removeTarget(nil)
        commandCenter.togglePlayPauseCommand.removeTarget(nil)

        UIApplication.shared.endReceivingRemoteControlEvents()
    }

    /// Configure the manager with engine and RPC client.
    /// Call this after both are initialized.
    func configure(engine: SnapClientEngine, rpcClient: SnapcastRPCClient) {
        self.engine = engine
        self.rpcClient = rpcClient

        // Log audio session state for debugging
        let session = AVAudioSession.sharedInstance()
        print("[NowPlaying] Audio session - category: \(session.category.rawValue), mode: \(session.mode.rawValue), isOtherAudioPlaying: \(session.isOtherAudioPlaying)")

        // Start receiving remote control events (required for lock screen/Control Center)
        UIApplication.shared.beginReceivingRemoteControlEvents()
        print("[NowPlaying] beginReceivingRemoteControlEvents called")

        // Subscribe to state changes
        setupObservers()

        // Initial update
        updateNowPlayingInfo()

        print("[NowPlaying] Configured with engine and RPC client, clientId=\(myClientId)")
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

        // Add handlers
        commandCenter.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                self?.engine?.resume()
            }
            return .success
        }

        commandCenter.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                self?.engine?.pause()
            }
            return .success
        }

        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            print("[NowPlaying] togglePlayPauseCommand received")
            Task { @MainActor in
                self?.engine?.togglePlayback()
            }
            return .success
        }

        print("[NowPlaying] Remote command center configured - play:\(commandCenter.playCommand.isEnabled) pause:\(commandCenter.pauseCommand.isEnabled) toggle:\(commandCenter.togglePlayPauseCommand.isEnabled)")
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
            print("[NowPlaying] updateNowPlayingInfo: engine is nil")
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }

        print("[NowPlaying] updateNowPlayingInfo: state=\(engine.state.displayName) isActive=\(engine.state.isActive)")

        guard engine.state.isActive else {
            // Clear now playing info when not connected
            print("[NowPlaying] Clearing now playing info (not active)")
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
        // For live streams, set elapsed time to 0 (no seek bar shown)
        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = 0.0

        // Set the info
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
        print("[NowPlaying] Set nowPlayingInfo: title='\(nowPlayingInfo[MPMediaItemPropertyTitle] ?? "nil")' artist='\(nowPlayingInfo[MPMediaItemPropertyArtist] ?? "nil")' playbackRate=\(nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] ?? "nil")")

        // Load artwork if available
        if let artUrlString = metadata?.artUrl, !artUrlString.isEmpty {
            loadArtwork(from: artUrlString)
        }

        print("[NowPlaying] Updated: \(metadata?.artist ?? "?") - \(metadata?.title ?? "?")")
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
            print("[NowPlaying] Client not found for ID: \(myClientId)")
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

                print("[NowPlaying] Artwork loaded from \(urlString)")
            } catch {
                print("[NowPlaying] Failed to load artwork: \(error)")
            }
        }
    }

    private func updateArtwork(_ artwork: MPMediaItemArtwork) {
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        info[MPMediaItemPropertyArtwork] = artwork
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
