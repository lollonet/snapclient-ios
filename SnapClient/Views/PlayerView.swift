import SwiftUI
import UIKit

/// Main player view with now playing info, volume control, and playback buttons.
struct PlayerView: View {
    @EnvironmentObject var engine: SnapClientEngine
    @EnvironmentObject var discovery: ServerDiscovery
    @EnvironmentObject var rpcClient: SnapcastRPCClient

    @State private var showTechnicalDetails = false

    /// Our unique client ID - uses the shared static property from SnapClientEngine
    private var myClientId: String {
        SnapClientEngine.uniqueClientId
    }

    /// Find our client in the server status by matching our unique ID.
    private var currentClient: SnapcastClient? {
        guard let clients = rpcClient.serverStatus?.allClients else { return nil }
        return clients.first { $0.id == myClientId }
    }

    /// Server-side volume for our client (for change observation)
    private var serverVolume: Int {
        currentClient?.config.volume.percent ?? 100
    }

    /// Server-side mute state for our client
    private var serverMuted: Bool {
        currentClient?.config.volume.muted ?? false
    }

    /// Current stream (for now playing info)
    private var currentStream: SnapcastStream? {
        guard let status = rpcClient.serverStatus,
              let client = currentClient else { return nil }
        // Find the group containing our client, then get its stream
        for group in status.groups {
            if group.clients.contains(where: { $0.id == client.id }) {
                return status.streams.first { $0.id == group.stream_id }
            }
        }
        return nil
    }

