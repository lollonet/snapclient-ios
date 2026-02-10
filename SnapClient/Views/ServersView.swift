import SwiftUI

/// View for managing server connections.
struct ServersView: View {
    @EnvironmentObject var engine: SnapClientEngine
    @EnvironmentObject var discovery: ServerDiscovery
    @EnvironmentObject var rpcClient: SnapcastRPCClient
    @EnvironmentObject var savedServers: SavedServersStore

    @State private var showAddSheet = false
    @State private var editingServer: SavedServer?

    var body: some View {
        NavigationStack {
            List {
                // Discovered servers (auto-discovery via Bonjour)
                Section {
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
                                ServerRow(
                                    name: server.displayName,
                                    host: server.host,
                                    port: server.port,
                                    isConnected: engine.connectedHost == server.host
                                )
                            }
                        }
                    }
                } header: {
                    Label("Discovered", systemImage: "antenna.radiowaves.left.and.right")
                }

                // Saved servers (manually added)
                if !savedServers.servers.isEmpty {
                    Section {
                        ForEach(savedServers.servers) { server in
                            Button {
                                connectTo(host: server.host, port: server.port)
                            } label: {
                                ServerRow(
                                    name: server.displayName,
                                    host: server.host,
                                    port: server.port,
                                    isConnected: engine.connectedHost == server.host
                                )
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    savedServers.remove(server)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            .swipeActions(edge: .leading) {
                                Button {
                                    editingServer = server
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                .tint(.orange)
                            }
                        }
                    } header: {
                        Label("Saved", systemImage: "pin.fill")
                    }
                }

                // Add server button
                Section {
                    Button {
                        showAddSheet = true
                    } label: {
                        Label("Add Server Manually...", systemImage: "plus")
                    }
                }

                // Info
                Section("About") {
                    LabeledContent("Core Version", value: engine.coreVersion)
                    LabeledContent("Protocol Version", value: "\(engine.protocolVersion)")
                    LabeledContent("State", value: engine.state.displayName)
                }

                // Debug
                Section("Debug") {
                    Button("Clear Last Server") {
                        engine.lastServer = nil
                        #if DEBUG
                        print("Cleared lastServer")
                        #endif
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
            .sheet(isPresented: $showAddSheet) {
                AddServerSheet()
            }
            .sheet(item: $editingServer) { server in
                AddServerSheet(editingServer: server)
            }
        }
    }

    private func connectTo(host: String, port: Int) {
        // Disconnect old RPC connection first to avoid stale state
        rpcClient.disconnect()

        engine.start(host: host, port: port)
        // RPC control port is audio port + 76 (standard: 1704 -> 1780)
        rpcClient.connect(host: host, port: port + 76)
    }
}

/// Reusable row for displaying a server.
private struct ServerRow: View {
    let name: String
    let host: String
    let port: Int
    let isConnected: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(name)
                    .font(.body)
                Text("\(host):\(port)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isConnected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
        .contentShape(Rectangle())
    }
}

/// Debug view for bridge logs.
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
