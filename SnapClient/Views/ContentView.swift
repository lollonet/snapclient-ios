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
    @State private var rpcError: String?
    @State private var showRPCError = false

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
            .alert("Error", isPresented: $showRPCError) {
                Button("OK") { }
            } message: {
                Text(rpcError ?? "Unknown error")
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
        VStack(spacing: 8) {
            HStack {
                Slider(
                    value: $volumeSlider,
                    in: 0...100,
                    step: 1
                ) { editing in
                    isEditingVolume = editing
                    if !editing, let client = currentClient {
                        Task {
                            do {
                                try await rpcClient.setClientVolume(
                                    clientId: client.id,
                                    volume: ClientVolume(percent: Int(volumeSlider), muted: serverMuted)
                                )
                                await rpcClient.refreshStatus()
                            } catch {
                                rpcError = error.localizedDescription
                                showRPCError = true
                            }
                        }
                    }
                }
                .tint(serverMuted ? .secondary : .accentColor)
                .accessibilityLabel("Volume")
                .accessibilityValue("\(Int(volumeSlider)) percent")
            }
            .opacity(serverMuted ? 0.4 : 1.0)
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
                        do {
                            try await rpcClient.setClientVolume(
                                clientId: client.id,
                                volume: ClientVolume(percent: serverVolume, muted: !serverMuted)
                            )
                            await rpcClient.refreshStatus()
                        } catch {
                            rpcError = error.localizedDescription
                            showRPCError = true
                        }
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

/// What to show in the edit sheet
enum GroupsEditItem: Identifiable {
    case group(SnapcastGroup)
    case client(SnapcastClient, groupId: String)

    var id: String {
        switch self {
        case .group(let g): return "group-\(g.id)"
        case .client(let c, _): return "client-\(c.id)"
        }
    }
}

struct GroupsView: View {
    @EnvironmentObject var rpcClient: SnapcastRPCClient
    @State private var editItem: GroupsEditItem?

    var body: some View {
        NavigationStack {
            Group {
                if let status = rpcClient.serverStatus {
                    List {
                        ForEach(status.groups) { group in
                            GroupSection(group: group, editItem: $editItem)
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
            .sheet(item: $editItem) { item in
                switch item {
                case .group(let group):
                    GroupEditSheet(group: group)
                case .client(let client, let groupId):
                    ClientEditSheet(client: client, currentGroupId: groupId)
                }
            }
            .refreshable {
                await rpcClient.refreshStatus()
            }
        }
    }
}

struct GroupSection: View {
    let group: SnapcastGroup
    @Binding var editItem: GroupsEditItem?
    @EnvironmentObject var rpcClient: SnapcastRPCClient
    @State private var groupVolume: Double = 100
    @State private var isEditingVolume = false
    @State private var rpcError: String?
    @State private var showRPCError = false

    /// Average volume of all connected clients in the group
    private var averageVolume: Int {
        let connectedClients = group.clients.filter(\.connected)
        guard !connectedClients.isEmpty else { return 100 }
        let total = connectedClients.reduce(0) { $0 + $1.config.volume.percent }
        return total / connectedClients.count
    }

    var body: some View {
        Section {
            // Group volume slider
            HStack(spacing: 12) {
                Image(systemName: "speaker.wave.2")
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                Slider(
                    value: $groupVolume,
                    in: 0...100,
                    step: 1
                ) { editing in
                    isEditingVolume = editing
                    if !editing {
                        setAllClientsVolume(Int(groupVolume))
                    }
                }
                .tint(group.muted ? .secondary : .accentColor)
                Text("\(Int(groupVolume))%")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 40)
            }
            .opacity(group.muted ? 0.4 : 1.0)
            .onAppear {
                groupVolume = Double(averageVolume)
            }
            .onChange(of: averageVolume) { _, newValue in
                if !isEditingVolume {
                    groupVolume = Double(newValue)
                }
            }

            ForEach(group.clients) { client in
                ClientRow(client: client, groupId: group.id, editItem: $editItem)
            }
        } header: {
            HStack {
                Button {
                    editItem = .group(group)
                } label: {
                    HStack {
                        Text(group.name.isEmpty ? "Group" : group.name)
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .foregroundStyle(.primary)

                Spacer()

                Button {
                    Task {
                        do {
                            try await rpcClient.setGroupMute(groupId: group.id, muted: !group.muted)
                            await rpcClient.refreshStatus()
                        } catch {
                            rpcError = error.localizedDescription
                            showRPCError = true
                        }
                    }
                } label: {
                    Image(systemName: group.muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .foregroundStyle(group.muted ? .red : .secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .alert("Error", isPresented: $showRPCError) {
            Button("OK") { }
        } message: {
            Text(rpcError ?? "Unknown error")
        }
    }

    private func setAllClientsVolume(_ volume: Int) {
        Task {
            var errors: [String] = []
            for client in group.clients where client.connected {
                do {
                    try await rpcClient.setClientVolume(
                        clientId: client.id,
                        volume: ClientVolume(percent: volume, muted: client.config.volume.muted)
                    )
                } catch {
                    errors.append("\(client.config.name.isEmpty ? client.id : client.config.name): \(error.localizedDescription)")
                }
            }
            await rpcClient.refreshStatus()
            if !errors.isEmpty {
                rpcError = errors.joined(separator: "\n")
                showRPCError = true
            }
        }
    }
}

struct ClientRow: View {
    let client: SnapcastClient
    let groupId: String
    @Binding var editItem: GroupsEditItem?
    @EnvironmentObject var rpcClient: SnapcastRPCClient
    @State private var sliderValue: Double = 0
    @State private var isEditing = false
    @State private var rpcError: String?
    @State private var showRPCError = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                editItem = .client(client, groupId: groupId)
            } label: {
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
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .foregroundStyle(.primary)

            Slider(
                value: $sliderValue,
                in: 0...100,
                step: 1
            ) { editing in
                isEditing = editing
                if !editing {
                    // Only send when user finishes dragging
                    Task {
                        do {
                            try await rpcClient.setClientVolume(
                                clientId: client.id,
                                volume: ClientVolume(percent: Int(sliderValue), muted: client.config.volume.muted)
                            )
                            await rpcClient.refreshStatus()
                        } catch {
                            rpcError = error.localizedDescription
                            showRPCError = true
                        }
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
        .alert("Error", isPresented: $showRPCError) {
            Button("OK") { }
        } message: {
            Text(rpcError ?? "Unknown error")
        }
    }
}

// MARK: - Edit Sheets

struct ClientEditSheet: View {
    let client: SnapcastClient
    let currentGroupId: String
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var rpcClient: SnapcastRPCClient
    @State private var name: String = ""
    @State private var latency: String = ""
    @State private var selectedGroupId: String = ""
    @State private var errorMessage: String?
    @State private var showError = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Client Info") {
                    LabeledContent("ID", value: client.id)
                    if let host = client.host {
                        if let hostName = host.name {
                            LabeledContent("Host", value: hostName)
                        }
                        if let ip = host.ip {
                            LabeledContent("IP", value: ip)
                        }
                        if let os = host.os {
                            LabeledContent("OS", value: os)
                        }
                    }
                    HStack {
                        Circle()
                            .fill(client.connected ? .green : .red)
                            .frame(width: 10, height: 10)
                        Text(client.connected ? "Connected" : "Disconnected")
                    }
                }

                Section("Settings") {
                    TextField("Display Name", text: $name)
                    TextField("Latency (ms)", text: $latency)
                        .keyboardType(.numberPad)
                }

                if let groups = rpcClient.serverStatus?.groups, groups.count > 1 {
                    Section("Group") {
                        Picker("Move to Group", selection: $selectedGroupId) {
                            ForEach(groups) { group in
                                Text(group.name.isEmpty ? "Group \(group.id.prefix(8))" : group.name)
                                    .tag(group.id)
                            }
                        }
                    }
                }

                Section {
                    Button("Delete Client", role: .destructive) {
                        Task {
                            do {
                                try await rpcClient.deleteClient(clientId: client.id)
                                await rpcClient.refreshStatus()
                                dismiss()
                            } catch {
                                errorMessage = error.localizedDescription
                                showError = true
                            }
                        }
                    }
                    .disabled(client.connected)
                }
            }
            .navigationTitle("Edit Client")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveChanges() }
                }
            }
            .onAppear {
                name = client.config.name
                latency = String(client.config.latency)
                selectedGroupId = currentGroupId
            }
            .alert("Error", isPresented: $showError) {
                Button("OK") { showError = false }
            } message: {
                Text(errorMessage ?? "Unknown error")
            }
        }
    }

    private func saveChanges() {
        Task {
            do {
                // Save name if changed
                if name != client.config.name {
                    print("[ClientEdit] setClientName: clientId=\(client.id), name=\(name)")
                    try await rpcClient.setClientName(clientId: client.id, name: name)
                }
                // Save latency if changed
                if let newLatency = Int(latency), newLatency != client.config.latency {
                    print("[ClientEdit] setClientLatency: clientId=\(client.id), latency=\(newLatency)")
                    try await rpcClient.setClientLatency(clientId: client.id, latency: newLatency)
                }
                // Move to different group if changed
                if selectedGroupId != currentGroupId {
                    // Get current clients in target group and add this one
                    if let targetGroup = rpcClient.serverStatus?.groups.first(where: { $0.id == selectedGroupId }) {
                        var clientIds = targetGroup.clients.map(\.id)
                        clientIds.append(client.id)
                        print("[ClientEdit] setGroupClients: groupId=\(selectedGroupId), clientIds=\(clientIds)")
                        try await rpcClient.setGroupClients(groupId: selectedGroupId, clientIds: clientIds)
                    }
                }
                await rpcClient.refreshStatus()
                dismiss()
            } catch {
                print("[ClientEdit] error: \(error.localizedDescription)")
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }
}

struct GroupEditSheet: View {
    let group: SnapcastGroup
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var rpcClient: SnapcastRPCClient
    @State private var name: String = ""
    @State private var selectedStreamId: String = ""
    @State private var errorMessage: String?
    @State private var showError = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Group Info") {
                    LabeledContent("ID", value: String(group.id.prefix(8)))
                    LabeledContent("Clients", value: "\(group.clients.count)")
                }

                Section("Settings") {
                    TextField("Group Name", text: $name)
                }

                if let streams = rpcClient.serverStatus?.streams, !streams.isEmpty {
                    Section("Stream") {
                        Picker("Audio Stream", selection: $selectedStreamId) {
                            ForEach(streams) { stream in
                                HStack {
                                    Text(stream.id)
                                    if stream.status == "playing" {
                                        Image(systemName: "music.note")
                                    }
                                }
                                .tag(stream.id)
                            }
                        }
                    }
                }

                Section("Clients") {
                    ForEach(group.clients) { client in
                        HStack {
                            Circle()
                                .fill(client.connected ? .green : .red)
                                .frame(width: 8, height: 8)
                            Text(client.config.name.isEmpty ? (client.host?.name ?? client.id) : client.config.name)
                        }
                    }
                }
            }
            .navigationTitle("Edit Group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveChanges() }
                }
            }
            .onAppear {
                name = group.name
                selectedStreamId = group.stream_id
            }
            .alert("Error", isPresented: $showError) {
                Button("OK") { showError = false }
            } message: {
                Text(errorMessage ?? "Unknown error")
            }
        }
    }

    private func saveChanges() {
        Task {
            do {
                // Save name if changed
                if name != group.name {
                    print("[GroupEdit] setGroupName: groupId=\(group.id), name=\(name)")
                    try await rpcClient.setGroupName(groupId: group.id, name: name)
                }
                // Save stream if changed
                if selectedStreamId != group.stream_id {
                    print("[GroupEdit] setGroupStream: groupId=\(group.id), streamId=\(selectedStreamId)")
                    try await rpcClient.setGroupStream(groupId: group.id, streamId: selectedStreamId)
                }
                await rpcClient.refreshStatus()
                dismiss()
            } catch {
                print("[GroupEdit] error: \(error.localizedDescription)")
                errorMessage = error.localizedDescription
                showError = true
            }
        }
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
