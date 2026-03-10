import Foundation

/// A unified message type that can travel over any transport.
/// The transport layer sees only the encrypted envelope — it doesn't know or care about content.
public struct Message: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let senderPublicKey: Data
    public let recipientPublicKey: Data
    public let encryptedPayload: Data
    public let timestamp: Date
    public let nonce: Data

    public init(
        id: UUID = UUID(),
        senderPublicKey: Data,
        recipientPublicKey: Data,
        encryptedPayload: Data,
        timestamp: Date = Date(),
        nonce: Data
    ) {
        self.id = id
        self.senderPublicKey = senderPublicKey
        self.recipientPublicKey = recipientPublicKey
        self.encryptedPayload = encryptedPayload
        self.timestamp = timestamp
        self.nonce = nonce
    }
}

/// The plaintext content before encryption.
public struct MessageContent: Codable, Sendable {
    public let text: String
    public let timestamp: Date

    public init(text: String, timestamp: Date = Date()) {
        self.text = text
        self.timestamp = timestamp
    }
}

/// Delivery state visible to the user.
public enum DeliveryState: String, Codable, Sendable {
    /// Message is on this phone, waiting for a path
    case queued
    /// A relay device has picked it up
    case carried
    /// Recipient's device has received it
    case delivered
    /// Recipient has opened it
    case read
}

/// A stored message with its delivery metadata.
public struct StoredMessage: Identifiable, Codable, Sendable {
    public let message: Message
    public var deliveryState: DeliveryState
    public let direction: Direction
    /// Decrypted text (only available to sender/recipient, not relays)
    public var decryptedText: String?

    public var id: UUID { message.id }

    public enum Direction: String, Codable, Sendable {
        case sent
        case received
    }

    public init(
        message: Message,
        deliveryState: DeliveryState,
        direction: Direction,
        decryptedText: String? = nil
    ) {
        self.message = message
        self.deliveryState = deliveryState
        self.direction = direction
        self.decryptedText = decryptedText
    }
}
