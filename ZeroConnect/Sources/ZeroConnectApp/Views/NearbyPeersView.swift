import SwiftUI
import ZeroConnectCore

struct NearbyPeersView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        NavigationStack {
            Group {
                if appState.nearbyPeers.isEmpty {
                    VStack(spacing: 16) {
                        if appState.isDiscovering {
                            ProgressView()
                                .scaleEffect(1.5)
                            Text("Looking for nearby devices...")
                                .font(.body)
                                .foregroundStyle(.secondary)
                        } else {
                            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                                .font(.system(size: 48))
                                .foregroundStyle(.secondary)
                            Text("No nearby devices found")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    List(appState.nearbyPeers) { peer in
                        PeerRow(peer: peer)
                    }
                }
            }
            .navigationTitle("Nearby")
        }
    }
}

struct PeerRow: View {
    let peer: TransportPeer

    var body: some View {
        HStack {
            transportIcon(peer.transport)
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(peer.displayName)
                    .font(.body)
                Text(peer.transport.rawValue.capitalized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let rssi = peer.rssi {
                signalBars(rssi: rssi)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func transportIcon(_ kind: TransportKind) -> some View {
        switch kind {
        case .loom:
            Image(systemName: "wifi")
                .foregroundStyle(.blue)
        case .meshtastic:
            Image(systemName: "wave.3.right")
                .foregroundStyle(.green)
        case .server:
            Image(systemName: "cloud")
                .foregroundStyle(.purple)
        }
    }

    @ViewBuilder
    private func signalBars(rssi: Int) -> some View {
        let bars = switch rssi {
        case -50...0: 4
        case -65...(-51): 3
        case -80...(-66): 2
        default: 1
        }

        HStack(spacing: 1) {
            ForEach(1...4, id: \.self) { bar in
                RoundedRectangle(cornerRadius: 1)
                    .fill(bar <= bars ? Color.green : Color.gray.opacity(0.3))
                    .frame(width: 4, height: CGFloat(bar) * 4 + 4)
            }
        }
    }
}
