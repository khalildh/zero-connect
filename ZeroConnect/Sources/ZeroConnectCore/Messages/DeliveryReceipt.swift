import Foundation

/// A lightweight acknowledgment that a message was received.
///
/// When a device receives a message addressed to it, it creates a
/// DeliveryReceipt and sends it back to the sender. The receipt contains
/// only the message ID and a status — no content leaks.
public struct DeliveryReceipt: Codable, Sendable {
    public let messageId: UUID
    public let status: DeliveryState
    public let timestamp: Date

    /// Identifier to distinguish receipts from regular messages on the wire.
    public static let typeTag = "delivery-receipt-v1"

    public init(messageId: UUID, status: DeliveryState, timestamp: Date = Date()) {
        self.messageId = messageId
        self.status = status
        self.timestamp = timestamp
    }
}

/// Wrapper that allows sending both messages and receipts over the same transport.
public enum TransportEnvelope: Codable, Sendable {
    case message(Message)
    case receipt(DeliveryReceipt)

    private enum CodingKeys: String, CodingKey {
        case type, payload
    }

    private enum EnvelopeType: String, Codable {
        case message, receipt
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .message(let msg):
            try container.encode(EnvelopeType.message, forKey: .type)
            try container.encode(msg, forKey: .payload)
        case .receipt(let receipt):
            try container.encode(EnvelopeType.receipt, forKey: .type)
            try container.encode(receipt, forKey: .payload)
        }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(EnvelopeType.self, forKey: .type)
        switch type {
        case .message:
            let msg = try container.decode(Message.self, forKey: .payload)
            self = .message(msg)
        case .receipt:
            let receipt = try container.decode(DeliveryReceipt.self, forKey: .payload)
            self = .receipt(receipt)
        }
    }
}
