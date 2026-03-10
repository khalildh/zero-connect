import SwiftUI
import ZeroConnectCore

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var showResetAlert = false
    @State private var displayName = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Device") {
                    HStack {
                        Text("Display Name")
                        Spacer()
                        Text(appState.displayName)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Queue") {
                    HStack {
                        Text("Pending Messages")
                        Spacer()
                        Text("\(appState.pendingQueueCount)")
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("Contacts")
                        Spacer()
                        Text("\(appState.contacts.count)")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Transports") {
                    HStack {
                        Image(systemName: "wifi")
                            .foregroundStyle(.blue)
                        Text("Loom (Wi-Fi / AWDL)")
                        Spacer()
                        Text("Active")
                            .foregroundStyle(.green)
                            .font(.caption)
                    }

                    HStack {
                        Image(systemName: "wave.3.right")
                            .foregroundStyle(.green)
                        Text("Meshtastic (LoRa)")
                        Spacer()
                        Text(appState.nearbyPeers.contains(where: { $0.transport == .meshtastic })
                            ? "Connected" : "Scanning")
                            .foregroundStyle(appState.nearbyPeers.contains(where: { $0.transport == .meshtastic })
                                ? .green : .orange)
                            .font(.caption)
                    }

                    HStack {
                        Image(systemName: "cloud")
                            .foregroundStyle(.purple)
                        Text("Server")
                        Spacer()
                        Text("Not configured")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                }

                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("0.1.0")
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("Encryption")
                        Spacer()
                        Text("ECDH + ChaChaPoly")
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Button("Reset Identity", role: .destructive) {
                        showResetAlert = true
                    }
                }
            }
            .navigationTitle("Settings")
            .alert("Reset Identity?", isPresented: $showResetAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Reset", role: .destructive) {
                    Task {
                        try? await appState.identity.deleteIdentity()
                    }
                }
            } message: {
                Text("This will generate a new identity key. Existing contacts won't be able to reach you.")
            }
        }
    }
}
