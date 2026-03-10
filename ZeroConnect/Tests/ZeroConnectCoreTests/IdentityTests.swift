import CryptoKit
import Foundation
import Testing

@testable import ZeroConnectCore

@Suite("IdentityManager Tests")
struct IdentityTests {
    @Test("Public key data is consistent across calls")
    func publicKeyConsistency() async throws {
        let identity = IdentityManager()
        let key1 = try await identity.publicKeyData()
        let key2 = try await identity.publicKeyData()
        #expect(key1 == key2)
    }

    @Test("Public key hex is valid hex string")
    func publicKeyHexFormat() async throws {
        let identity = IdentityManager()
        let hex = try await identity.publicKeyHex()

        // Should be all hex characters
        let hexChars = CharacterSet(charactersIn: "0123456789abcdef")
        #expect(hex.unicodeScalars.allSatisfy { hexChars.contains($0) })

        // P-256 compact representation is 32 bytes = 64 hex chars
        // raw representation is 65 bytes = 130 hex chars
        #expect(hex.count == 64 || hex.count == 130)
    }

    @Test("Private key can perform ECDH key agreement")
    func ecdhKeyAgreement() async throws {
        let identity = IdentityManager()
        let privateKey = try await identity.privateKey()

        let otherKey = P256.KeyAgreement.PrivateKey()
        let sharedSecret = try privateKey.sharedSecretFromKeyAgreement(
            with: otherKey.publicKey
        )

        // Verify the other side derives the same shared secret
        let otherSharedSecret = try otherKey.sharedSecretFromKeyAgreement(
            with: privateKey.publicKey
        )

        // ECDH should produce the same shared secret from both sides
        let key1 = sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data("test".utf8),
            sharedInfo: Data(),
            outputByteCount: 32
        )
        let key2 = otherSharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data("test".utf8),
            sharedInfo: Data(),
            outputByteCount: 32
        )

        #expect(key1 == key2)
    }

    @Test("Full end-to-end message flow using IdentityManager")
    func fullMessageFlow() async throws {
        // Simulate two devices
        let aliceIdentity = IdentityManager()
        let bobKey = P256.KeyAgreement.PrivateKey()

        let alicePrivate = try await aliceIdentity.privateKey()
        let alicePubData = try await aliceIdentity.publicKeyData()

        // Alice encrypts a message to Bob
        let crypto = MessageCrypto()
        let content = MessageContent(text: "Kusheh, Bob!")

        let (encrypted, nonce) = try crypto.encrypt(
            content: content,
            senderPrivateKey: alicePrivate,
            recipientPublicKey: bobKey.publicKey
        )

        // Create the message envelope
        let message = Message(
            senderPublicKey: alicePubData,
            recipientPublicKey: bobKey.publicKey.x963Representation,
            encryptedPayload: encrypted,
            nonce: nonce
        )

        // Bob receives and decrypts
        let senderPubKey = try P256.KeyAgreement.PublicKey(
            x963Representation: message.senderPublicKey
        )
        let decrypted = try crypto.decrypt(
            encryptedPayload: message.encryptedPayload,
            senderPublicKey: senderPubKey,
            recipientPrivateKey: bobKey
        )

        #expect(decrypted.text == "Kusheh, Bob!")
    }
}
