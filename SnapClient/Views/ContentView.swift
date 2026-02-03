import SwiftUI

struct ContentView: View {
    @EnvironmentObject var engine: SnapClientEngine
    @EnvironmentObject var discovery: ServerDiscovery
    @EnvironmentObject var rpcClient: SnapcastRPCClient

    var body: some View {
        TabView {
            PlayerView()
                .tabItem {
                    Label("Player", systemImage: "play.circle.fill")
                }

            GroupsView()
                .tabItem {
                    Label("Groups", systemImage: "rectangle.3.group")
                }

            ServersView()
                .tabItem {
                    Label("Servers", systemImage: "network")
                }
        }
    }
}

// MARK: - Player View

struct PlayerView: View {
    @EnvironmentObject var engine: SnapClientEngine

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
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
        }
    }

    private var statusView: some View {
        VStack(spacing: 8) {
            Image(systemName: engine.state.isActive ? "speaker.wave.3.fill" : "speaker.slash")
                .font(.system(size: 64))
                .foregroundStyle(engine.state.isActive ? .green : .secondary)
                .symbolEffect(.variableColor, isActive: engine.state == .playing)

            Text(engine.state.displayName)
                .font(.headline)
                .foregroundStyle(.secondary)

            if let host = engine.connectedHost {
                Text(host)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var volumeSection: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "speaker.fill")
                    .foregroundStyle(.secondary)
                Slider(value: volumeBinding, in: 0...100, step: 1)
                Image(systemName: "speaker.wave.3.fill")
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text("\(engine.volume)%")
                    .font(.caption)
                    .monospacedDigit()
                Spacer()
                Button {
                    engine.isMuted.toggle()
                } label: {
                    Image(systemName: engine.isMuted ? "speaker.slash.fill" : "speaker.fill")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.horizontal)
    }

    private var volumeBinding: Binding<Double> {
        Binding(
            get: { Double(engine.volume) },
            set: { engine.volume = Int($0) }
        )
    }

    private var controlButtons: some View {
        HStack(spacing: 24) {
            if engine.state.isActive {
                Button(role: .destructive) {
                    engine.stop()
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                        .font(.title2)
                }
                .buttonStyle(.borderedProminent)
            } else {
                // Show when disconnected — auto-connect to first discovered server
                Button {
                    // Will be wired to discovery in ServersView
                } label: {
                    Label("Connect", systemImage: "play.fill")
                        .font(.title2)
                }
                .buttonStyle(.borderedProminent)
                .disabled(true) // Enable after server selection
            }
        }
    }
}

// MARK: - Groups View

struct GroupsView: View {
    @EnvironmentObject var rpcClient: SnapcastRPCClient

    var body: some View {
        NavigationStack {
            Group {
                if let status = rpcClient.serverStatus {
                    List {
                        ForEach(status.groups) { group in
                            GroupSection(group: group)
                        }

                        if !status.streams.isEmpty {
                            Section("Streams") {
                                ForEach(status.streams) { stream in
                                    StreamRow(stream: stream)
                                }
                            }
                        }
                    }
                } else if rpcClient.isConnected {
                    ProgressView("Loading...")
                } else {
                    ContentUnavailableView(
                        "Not Connected",
                        systemImage: "network.slash",
                        description: Text("Connect to a Snapcast server to manage groups and clients.")
                    )
                }
            }
            .navigationTitle("Groups")
            .refreshable {
                await rpcClient.refreshStatus()
            }
        }
    }
}

struct GroupSection: View {
    let group: SnapcastGroup
    @EnvironmentObject var rpcClient: SnapcastRPCClient

    var body: some View {
        Section {
            ForEach(group.clients) { client in
                ClientRow(client: client)
            }
        } header: {
            HStack {
                Text(group.name.isEmpty ? "Group" : group.name)
                Spacer()
                if group.muted {
                    Image(systemName: "speaker.slash.fill")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct ClientRow: View {
    let client: SnapcastClient
    @EnvironmentObject var rpcClient: SnapcastRPCClient

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Circle()
                    .fill(client.connected ? .green : .red)
                    .frame(width: 8, height: 8)
                Text(client.config.name.isEmpty ? (client.host?.name ?? client.id) : client.config.name)
                    .font(.body)
                Spacer()
                Text("\(client.config.volume.percent)%")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            Slider(
                value: Binding(
                    get: { Double(client.config.volume.percent) },
                    set: { newVal in
                        Task {
                            try? await rpcClient.setClientVolume(
                                clientId: client.id,
                                volume: ClientVolume(percent: Int(newVal), muted: client.config.volume.muted)
                            )
                            await rpcClient.refreshStatus()
                        }
                    }
                ),
                in: 0...100,
                step: 1
            )
        }
        .padding(.vertical, 2)
    }
}

struct StreamRow: View {
    let stream: SnapcastStream

    var body: some View {
        HStack {
            Image(systemName: stream.status == "playing" ? "music.note" : "pause.circle")
                .foregroundStyle(stream.status == "playing" ? .green : .secondary)
            VStack(alignment: .leading) {
                Text(stream.id)
                    .font(.body)
                if let meta = stream.properties?.metadata,
                   let title = meta.title {
                    Text("\(meta.artist ?? "Unknown") — \(title)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Servers View

struct ServersView: View {
    @EnvironmentObject var engine: SnapClientEngine
    @EnvironmentObject var discovery: ServerDiscovery
    @EnvironmentObject var rpcClient: SnapcastRPCClient

    @State private var manualHost = ""
    @State private var manualPort = "1704"

    var body: some View {
        NavigationStack {
            List {
                // Discovered servers
                Section("Discovered") {
                    if discovery.servers.isEmpty {
                        HStack {
                            if discovery.isSearching {
                                ProgressView()
                                    .padding(.trailing, 4)
                                Text("Searching...")
                            } else {
                                Text("No servers found")
                            }
                        }
                        .foregroundStyle(.secondary)
                    } else {
                        ForEach(discovery.servers) { server in
                            Button {
                                connectTo(host: server.host, port: server.port)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(server.displayName)
                                            .font(.body)
                                        Text("\(server.host):\(server.port)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if engine.connectedHost == server.host {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.green)
                                    }
                                }
                            }
                        }
                    }
                }

                // Manual connection
                Section("Manual Connection") {
                    TextField("Host (IP or hostname)", text: $manualHost)
                        .textContentType(.URL)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    TextField("Port", text: $manualPort)
                        .keyboardType(.numberPad)
                    Button("Connect") {
                        let port = Int(manualPort) ?? 1704
                        connectTo(host: manualHost, port: port)
                    }
                    .disabled(manualHost.isEmpty)
                }

                // Info
                Section("About") {
                    LabeledContent("Core Version", value: engine.coreVersion)
                    LabeledContent("Protocol Version", value: "\(engine.protocolVersion)")
                    LabeledContent("State", value: engine.state.displayName)
                }
            }
            .navigationTitle("Servers")
            .onAppear {
                discovery.startBrowsing()
            }
        }
    }

    private func connectTo(host: String, port: Int) {
        engine.start(host: host, port: port)
        // Also connect the RPC client for control
        rpcClient.connect(host: host, port: 1780)
    }
}
