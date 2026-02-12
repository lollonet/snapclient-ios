import SwiftUI

/// View for managing server connections.
struct ServersView: View {
    @EnvironmentObject var engine: SnapClientEngine
    @EnvironmentObject var discovery: ServerDiscovery
    @EnvironmentObject var rpcClient: SnapcastRPCClient
    @EnvironmentObject var savedServers: SavedServersStore

    @State private var showAddSheet = false
    @State private var editingServer: SavedServer?
    @State private var isTestingConnection = false
    @State private var connectionTestResult: Bool?
    @State private var clearResultTask: Task<Void, Never>?

    /// Discovered servers sorted: connected first, then alphabetically
    private var sortedDiscoveredServers: [DiscoveredServer] {
        discovery.servers.sorted { a, b in
            let aConnected = engine.connectedHost == a.host
            let bConnected = engine.connectedHost == b.host
            if aConnected != bConnected {
                return aConnected  // Connected server first
            }
            return a.displayName.localizedCaseInsensitiveCompare(b.displayName) == .orderedAscending
        }
    }

    /// Saved servers sorted: connected first, then alphabetically
    private var sortedSavedServers: [SavedServer] {
        savedServers.servers.sorted { a, b in
            let aConnected = engine.connectedHost == a.host
            let bConnected = engine.connectedHost == b.host
            if aConnected != bConnected {
                return aConnected  // Connected server first
            }
            return a.displayName.localizedCaseInsensitiveCompare(b.displayName) == .orderedAscending
        }
    }

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
                        ForEach(sortedDiscoveredServers) { server in
                            Button {
                                connectTo(host: server.host, port: server.port)
                            } label: {
                                ServerRow(
                                    name: server.displayName,
                                    host: server.host,
                                    port: server.port,
                                    hostname: server.hostname,
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
                        ForEach(sortedSavedServers) { server in
                            Button {
                                connectTo(host: server.host, port: server.port)
                            } label: {
                                ServerRow(
                                    name: server.displayName,
                                    host: server.host,
                                    port: server.port,
                                    hostname: nil,
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

                // Diagnostics
                Section("Diagnostics") {
                    // Discovery status
                    HStack {
                        Label("Network Discovery", systemImage: "antenna.radiowaves.left.and.right")
                        Spacer()
                        if discovery.isSearching {
                            Text("Active")
                                .foregroundStyle(.green)
                        } else {
                            Text("Idle")
                                .foregroundStyle(.secondary)
                        }
                    }

                    LabeledContent("Servers Found", value: "\(discovery.servers.count)")

                    // Connection test (only when connected)
                    if let host = engine.connectedHost, let port = engine.connectedPort {
                        Button {
                            testConnection(host: host, port: port)
                        } label: {
                            HStack {
                                Label("Test Connection", systemImage: "network")
                                Spacer()
                                if isTestingConnection {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                } else if let result = connectionTestResult {
                                    Image(systemName: result ? "checkmark.circle.fill" : "xmark.circle.fill")
                                        .foregroundStyle(result ? .green : .red)
                                }
                            }
                        }
                        .disabled(isTestingConnection)
                    }

                    // Bridge logs
                    if !engine.bridgeLogs.isEmpty {
                        NavigationLink {
                            BridgeLogsView(logs: engine.bridgeLogs)
                        } label: {
                            HStack {
                                Label("Bridge Logs", systemImage: "doc.text")
                                Spacer()
                                Text("\(engine.bridgeLogs.count)")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                // Version info
                Section("Version") {
                    LabeledContent("Core", value: engine.coreVersion)
                    LabeledContent("Protocol", value: "\(engine.protocolVersion)")
                }
            }
            .navigationTitle("Servers")
            .onAppear {
                discovery.startBrowsing()
            }
            .onDisappear {
                clearResultTask?.cancel()
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

    private func testConnection(host: String, port: Int) {
        isTestingConnection = true
        connectionTestResult = nil
        clearResultTask?.cancel()

        Task {
            let result = await engine.testTCP(host: host, port: port)
            isTestingConnection = false
            connectionTestResult = (result == 0)

            // Clear result after 3 seconds (cancellable)
            clearResultTask = Task {
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { return }
                connectionTestResult = nil
            }
        }
    }
}

/// Reusable row for displaying a server.
private struct ServerRow: View {
    let name: String
    let host: String
    let port: Int
    let hostname: String?  // Resolved hostname (from reverse DNS)
    let isConnected: Bool

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(name)
                        .font(.body)
                    if isConnected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                    }
                }
                // Show hostname if we have it and it's different from display name
                if let hostname, !hostname.isEmpty, hostname != name, hostname != host {
                    Text(hostname)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text("\(host):\(String(port))")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
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
