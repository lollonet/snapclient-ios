import SwiftUI

@main
struct SnapClientApp: App {
    @StateObject private var engine = SnapClientEngine()
    @StateObject private var discovery = ServerDiscovery()
    @StateObject private var rpcClient = SnapcastRPCClient()
    @StateObject private var nowPlaying = NowPlayingManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(engine)
                .environmentObject(discovery)
                .environmentObject(rpcClient)
                .task {
                    // Configure now playing integration
                    nowPlaying.configure(engine: engine, rpcClient: rpcClient)

                    // Auto-connect to last server on launch
                    if let server = engine.lastServer {
                        engine.start(host: server.host, port: server.port)
                        rpcClient.connect(host: server.host, port: server.port + 76)
                    }
                }
        }
    }
}
