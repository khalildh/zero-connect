import SwiftUI
import ZeroConnectCore

struct ConversationView: View {
    @EnvironmentObject var appState: AppState
    let contact: Contact
    @State private var messageText = ""
    @FocusState private var isInputFocused: Bool

    private var messages: [StoredMessage] {
        appState.conversations[contact.id] ?? []
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(messages) { stored in
                            MessageBubble(stored: stored)
                                .id(stored.id)
                        }
                    }
                    .padding()
                }
                .onChange(of: messages.count) {
                    if let last = messages.last {
                        withAnimation {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }

            Divider()

            HStack(spacing: 12) {
                TextField("Message", text: $messageText)
                    .textFieldStyle(.plain)
                    .focused($isInputFocused)
                    .onSubmit { sendMessage() }

                Button(action: sendMessage) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(messageText.isEmpty ? .gray : .blue)
                }
                .disabled(messageText.isEmpty)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .navigationTitle(contact.displayName)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private func sendMessage() {
        let text = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        messageText = ""

        Task {
            await appState.sendMessage(text: text, to: contact)
        }
    }
}

struct MessageBubble: View {
    let stored: StoredMessage

    var body: some View {
        HStack {
            if stored.direction == .sent { Spacer(minLength: 60) }

            VStack(alignment: stored.direction == .sent ? .trailing : .leading, spacing: 2) {
                Text(stored.decryptedText ?? "Encrypted")
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(stored.direction == .sent ? Color.blue : Color.gray.opacity(0.2))
                    .foregroundStyle(stored.direction == .sent ? .white : .primary)
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                HStack(spacing: 4) {
                    Text(stored.message.timestamp, style: .time)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)

                    if stored.direction == .sent {
                        deliveryLabel(stored.deliveryState)
                    }
                }
            }

            if stored.direction == .received { Spacer(minLength: 60) }
        }
    }

    @ViewBuilder
    private func deliveryLabel(_ state: DeliveryState) -> some View {
        switch state {
        case .queued:
            Label("Queued", systemImage: "clock")
                .font(.caption2)
                .foregroundStyle(.secondary)
        case .carried:
            Label("Carried", systemImage: "arrow.right.circle")
                .font(.caption2)
                .foregroundStyle(.orange)
        case .delivered:
            Label("Delivered", systemImage: "checkmark")
                .font(.caption2)
                .foregroundStyle(.green)
        case .read:
            Label("Read", systemImage: "checkmark.circle.fill")
                .font(.caption2)
                .foregroundStyle(.blue)
        }
    }
}
