import SwiftUI
import ZeroConnectCore

struct ContentView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        TabView {
            ContactListView()
                .tabItem {
                    Label("Messages", systemImage: "message.fill")
                }

            NearbyPeersView()
                .tabItem {
                    Label("Nearby", systemImage: "antenna.radiowaves.left.and.right")
                }

            MyIdentityView()
                .tabItem {
                    Label("Me", systemImage: "person.crop.circle")
                }
        }
        .task {
            await appState.startDiscovery()
        }
    }
}
