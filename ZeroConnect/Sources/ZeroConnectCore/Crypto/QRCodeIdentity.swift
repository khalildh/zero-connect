import CryptoKit
import Foundation

/// Data encoded in a QR code for contact exchange.
/// When two people scan each other's QR codes, they exchange public keys and display names.
public struct QRCodeIdentity: Codable, Sendable {
    public let publicKey: Data
    public let displayName: String
    public let version: Int

    public init(publicKey: Data, displayName: String) {
        self.publicKey = publicKey
        self.displayName = displayName
        self.version = 1
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

    /// Convert to a Contact.
    public func toContact() -> Contact {
        Contact(
            publicKey: publicKey,
            displayName: displayName
        )
    }
}

public enum QRCodeError: Error, Sendable {
    case invalidBase64
}
