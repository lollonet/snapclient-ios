import SwiftUI
import UIKit
import AVFoundation

@main
struct SnapClientApp: App {
    @StateObject private var engine = SnapClientEngine()
    @StateObject private var discovery = ServerDiscovery()
    @StateObject private var rpcClient = SnapcastRPCClient()
    @StateObject private var nowPlaying = NowPlayingManager()
    @StateObject private var savedServers = SavedServersStore()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Start receiving remote control events early in app lifecycle
        // This is required for lock screen and Control Center controls
        UIApplication.shared.beginReceivingRemoteControlEvents()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(engine)
                .environmentObject(discovery)
                .environmentObject(rpcClient)
                .environmentObject(savedServers)
                .task {
                    // Configure now playing integration
                    nowPlaying.configure(engine: engine, rpcClient: rpcClient)

                    // Auto-connect to last server on launch
                    if let server = engine.lastServer {
                        engine.start(host: server.host, port: server.port)
                        rpcClient.connect(host: server.host, port: server.port + 76)
                    }
                }
                .onChange(of: scenePhase) { _, newPhase in
                    handleScenePhaseChange(newPhase)
                }
        }
    }

    private func handleScenePhaseChange(_ phase: ScenePhase) {
        // Just log phase changes - don't manipulate audio session here
        // The audio session is managed by SnapClientEngine
        #if DEBUG
        switch phase {
        case .active:
            print("[App] Scene became active")
        case .inactive:
            print("[App] Scene became inactive")
        case .background:
            print("[App] Scene went to background")
        @unknown default:
            break
        }
        #endif
    }
}
