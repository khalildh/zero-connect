import CryptoKit
import Foundation

/// Data encoded in a QR code for contact exchange.
/// When two people scan each other's QR codes, they exchange public keys and display names.
///
/// Version 2 uses compressed public keys (33 bytes vs 65 bytes) to produce
/// simpler QR codes that are easier to scan in low-light conditions.
public struct QRCodeIdentity: Codable, Sendable {
    public let publicKey: Data
    public let displayName: String
    public let version: Int

    public init(publicKey: Data, displayName: String) {
        // Compress the key if it's in x963 format to reduce QR complexity
        if publicKey.count == 65,
           let key = try? P256.KeyAgreement.PublicKey(x963Representation: publicKey) {
            self.publicKey = key.compressedRepresentation
        } else {
            self.publicKey = publicKey
        }
        self.displayName = displayName
        self.version = 2
    }

    /// Encode to JSON data suitable for QR code generation.
    public func encode() throws -> Data {
        try JSONEncoder().encode(self)
    }

    /// Encode to a string for QR code display.
    public func encodeToString() throws -> String {
        let data = try encode()
        return data.base64EncodedString()
    }

    /// Decode from a QR code string.
    public static func decode(from string: String) throws -> QRCodeIdentity {
        guard let data = Data(base64Encoded: string) else {
            throw QRCodeError.invalidBase64
        }
        return try JSONDecoder().decode(QRCodeIdentity.self, from: data)
    }

    /// Convert to a Contact. Expands compressed keys back to x963 for storage.
    public func toContact() throws -> Contact {
        let expandedKey = try PublicKeyUtils.decode(publicKey)
        return Contact(
            publicKey: expandedKey.x963Representation,
            displayName: displayName
        )
    }
}

public enum QRCodeError: Error, Sendable {
    case invalidBase64
}
