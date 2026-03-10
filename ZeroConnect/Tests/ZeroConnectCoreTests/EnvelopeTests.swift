import Foundation
import Testing

@testable import ZeroConnectCore

@Suite("TransportEnvelope Tests")
struct EnvelopeTests {
    @Test("Message envelope round-trip")
    func messageEnvelopeRoundTrip() throws {
        let message = Message(
            senderPublicKey: Data([1, 2, 3]),
            recipientPublicKey: Data([4, 5, 6]),
            encryptedPayload: Data([7, 8, 9]),
            nonce: Data([10, 11, 12])
        )

        let envelope = TransportEnvelope.message(message)
        let encoded = try JSONEncoder().encode(envelope)
        let decoded = try JSONDecoder().decode(TransportEnvelope.self, from: encoded)

        if case .message(let decodedMsg) = decoded {
            #expect(decodedMsg.id == message.id)
            #expect(decodedMsg.senderPublicKey == message.senderPublicKey)
        } else {
            Issue.record("Expected message envelope")
        }
    }

    @Test("Receipt envelope round-trip")
    func receiptEnvelopeRoundTrip() throws {
        let messageId = UUID()
        let receipt = DeliveryReceipt(messageId: messageId, status: .delivered)
        let envelope = TransportEnvelope.receipt(receipt)

        let encoded = try JSONEncoder().encode(envelope)
        let decoded = try JSONDecoder().decode(TransportEnvelope.self, from: encoded)

        if case .receipt(let decodedReceipt) = decoded {
            #expect(decodedReceipt.messageId == messageId)
            #expect(decodedReceipt.status == .delivered)
        } else {
            Issue.record("Expected receipt envelope")
        }
    }

    @Test("Different envelope types are distinguishable")
    func envelopeTypeDistinction() throws {
        let message = Message(
            senderPublicKey: Data([1]),
            recipientPublicKey: Data([2]),
            encryptedPayload: Data([3]),
            nonce: Data([4])
        )
        let receipt = DeliveryReceipt(messageId: UUID(), status: .read)

        let msgEnvelope = TransportEnvelope.message(message)
        let rcptEnvelope = TransportEnvelope.receipt(receipt)

        let msgData = try JSONEncoder().encode(msgEnvelope)
        let rcptData = try JSONEncoder().encode(rcptEnvelope)

        let decodedMsg = try JSONDecoder().decode(TransportEnvelope.self, from: msgData)
        let decodedRcpt = try JSONDecoder().decode(TransportEnvelope.self, from: rcptData)

        switch decodedMsg {
        case .message: break // correct
        case .receipt: Issue.record("Expected message, got receipt")
        }

        switch decodedRcpt {
        case .receipt: break // correct
        case .message: Issue.record("Expected receipt, got message")
        }
    }

    @Test("DeliveryReceipt preserves all states")
    func deliveryReceiptStates() throws {
        for state in [DeliveryState.queued, .carried, .delivered, .read] {
            let receipt = DeliveryReceipt(messageId: UUID(), status: state)
            let data = try JSONEncoder().encode(receipt)
            let decoded = try JSONDecoder().decode(DeliveryReceipt.self, from: data)
            #expect(decoded.status == state)
        }
    }
}
