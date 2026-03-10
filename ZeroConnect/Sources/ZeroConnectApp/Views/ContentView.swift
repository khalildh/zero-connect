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
                .badge(appState.totalUnreadCount)

            NearbyPeersView()
                .tabItem {
                    Label("Nearby", systemImage: "antenna.radiowaves.left.and.right")
                }

            MyIdentityView()
                .tabItem {
                    Label("Me", systemImage: "person.crop.circle")
                }

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
        }
        .task {
            await appState.startDiscovery()
        }
    }
}
