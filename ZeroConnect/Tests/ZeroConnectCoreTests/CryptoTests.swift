import CryptoKit
import Foundation
import Testing

@testable import ZeroConnectCore

@Suite("Message Crypto Tests")
struct CryptoTests {
    let crypto = MessageCrypto()

    @Test("Encrypt and decrypt round-trip produces original message")
    func encryptDecryptRoundTrip() throws {
        let senderKey = P256.KeyAgreement.PrivateKey()
        let recipientKey = P256.KeyAgreement.PrivateKey()

        let content = MessageContent(text: "Hello from Kabala!")
        let (encrypted, _) = try crypto.encrypt(
            content: content,
            senderPrivateKey: senderKey,
            recipientPublicKey: recipientKey.publicKey
        )

        let decrypted = try crypto.decrypt(
            encryptedPayload: encrypted,
            senderPublicKey: senderKey.publicKey,
            recipientPrivateKey: recipientKey
        )

        #expect(decrypted.text == "Hello from Kabala!")
    }

    @Test("Different key pairs produce different ciphertexts")
    func differentKeysDifferentCiphertext() throws {
        let sender = P256.KeyAgreement.PrivateKey()
        let recipient1 = P256.KeyAgreement.PrivateKey()
        let recipient2 = P256.KeyAgreement.PrivateKey()

        let content = MessageContent(text: "Same message")

        let (encrypted1, _) = try crypto.encrypt(
            content: content,
            senderPrivateKey: sender,
            recipientPublicKey: recipient1.publicKey
        )

        let (encrypted2, _) = try crypto.encrypt(
            content: content,
            senderPrivateKey: sender,
            recipientPublicKey: recipient2.publicKey
        )

        #expect(encrypted1 != encrypted2)
    }

    @Test("Decryption with wrong key fails")
    func wrongKeyFails() throws {
        let sender = P256.KeyAgreement.PrivateKey()
        let recipient = P256.KeyAgreement.PrivateKey()
        let wrongRecipient = P256.KeyAgreement.PrivateKey()

        let content = MessageContent(text: "Secret")
        let (encrypted, _) = try crypto.encrypt(
            content: content,
            senderPrivateKey: sender,
            recipientPublicKey: recipient.publicKey
        )

        #expect(throws: (any Error).self) {
            _ = try crypto.decrypt(
                encryptedPayload: encrypted,
                senderPublicKey: sender.publicKey,
                recipientPrivateKey: wrongRecipient
            )
        }
    }

    @Test("Empty message encrypts and decrypts")
    func emptyMessage() throws {
        let sender = P256.KeyAgreement.PrivateKey()
        let recipient = P256.KeyAgreement.PrivateKey()

        let content = MessageContent(text: "")
        let (encrypted, _) = try crypto.encrypt(
            content: content,
            senderPrivateKey: sender,
            recipientPublicKey: recipient.publicKey
        )

        let decrypted = try crypto.decrypt(
            encryptedPayload: encrypted,
            senderPublicKey: sender.publicKey,
            recipientPrivateKey: recipient
        )

        #expect(decrypted.text == "")
    }

    @Test("Unicode message preserves content")
    func unicodeMessage() throws {
        let sender = P256.KeyAgreement.PrivateKey()
        let recipient = P256.KeyAgreement.PrivateKey()

        // Krio/mixed script test
        let text = "Aw di bodi? 你好 🇸🇱"
        let content = MessageContent(text: text)
        let (encrypted, _) = try crypto.encrypt(
            content: content,
            senderPrivateKey: sender,
            recipientPublicKey: recipient.publicKey
        )

        let decrypted = try crypto.decrypt(
            encryptedPayload: encrypted,
            senderPublicKey: sender.publicKey,
            recipientPrivateKey: recipient
        )

        #expect(decrypted.text == text)
    }
}

@Suite("QR Code Identity Tests")
struct QRCodeIdentityTests {
    @Test("Encode and decode round-trip")
    func encodeDecodeRoundTrip() throws {
        let key = P256.KeyAgreement.PrivateKey()
        let pubKeyData = key.publicKey.x963Representation

        let identity = QRCodeIdentity(publicKey: pubKeyData, displayName: "Ibrahim")
        let encoded = try identity.encodeToString()
        let decoded = try QRCodeIdentity.decode(from: encoded)

        #expect(decoded.publicKey == pubKeyData)
        #expect(decoded.displayName == "Ibrahim")
        #expect(decoded.version == 1)
    }

    @Test("Invalid base64 throws error")
    func invalidBase64Throws() {
        #expect(throws: QRCodeError.self) {
            _ = try QRCodeIdentity.decode(from: "not-valid-base64!!!")
        }
    }

    @Test("toContact creates correct contact")
    func toContactCreation() throws {
        let key = P256.KeyAgreement.PrivateKey()
        let pubKeyData = key.publicKey.x963Representation

        let identity = QRCodeIdentity(publicKey: pubKeyData, displayName: "Fatmata")
        let contact = identity.toContact()

        #expect(contact.displayName == "Fatmata")
        #expect(contact.publicKey == pubKeyData)
    }
}

@Suite("Message Model Tests")
struct MessageModelTests {
    @Test("Message is Codable")
    func messageCodable() throws {
        let message = Message(
            senderPublicKey: Data([1, 2, 3]),
            recipientPublicKey: Data([4, 5, 6]),
            encryptedPayload: Data([7, 8, 9]),
            nonce: Data([10, 11, 12])
        )

        let encoded = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(Message.self, from: encoded)

        #expect(decoded.id == message.id)
        #expect(decoded.senderPublicKey == message.senderPublicKey)
        #expect(decoded.recipientPublicKey == message.recipientPublicKey)
        #expect(decoded.encryptedPayload == message.encryptedPayload)
        #expect(decoded.nonce == message.nonce)
    }

    @Test("StoredMessage tracks delivery state")
    func storedMessageDeliveryState() {
        let message = Message(
            senderPublicKey: Data(),
            recipientPublicKey: Data(),
            encryptedPayload: Data(),
            nonce: Data()
        )

        var stored = StoredMessage(
            message: message,
            deliveryState: .queued,
            direction: .sent,
            decryptedText: "Hello"
        )

        #expect(stored.deliveryState == .queued)
        stored.deliveryState = .delivered
        #expect(stored.deliveryState == .delivered)
    }

    @Test("Contact is Codable")
    func contactCodable() throws {
        let contact = Contact(
            publicKey: Data([1, 2, 3]),
            displayName: "Musa",
            meshtasticNodeId: 42,
            loomDeviceId: UUID()
        )

        let encoded = try JSONEncoder().encode(contact)
        let decoded = try JSONDecoder().decode(Contact.self, from: encoded)

        #expect(decoded.displayName == "Musa")
        #expect(decoded.meshtasticNodeId == 42)
        #expect(decoded.loomDeviceId == contact.loomDeviceId)
    }
}
