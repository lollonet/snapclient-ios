import SwiftUI

/// Root content view containing the main tab navigation.
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
        .alert("Error", isPresented: $rpcClient.showError) {
            Button("OK") { }
        } message: {
            Text(rpcClient.lastError ?? "Unknown error")
        }
    }
}
