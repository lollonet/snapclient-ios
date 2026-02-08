import SwiftUI
import UIKit
import AVFoundation

@main
struct SnapClientApp: App {
    @StateObject private var engine = SnapClientEngine()
    @StateObject private var discovery = ServerDiscovery()
    @StateObject private var rpcClient = SnapcastRPCClient()
    @StateObject private var nowPlaying = NowPlayingManager()
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
        switch phase {
        case .active:
            // App became active - ensure audio session is active
            print("[App] Scene became active")
            do {
                try AVAudioSession.sharedInstance().setActive(true)
            } catch {
                print("[App] Failed to activate audio session: \(error)")
            }

        case .inactive:
            // App becoming inactive (e.g., incoming call overlay)
            print("[App] Scene became inactive")

        case .background:
            // App went to background - audio should continue
            // Ensure audio session stays active for background playback
            print("[App] Scene went to background")
            if engine.state.isActive {
                do {
                    try AVAudioSession.sharedInstance().setActive(true)
                    print("[App] Audio session kept active for background playback")
                } catch {
                    print("[App] Failed to keep audio session active: \(error)")
                }
            }

        @unknown default:
            break
        }
    }
}
