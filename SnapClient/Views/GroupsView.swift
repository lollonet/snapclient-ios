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
    @State private var showMasterVolume = false

    /// Average volume of all connected clients in the group
    private var averageVolume: Int {
        let connectedClients = group.clients.filter(\.connected)
        guard !connectedClients.isEmpty else { return 100 }
        let total = connectedClients.reduce(0) { $0 + $1.config.volume.percent }
        return total / connectedClients.count
    }

    /// Clients sorted: connected first, then alphabetically by name
    private var sortedClients: [SnapcastClient] {
        group.clients.sorted { a, b in
            if a.connected != b.connected {
                return a.connected  // Connected clients first
            }
            let nameA = a.config.name.isEmpty ? (a.host?.name ?? a.id) : a.config.name
            let nameB = b.config.name.isEmpty ? (b.host?.name ?? b.id) : b.config.name
            return nameA.localizedCaseInsensitiveCompare(nameB) == .orderedAscending
        }
    }

    var body: some View {
        Section {
            // Master volume (only when expanded)
            if showMasterVolume {
                HStack(spacing: 10) {
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
                }
                .opacity(group.muted ? 0.4 : 1.0)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // Client rows (sorted)
            ForEach(sortedClients) { client in
                ClientRow(client: client, groupId: group.id, editItem: $editItem)
            }
        } header: {
            HStack(spacing: 12) {
                // Group name (tappable for edit)
                Button {
                    editItem = .group(group)
                } label: {
                    HStack(spacing: 4) {
                        Text(group.name.isEmpty ? "Group" : group.name)
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .foregroundStyle(.primary)

                Spacer()

                // Master volume toggle
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showMasterVolume.toggle()
                    }
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .foregroundStyle(showMasterVolume ? Color.accentColor : .secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(showMasterVolume ? "Hide master volume" : "Show master volume")

                // Group mute
                Button {
                    Task {
                        do {
                            try await rpcClient.setGroupMute(groupId: group.id, muted: !group.muted)
                            await rpcClient.refreshStatus()
                        } catch {
                            rpcClient.handleError(error)
                        }
                    }
                } label: {
                    Image(systemName: group.muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .foregroundStyle(group.muted ? .red : .secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(group.muted ? "Unmute group" : "Mute group")
            }
        }
        .onAppear {
            groupVolume = Double(averageVolume)
        }
        .onChange(of: averageVolume) { _, newValue in
            if !isEditingVolume {
                groupVolume = Double(newValue)
            }
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
                rpcClient.lastError = errors.joined(separator: "\n")
                rpcClient.showError = true
            }
        }
    }
}

/// Compact row showing a single client with full-width volume slider.
struct ClientRow: View {
    let client: SnapcastClient
    let groupId: String
    @Binding var editItem: GroupsEditItem?
    @EnvironmentObject var rpcClient: SnapcastRPCClient

    private var isMuted: Bool {
        client.config.volume.muted
    }

    private var displayName: String {
        client.config.name.isEmpty ? (client.host?.name ?? client.id) : client.config.name
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Top row: Status indicator + Name + Mute button
            HStack(spacing: 8) {
                // Status + Name (tappable for edit)
                Button {
                    editItem = .client(client, groupId: groupId)
                } label: {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(client.connected ? .green : .red)
                            .frame(width: 8, height: 8)
                        Text(displayName)
                            .font(.subheadline)
                            .lineLimit(1)
                    }
                }
                .foregroundStyle(.primary)

                Spacer()

                // Mute button
                Button {
                    toggleMute()
                } label: {
                    Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .foregroundStyle(isMuted ? .red : .secondary)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isMuted ? "Unmute \(displayName)" : "Mute \(displayName)")
            }

            // Bottom row: Full-width volume slider
            SnapVolumeSlider(
                serverValue: client.config.volume.percent,
                isMuted: isMuted,
                onCommit: { newPercent in
                    try await rpcClient.setClientVolume(
                        clientId: client.id,
                        volume: ClientVolume(percent: newPercent, muted: isMuted)
                    )
                    await rpcClient.refreshStatus()
                },
                onError: { error in
                    rpcClient.handleError(error)
                }
            )
        }
        .padding(.vertical, 4)
        .opacity(isMuted ? 0.5 : 1.0)
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
                rpcClient.handleError(error)
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
