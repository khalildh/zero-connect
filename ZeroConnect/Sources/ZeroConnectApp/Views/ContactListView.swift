import SwiftUI
import ZeroConnectCore

struct ContactListView: View {
    @EnvironmentObject var appState: AppState
    @State private var showScanner = false

    var body: some View {
        NavigationStack {
            Group {
                if appState.contacts.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "person.2.slash")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                        Text("No contacts yet")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                        Text("Scan someone's QR code to add them")
                            .font(.body)
                            .foregroundStyle(.tertiary)
                        Button("Scan QR Code") {
                            showScanner = true
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else {
                    List(appState.contacts) { contact in
                        NavigationLink(destination: ConversationView(contact: contact)) {
                            ContactRow(
                                contact: contact,
                                lastMessage: appState.conversations[contact.id]?.last
                            )
                        }
                    }
                }
            }
            .navigationTitle("Messages")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showScanner = true
                    } label: {
                        Image(systemName: "qrcode.viewfinder")
                    }
                }
            }
            .sheet(isPresented: $showScanner) {
                ScannerView()
            }
        }
    }
}

struct ContactRow: View {
    let contact: Contact
    let lastMessage: StoredMessage?

    var body: some View {
        HStack {
            Circle()
                .fill(.blue.opacity(0.2))
                .frame(width: 44, height: 44)
                .overlay {
                    Text(String(contact.displayName.prefix(1)).uppercased())
                        .font(.headline)
                        .foregroundStyle(.blue)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(contact.displayName)
                    .font(.body)
                    .fontWeight(.medium)

                if let last = lastMessage {
                    HStack(spacing: 4) {
                        if last.direction == .sent {
                            deliveryIcon(last.deliveryState)
                        }
                        Text(last.decryptedText ?? "Encrypted message")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            if let last = lastMessage {
                Text(last.message.timestamp, style: .time)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func deliveryIcon(_ state: DeliveryState) -> some View {
        switch state {
        case .queued:
            Image(systemName: "clock")
                .font(.caption2)
                .foregroundStyle(.secondary)
        case .carried:
            Image(systemName: "arrow.right.circle")
                .font(.caption2)
                .foregroundStyle(.orange)
        case .delivered:
            Image(systemName: "checkmark")
                .font(.caption2)
                .foregroundStyle(.green)
        case .read:
            Image(systemName: "checkmark.circle.fill")
                .font(.caption2)
                .foregroundStyle(.blue)
        }
    }
}
