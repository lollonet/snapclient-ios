import SwiftUI
import UIKit

/// Main player view with now playing info, volume control, and playback buttons.
struct PlayerView: View {
    @EnvironmentObject var engine: SnapClientEngine
    @EnvironmentObject var discovery: ServerDiscovery
    @EnvironmentObject var rpcClient: SnapcastRPCClient

    /// Our unique client ID (matches what engine sets)
    private var myClientId: String {
        let vendorId = UIDevice.current.identifierForVendor?.uuidString ?? ""
        return "SnapForge-\(vendorId.prefix(8))"
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

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // AirPlay loop warning
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

                // Now playing info at top
                nowPlayingSection

                Spacer()

                // Status indicator
                statusView

                // Volume control
                volumeSection

                // Playback controls
                controlButtons

                Spacer()
            }
            .padding()
            .navigationTitle("SnapForge")
            .onAppear {
                discovery.startBrowsing()
            }
        }
    }

    private var nowPlayingSection: some View {
        Group {
            if let stream = currentStream,
               let meta = stream.properties?.metadata,
               meta.title != nil || meta.artist != nil {
                VStack(spacing: 16) {
                    // Cover art
                    if let artUrlString = meta.artUrl,
                       let artUrl = URL(string: artUrlString) {
                        AsyncImage(url: artUrl) { phase in
                            switch phase {
                            case .empty:
                                ProgressView()
                                    .frame(width: 200, height: 200)
                            case .success(let image):
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 200, height: 200)
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
                                .lineLimit(1)
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
                        Text(stream.id)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private var albumPlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(.secondary.opacity(0.15))
            Image(systemName: "music.note")
                .font(.system(size: 60))
                .foregroundStyle(.secondary.opacity(0.5))
        }
        .frame(width: 200, height: 200)
    }

    /// Server hostname from discovery
    private var serverHostname: String? {
        guard let host = engine.connectedHost else { return nil }
        return discovery.servers.first { $0.host == host }?.displayName
    }

    private var statusView: some View {
        VStack(spacing: 8) {
            Text(engine.state.displayName)
                .font(.headline)
                .foregroundStyle(engine.state.isActive ? .green : .secondary)

            // Server info: FQDN and IP
            if let host = engine.connectedHost {
                VStack(spacing: 2) {
                    if let hostname = serverHostname {
                        Text(hostname)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(host)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            // Client info
            if engine.state.isActive {
                VStack(spacing: 4) {
                    Divider().frame(width: 100)
                    if let client = currentClient {
                        Text("Client ID: \(client.id)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        if !client.config.name.isEmpty {
                            Text("Name: \(client.config.name)")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    } else {
                        Text("Client ID: \(myClientId)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("(not found on server)")
                            .font(.caption2)
                            .foregroundStyle(.red)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Status: \(engine.state.displayName)\(engine.connectedHost.map { ", connected to \($0)" } ?? "")")
    }

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
        .padding(.horizontal)
        .disabled(currentClient == nil)
    }

    private var controlButtons: some View {
        HStack(spacing: 24) {
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
