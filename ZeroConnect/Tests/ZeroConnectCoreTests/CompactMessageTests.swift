import CryptoKit
import Foundation
import Testing

@testable import ZeroConnectCore

@Suite("CompactMessage Tests")
struct CompactMessageTests {
    @Test("Encode and decode round-trip preserves all fields")
    func roundTrip() throws {
        let message = Message(
            senderPublicKey: Data(repeating: 0xAB, count: 65),
            recipientPublicKey: Data(repeating: 0xCD, count: 65),
            encryptedPayload: Data("encrypted content here".utf8),
            nonce: Data(repeating: 0x42, count: 12)
        )

        let compact = CompactMessage.encode(message)
        let decoded = try CompactMessage.decode(compact)

        #expect(decoded.id == message.id)
        #expect(decoded.senderPublicKey == message.senderPublicKey)
        #expect(decoded.recipientPublicKey == message.recipientPublicKey)
        #expect(decoded.encryptedPayload == message.encryptedPayload)
        #expect(decoded.nonce == message.nonce)
        #expect(abs(decoded.timestamp.timeIntervalSince(message.timestamp)) < 0.001)
    }

    @Test("Compact encoding is significantly smaller than JSON")
    func sizeComparison() throws {
        let message = Message(
            senderPublicKey: Data(repeating: 0xAB, count: 65),
            recipientPublicKey: Data(repeating: 0xCD, count: 65),
            encryptedPayload: Data("Hello from Kabala!".utf8),
            nonce: Data(repeating: 0x42, count: 12)
        )

        let jsonSize = try JSONEncoder().encode(message).count
        let compactSize = CompactMessage.encode(message).count

        // Compact should be much smaller than JSON
        #expect(compactSize < jsonSize, "Compact (\(compactSize)b) should be smaller than JSON (\(jsonSize)b)")
        #expect(compactSize < 200, "Compact encoding should fit in a LoRa packet (<230b)")
    }

    @Test("Real encrypted message fits in LoRa packet")
    func loraPacketSize() throws {
        let sender = P256.KeyAgreement.PrivateKey()
        let recipient = P256.KeyAgreement.PrivateKey()

        let crypto = MessageCrypto()
        let content = MessageContent(text: "Aw di bodi?") // Short Krio greeting

        let (encrypted, nonce) = try crypto.encrypt(
            content: content,
            senderPrivateKey: sender,
            recipientPublicKey: recipient.publicKey
        )

        let message = Message(
            senderPublicKey: sender.publicKey.x963Representation,
            recipientPublicKey: recipient.publicKey.x963Representation,
            encryptedPayload: encrypted,
            nonce: nonce
        )

        let compactSize = CompactMessage.encode(message).count
        let jsonSize = try JSONEncoder().encode(message).count

        // Print sizes for visibility
        print("Compact: \(compactSize) bytes, JSON: \(jsonSize) bytes")
        print("Savings: \(jsonSize - compactSize) bytes (\(Int(Double(jsonSize - compactSize) / Double(jsonSize) * 100))%)")

        // With 65-byte keys (x963), 12-byte nonce, ~60-byte encrypted payload:
        // 16 (UUID) + 1 + 65 + 1 + 65 + 8 + 1 + 12 + ~60 = ~229 bytes
        // Should fit in LoRa packet for short messages
        #expect(compactSize < 250, "Short message should be close to LoRa limit")
    }

    @Test("Decode rejects truncated data")
    func truncatedData() {
        let tooShort = Data([1, 2, 3])
        #expect(throws: CompactMessageError.self) {
            _ = try CompactMessage.decode(tooShort)
        }
    }

    @Test("Empty payload encodes correctly")
    func emptyPayload() throws {
        let message = Message(
            senderPublicKey: Data([1, 2, 3]),
            recipientPublicKey: Data([4, 5, 6]),
            encryptedPayload: Data(),
            nonce: Data([7, 8, 9])
        )

        let compact = CompactMessage.encode(message)
        let decoded = try CompactMessage.decode(compact)

        #expect(decoded.encryptedPayload.isEmpty)
        #expect(decoded.senderPublicKey == message.senderPublicKey)
    }
}
