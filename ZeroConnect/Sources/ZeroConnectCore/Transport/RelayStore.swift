import Foundation

/// Stores encrypted messages for relay to their intended recipients.
///
/// When a device receives a message addressed to someone else, it can act
/// as a relay — storing the opaque encrypted blob and forwarding it when
/// the intended recipient comes into range. The relay never sees plaintext;
/// it only reads the recipientPublicKey to know where to forward.
///
/// This enables the "store and carry" pattern: a user in a remote area
/// composes a message, hands it to any passing device via Loom or Meshtastic,
/// and that device carries it until the recipient (or another relay closer
/// to them) appears.
public actor RelayStore {
    private var relayMessages: [RelayMessage] = []
    private let maxRelayMessages = 100
    private let maxAge: TimeInterval = 7 * 24 * 60 * 60 // 7 days

    public init() {}

    /// Store a message for relay.
    public func store(_ message: Message) {
        // Don't store duplicates
        guard !relayMessages.contains(where: { $0.message.id == message.id }) else { return }

        // Enforce capacity limit
        if relayMessages.count >= maxRelayMessages {
            // Remove oldest first
            relayMessages.sort { $0.receivedAt < $1.receivedAt }
            relayMessages.removeFirst()
        }

        relayMessages.append(RelayMessage(message: message))
    }

    /// Get all relay messages intended for a specific public key.
    public func messagesFor(recipientPublicKey: Data) -> [Message] {
        relayMessages
            .filter { $0.message.recipientPublicKey == recipientPublicKey }
            .map(\.message)
    }

    /// Remove messages that have been successfully delivered.
    public func markDelivered(messageIds: [UUID]) {
        relayMessages.removeAll { messageIds.contains($0.message.id) }
    }

    /// Remove expired messages.
    public func pruneExpired() {
        let cutoff = Date().addingTimeInterval(-maxAge)
        relayMessages.removeAll { $0.receivedAt < cutoff }
    }

    /// All messages currently held for relay.
    public var allRelayMessages: [RelayMessage] {
        relayMessages
    }

    public var count: Int {
        relayMessages.count
    }
}

/// A message being held for relay to its intended recipient.
public struct RelayMessage: Codable, Sendable {
    public let message: Message
    public let receivedAt: Date

    public init(message: Message, receivedAt: Date = Date()) {
        self.message = message
        self.receivedAt = receivedAt
    }
}
