import SwiftUI

/// View for managing server connections.
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
                        Task {
                            let result = await engine.testTCP(host: host, port: port)
                            #if DEBUG
                            print("TCP test result: \(result)")
                            #endif
                        }
                    }
                    .disabled(manualHost.isEmpty && discovery.servers.isEmpty)

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
        }
    }

    private func connectTo(host: String, port: Int) {
        engine.start(host: host, port: port)
        // RPC control port is audio port + 76 (standard: 1704 -> 1780)
        rpcClient.connect(host: host, port: port + 76)
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
