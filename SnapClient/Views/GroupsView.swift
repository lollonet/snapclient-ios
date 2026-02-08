import SwiftUI

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

/// View for managing groups and clients.
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

/// Section showing a group with its clients.
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
            // Only refresh if at least one volume change succeeded
            if errors.count < group.clients.filter(\.connected).count {
                await rpcClient.refreshStatus()
            }
            if !errors.isEmpty {
                rpcError = errors.joined(separator: "\n")
                showRPCError = true
            }
        }
    }
}

/// Row showing a single client with volume slider.
struct ClientRow: View {
    let client: SnapcastClient
    let groupId: String
    @Binding var editItem: GroupsEditItem?
    @EnvironmentObject var rpcClient: SnapcastRPCClient
    @State private var sliderValue: Double = 0
    @State private var isEditing = false
    @State private var rpcError: String?
    @State private var showRPCError = false

    private var isMuted: Bool {
        client.config.volume.muted
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
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
                    }
                }
                .foregroundStyle(.primary)

                Text("\(Int(isEditing ? sliderValue : Double(client.config.volume.percent)))%")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)

                Button {
                    toggleMute()
                } label: {
                    Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .foregroundStyle(isMuted ? .red : .secondary)
                        .frame(width: 24)
                }
                .buttonStyle(.plain)

                Button {
                    editItem = .client(client, groupId: groupId)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
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
                        do {
                            try await rpcClient.setClientVolume(
                                clientId: client.id,
                                volume: ClientVolume(percent: Int(sliderValue), muted: isMuted)
                            )
                            await rpcClient.refreshStatus()
                        } catch {
                            rpcError = error.localizedDescription
                            showRPCError = true
                        }
                    }
                }
            }
            .tint(isMuted ? .secondary : .accentColor)
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
        .opacity(isMuted ? 0.5 : 1.0)
        .alert("Error", isPresented: $showRPCError) {
            Button("OK") { }
        } message: {
            Text(rpcError ?? "Unknown error")
        }
    }

    private func toggleMute() {
        Task {
            do {
                try await rpcClient.setClientVolume(
                    clientId: client.id,
                    volume: ClientVolume(percent: client.config.volume.percent, muted: !isMuted)
                )
                await rpcClient.refreshStatus()
            } catch {
                rpcError = error.localizedDescription
                showRPCError = true
            }
        }
    }
}

/// Row showing stream status.
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
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(stream.status)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
