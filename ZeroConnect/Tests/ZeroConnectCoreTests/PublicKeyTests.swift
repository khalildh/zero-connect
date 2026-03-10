import CryptoKit
import Foundation
import Testing

@testable import ZeroConnectCore

@Suite("PublicKeyUtils Tests")
struct PublicKeyTests {
    @Test("x963 round-trip (65 bytes)")
    func x963RoundTrip() throws {
        let key = P256.KeyAgreement.PrivateKey().publicKey
        let data = PublicKeyUtils.encode(key, format: .x963)

        #expect(data.count == 65)

        let decoded = try PublicKeyUtils.decode(data)
        #expect(decoded.x963Representation == key.x963Representation)
    }

    @Test("Compressed round-trip (33 bytes)")
    func compressedRoundTrip() throws {
        let key = P256.KeyAgreement.PrivateKey().publicKey
        let data = PublicKeyUtils.encode(key, format: .compressed)

        #expect(data.count == 33)

        let decoded = try PublicKeyUtils.decode(data)
        #expect(decoded.x963Representation == key.x963Representation)
    }

    @Test("Auto-detect format from data size")
    func autoDetect() throws {
        let key = P256.KeyAgreement.PrivateKey().publicKey

        let x963 = key.x963Representation
        let compressed = key.compressedRepresentation

        let fromX963 = try PublicKeyUtils.decode(x963)
        let fromCompressed = try PublicKeyUtils.decode(compressed)

        // Both should produce the same key
        #expect(fromX963.x963Representation == fromCompressed.x963Representation)
    }

    @Test("Invalid size throws error")
    func invalidSize() {
        let badData = Data(repeating: 0, count: 42)
        #expect(throws: PublicKeyError.self) {
            _ = try PublicKeyUtils.decode(badData)
        }
    }

    @Test("Compressed key saves 32 bytes over x963")
    func sizeSavings() {
        let key = P256.KeyAgreement.PrivateKey().publicKey
        let x963 = PublicKeyUtils.encode(key, format: .x963)
        let compressed = PublicKeyUtils.encode(key, format: .compressed)

        #expect(x963.count - compressed.count == 32)
    }

    @Test("ECDH works with both key formats")
    func ecdhWithBothFormats() throws {
        let alice = P256.KeyAgreement.PrivateKey()
        let bob = P256.KeyAgreement.PrivateKey()

        // Encode Bob's key in compressed format
        let bobCompressed = PublicKeyUtils.encode(bob.publicKey, format: .compressed)
        let bobRestored = try PublicKeyUtils.decode(bobCompressed)

        // Alice performs ECDH with restored key
        let secret1 = try alice.sharedSecretFromKeyAgreement(with: bobRestored)
        let secret2 = try alice.sharedSecretFromKeyAgreement(with: bob.publicKey)

        // Both should produce the same shared secret
        let key1 = secret1.hkdfDerivedSymmetricKey(
            using: SHA256.self, salt: Data(), sharedInfo: Data(), outputByteCount: 32
        )
        let key2 = secret2.hkdfDerivedSymmetricKey(
            using: SHA256.self, salt: Data(), sharedInfo: Data(), outputByteCount: 32
        )

        #expect(key1 == key2)
    }
}
