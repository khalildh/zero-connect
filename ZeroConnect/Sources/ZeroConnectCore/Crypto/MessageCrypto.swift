import CryptoKit
import Foundation

/// Handles encrypting and decrypting messages using ECDH + ChaChaPoly.
///
/// Flow:
/// 1. Sender and recipient exchanged public keys via QR code
/// 2. Sender performs ECDH with recipient's public key to derive shared secret
/// 3. Shared secret is expanded via HKDF to get a symmetric key
/// 4. Message content is encrypted with ChaChaPoly (AEAD)
/// 5. Encrypted blob + nonce travels over any transport
/// 6. Recipient performs the same ECDH derivation and decrypts
public struct MessageCrypto: Sendable {

    public init() {}

    /// Encrypt a plaintext message to a recipient's public key.
    public func encrypt(
        content: MessageContent,
        senderPrivateKey: P256.KeyAgreement.PrivateKey,
        recipientPublicKey: P256.KeyAgreement.PublicKey
    ) throws -> (encryptedPayload: Data, nonce: Data) {
        let plaintext = try JSONEncoder().encode(content)
        let sharedSecret = try senderPrivateKey.sharedSecretFromKeyAgreement(
            with: recipientPublicKey
        )

        let symmetricKey = sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data("ZeroConnect-v1".utf8),
            sharedInfo: Data(),
            outputByteCount: 32
        )

        let sealedBox = try ChaChaPoly.seal(plaintext, using: symmetricKey)
        return (sealedBox.combined, Data(sealedBox.nonce))
    }

    /// Decrypt a message using the recipient's private key and sender's public key.
    public func decrypt(
        encryptedPayload: Data,
        senderPublicKey: P256.KeyAgreement.PublicKey,
        recipientPrivateKey: P256.KeyAgreement.PrivateKey
    ) throws -> MessageContent {
        let sharedSecret = try recipientPrivateKey.sharedSecretFromKeyAgreement(
            with: senderPublicKey
        )

        let symmetricKey = sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data("ZeroConnect-v1".utf8),
            sharedInfo: Data(),
            outputByteCount: 32
        )

        let sealedBox = try ChaChaPoly.SealedBox(combined: encryptedPayload)
        let plaintext = try ChaChaPoly.open(sealedBox, using: symmetricKey)
        return try JSONDecoder().decode(MessageContent.self, from: plaintext)
    }
}
