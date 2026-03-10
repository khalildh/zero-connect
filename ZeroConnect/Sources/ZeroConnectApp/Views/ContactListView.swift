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
                    List {
                        ForEach(appState.contacts) { contact in
                            NavigationLink(destination: ConversationView(contact: contact)
                                .onAppear { appState.markRead(contactId: contact.id) }
                            ) {
                                ContactRow(
                                    contact: contact,
                                    lastMessage: appState.conversations[contact.id]?.last,
                                    unreadCount: appState.unreadCounts[contact.id] ?? 0
                                )
                            }
                        }
                        .onDelete { indices in
                            let contactsToDelete = indices.map { appState.contacts[$0] }
                            for contact in contactsToDelete {
                                appState.deleteContact(contact)
                            }
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
    var unreadCount: Int = 0

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
                    .fontWeight(unreadCount > 0 ? .bold : .medium)

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

            VStack(alignment: .trailing, spacing: 4) {
                if let last = lastMessage {
                    Text(last.message.timestamp, style: .time)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                if unreadCount > 0 {
                    Text("\(unreadCount)")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue)
                        .clipShape(Capsule())
                }
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
