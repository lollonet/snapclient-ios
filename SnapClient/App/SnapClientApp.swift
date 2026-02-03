import SwiftUI

@main
struct SnapClientApp: App {
    @StateObject private var engine = SnapClientEngine()
    @StateObject private var discovery = ServerDiscovery()
    @StateObject private var rpcClient = SnapcastRPCClient()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(engine)
                .environmentObject(discovery)
                .environmentObject(rpcClient)
        }
    }
}