    /// Adaptive album art size based on screen width
    private var adaptiveAlbumSize: CGFloat {
        let screenWidth = UIScreen.main.bounds.width
        return min(max(screenWidth * 0.55, 160), 280)
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ScrollView {
                    VStack(spacing: 20) {
                        // AirPlay loop warning
                        airPlayWarningBanner

                        // Now playing info at top
                        nowPlayingSection

                        Spacer(minLength: 16)

                        // Controls card (status + volume + buttons)
                        controlsCard
                    }
                    .padding()
                    .frame(minHeight: geometry.size.height)
                }
            }
            .navigationTitle("SnapCTRL")
            .onAppear {
                discovery.startBrowsing()
            }
        }
    }

    // MARK: - AirPlay Warning

    @ViewBuilder
    private var airPlayWarningBanner: some View {
        if engine.airPlayLoopWarning {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                Text("AirPlay active - possible audio loop")
                    .font(.caption)
                Spacer()
                Toggle("", isOn: $engine.forceLocalSpeaker)
                    .labelsHidden()
            }
            .padding(8)
            .background(.yellow.opacity(0.2), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    // MARK: - Now Playing Section

    private var nowPlayingSection: some View {
        Group {
            if let stream = currentStream,
               let meta = stream.properties?.metadata,
               meta.title != nil || meta.artist != nil {
                VStack(spacing: 16) {
                    // Cover art with adaptive sizing
                    // Priority: embedded base64 > URL (with HTTP→HTTPS)
                    if let artData = meta.artData,
                       let data = Data(base64Encoded: artData),
                       let uiImage = UIImage(data: data) {
                        // Embedded artwork from MPD/AirPlay
                        Image(uiImage: uiImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: adaptiveAlbumSize, height: adaptiveAlbumSize)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
                    } else if let artUrlString = meta.artUrl,
                              let artUrl = Self.secureURL(from: artUrlString) {
                        // URL artwork (with HTTP→HTTPS conversion)
                        AsyncImage(url: artUrl) { phase in
                            switch phase {
                            case .empty:
                                ProgressView()
                                    .frame(width: adaptiveAlbumSize, height: adaptiveAlbumSize)
                            case .success(let image):
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: adaptiveAlbumSize, height: adaptiveAlbumSize)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
                            case .failure:
                                albumPlaceholder
                            @unknown default:
                                albumPlaceholder
                            }
                        }
                    } else {
                        albumPlaceholder
                    }

                    // Track info
                    VStack(spacing: 4) {
                        if let title = meta.title {
                            Text(title)
                                .font(.headline)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                        }
                        if let artist = meta.artist {
                            Text(artist)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        if let album = meta.album {
                            Text(album)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            }
        }
    }

    private var albumPlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(.secondary.opacity(0.15))
            Image(systemName: "music.note")
                .font(.system(size: adaptiveAlbumSize * 0.3))
                .foregroundStyle(.secondary.opacity(0.5))
        }
        .frame(width: adaptiveAlbumSize, height: adaptiveAlbumSize)
    }

    /// Convert HTTP URLs to HTTPS for App Transport Security compliance
    private static func secureURL(from urlString: String) -> URL? {
        let secure = urlString.hasPrefix("http://")
            ? urlString.replacingOccurrences(of: "http://", with: "https://")
            : urlString
        return URL(string: secure)
    }

    // MARK: - Controls Card

    private var controlsCard: some View {
        VStack(spacing: 16) {
            statusView
            Divider()
            volumeSection
            controlButtons
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Status View

    /// Server hostname from discovery
    private var serverHostname: String? {
        guard let host = engine.connectedHost else { return nil }
        return discovery.servers.first { $0.host == host }?.displayName
    }

    private var statusView: some View {
        VStack(spacing: 8) {
            // Primary: Connection state with indicator
            HStack(spacing: 8) {
                Circle()
                    .fill(engine.state.isActive ? .green : .secondary)
                    .frame(width: 10, height: 10)
                Text(engine.state.displayName)
                    .font(.headline)
            }

            // Secondary: Server name (always visible when connected)
            if let hostname = serverHostname {
                Text(hostname)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            // Tertiary: Technical details (collapsible)
            if engine.state.isActive {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showTechnicalDetails.toggle()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(showTechnicalDetails ? "Hide Details" : "Details")
                            .font(.caption)
                        Image(systemName: showTechnicalDetails ? "chevron.up" : "chevron.down")
                            .font(.caption2)
                    }
                    .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)

                if showTechnicalDetails {
                    technicalDetailsView
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Status: \(engine.state.displayName)\(engine.connectedHost.map { ", connected to \($0)" } ?? "")")
    }

    private var technicalDetailsView: some View {
        VStack(spacing: 4) {
            if let host = engine.connectedHost {
                Text(host)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            if let client = currentClient {
                Text("ID: \(client.id)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                if !client.config.name.isEmpty {
                    Text("Name: \(client.config.name)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            } else {
                Text("ID: \(myClientId)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Text("(not found on server)")
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
        }
    }

    // MARK: - Volume Section

    private var volumeSection: some View {
        SnapVolumeControl(
            serverValue: serverVolume,
            isMuted: serverMuted,
            onVolumeCommit: { newPercent in
                guard let client = currentClient else { return }
                try await rpcClient.setClientVolume(
                    clientId: client.id,
                    volume: ClientVolume(percent: newPercent, muted: serverMuted)
                )
                await rpcClient.refreshStatus()
            },
            onMuteToggle: {
                guard let client = currentClient else { return }
                try await rpcClient.setClientVolume(
                    clientId: client.id,
                    volume: ClientVolume(percent: serverVolume, muted: !serverMuted)
                )
                await rpcClient.refreshStatus()
            },
            onError: { error in
                rpcClient.handleError(error)
            }
        )
        .disabled(currentClient == nil)
    }

    // MARK: - Control Buttons

    private var controlButtons: some View {
        HStack(spacing: 20) {
            if engine.state.isActive {
                // Play/Pause button
                Button {
                    engine.togglePlayback()
                } label: {
                    Label(
                        engine.isPaused ? "Play" : "Pause",
                        systemImage: engine.isPaused ? "play.fill" : "pause.fill"
                    )
                    .font(.title2)
                }
                .buttonStyle(.borderedProminent)
                .tint(engine.isPaused ? .green : .orange)
                .accessibilityHint(engine.isPaused ? "Resume audio playback" : "Pause audio playback")

                // Disconnect button
                Button(role: .destructive) {
                    engine.stop()
                    rpcClient.disconnect()
                } label: {
                    Label("Disconnect", systemImage: "xmark.circle.fill")
                        .font(.title2)
                }
                .buttonStyle(.bordered)
                .accessibilityHint("Disconnects from the Snapcast server")
            } else {
                // Connect to first discovered server, or prompt to go to Servers tab
                Button {
                    if let server = discovery.servers.first {
                        // Disconnect old connections first for clean switch
                        rpcClient.disconnect()
                        engine.start(host: server.host, port: server.port)
                        rpcClient.connect(host: server.host, port: server.controlPort)
                    }
                } label: {
                    Label("Connect", systemImage: "play.fill")
                        .font(.title2)
                }
                .buttonStyle(.borderedProminent)
                .disabled(discovery.servers.isEmpty)
                .accessibilityHint(discovery.servers.isEmpty
                    ? "No servers found. Go to Servers tab to search or enter manually."
                    : "Connects to \(discovery.servers.first?.displayName ?? "server")")
            }
        }
    }
}
