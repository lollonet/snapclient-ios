import SwiftUI
import UIKit

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
    @EnvironmentObject var discovery: ServerDiscovery
    @EnvironmentObject var rpcClient: SnapcastRPCClient

    @State private var volumeSlider: Double = 100
    @State private var isEditingVolume = false

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
                .frame(maxWidth: .infinity)
                .padding()
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    /// Server hostname from discovery
    private var serverHostname: String? {
        guard let host = engine.connectedHost else { return nil }
        return discovery.servers.first { $0.host == host }?.displayName
    }

    private var statusView: some View {
        VStack(spacing: 8) {
            Image(systemName: engine.state.isActive ? "speaker.wave.3.fill" : "speaker.slash")
                .font(.system(size: 64))
                .foregroundStyle(engine.state.isActive ? .green : .secondary)
                .symbolEffect(.variableColor, isActive: engine.state == .playing)
                .accessibilityHidden(true)

            Text(engine.state.displayName)
                .font(.headline)
                .foregroundStyle(.secondary)

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
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "speaker.fill")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Slider(
                    value: $volumeSlider,
                    in: 0...100,
                    step: 1
                ) { editing in
                    isEditingVolume = editing
                    if !editing, let client = currentClient {
                        Task {
                            try? await rpcClient.setClientVolume(
                                clientId: client.id,
                                volume: ClientVolume(percent: Int(volumeSlider), muted: serverMuted)
                            )
                            await rpcClient.refreshStatus()
                        }
                    }
                }
                .accessibilityLabel("Volume")
                .accessibilityValue("\(Int(volumeSlider)) percent")
                Image(systemName: "speaker.wave.3.fill")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .onAppear {
                volumeSlider = Double(serverVolume)
            }
            .onChange(of: serverVolume) { _, newValue in
                if !isEditingVolume {
                    volumeSlider = Double(newValue)
                }
            }

            HStack {
                Text("\(Int(volumeSlider))%")
                    .font(.caption)
                    .monospacedDigit()
                    .accessibilityHidden(true)
                Spacer()
                Button {
                    guard let client = currentClient else { return }
                    Task {
                        try? await rpcClient.setClientVolume(
                            clientId: client.id,
                            volume: ClientVolume(percent: serverVolume, muted: !serverMuted)
                        )
                        await rpcClient.refreshStatus()
                    }
                } label: {
                    Image(systemName: serverMuted ? "speaker.slash.fill" : "speaker.fill")
                }
                .buttonStyle(.bordered)
                .accessibilityLabel(serverMuted ? "Unmute" : "Mute")
                .disabled(currentClient == nil)
            }
        }
        .padding(.horizontal)
        .disabled(currentClient == nil)
    }

    private var controlButtons: some View {
        HStack(spacing: 24) {
            if engine.state.isActive {
                Button(role: .destructive) {
                    engine.stop()
                    rpcClient.disconnect()
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                        .font(.title2)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityHint("Disconnects from the Snapcast server")
            } else {
                // Connect to first discovered server, or prompt to go to Servers tab
                Button {
                    if let server = discovery.servers.first {
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
    @State private var sliderValue: Double = 0
    @State private var isEditing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Circle()
                    .fill(client.connected ? .green : .red)
                    .frame(width: 8, height: 8)
                Text(client.config.name.isEmpty ? (client.host?.name ?? client.id) : client.config.name)
                    .font(.body)
                Spacer()
                Text("\(Int(isEditing ? sliderValue : Double(client.config.volume.percent)))%")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            Slider(
                value: $sliderValue,
                in: 0...100,
                step: 1
            ) { editing in
                isEditing = editing
                if !editing {
                    // Only send when user finishes dragging
                    Task {
                        try? await rpcClient.setClientVolume(
                            clientId: client.id,
                            volume: ClientVolume(percent: Int(sliderValue), muted: client.config.volume.muted)
                        )
                        await rpcClient.refreshStatus()
                    }
                }
            }
            .onAppear {
                sliderValue = Double(client.config.volume.percent)
            }
            .onChange(of: client.config.volume.percent) { _, newValue in
                if !isEditing {
                    sliderValue = Double(newValue)
                }
            }
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

                // Debug
                Section("Debug") {
                    Button("Test Raw TCP") {
                        let host = manualHost.isEmpty ? (discovery.servers.first?.host ?? "") : manualHost
                        guard !host.isEmpty else { return }
                        let port = Int(manualPort) ?? 1704
                        let result = engine.testTCP(host: host, port: port)
                        print("TCP test result: \(result)")
                    }
                    .disabled(manualHost.isEmpty && discovery.servers.isEmpty)

                    Button("Clear Last Server") {
                        engine.lastServer = nil
                        print("Cleared lastServer")
                    }

                    if !engine.bridgeLogs.isEmpty {
                        NavigationLink("View Bridge Logs (\(engine.bridgeLogs.count))") {
                            BridgeLogsView(logs: engine.bridgeLogs)
                        }
                    }
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
        // RPC control port is audio port + 76 (standard: 1704 -> 1780)
        rpcClient.connect(host: host, port: port + 76)
    }
}

// MARK: - Bridge Logs View

struct BridgeLogsView: View {
    let logs: [String]

    var body: some View {
        List {
            ForEach(Array(logs.enumerated()), id: \.offset) { _, log in
                Text(log)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(logColor(for: log))
            }
        }
        .navigationTitle("Bridge Logs")
    }

    private func logColor(for log: String) -> Color {
        if log.hasPrefix("[E]") { return .red }
        if log.hasPrefix("[W]") { return .orange }
        if log.hasPrefix("[D]") { return .secondary }
        return .primary
    }
}
