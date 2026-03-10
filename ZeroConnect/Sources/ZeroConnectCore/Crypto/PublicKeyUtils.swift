import CryptoKit
import Foundation

/// Utilities for P-256 public key serialization.
///
/// Supports two formats:
/// - **x963** (65 bytes): Standard uncompressed format. Used in QR codes and
///   JSON messages where size isn't critical.
/// - **Compressed** (33 bytes): SEC1 compressed format (x-coordinate + parity).
///   Used in compact binary encoding for LoRa where every byte matters.
public enum PublicKeyFormat: Sendable {
    case x963        // 65 bytes (04 || x || y)
    case compressed  // 33 bytes (02/03 || x)
}

public struct PublicKeyUtils: Sendable {
    /// Encode a public key in the specified format.
    public static func encode(
        _ key: P256.KeyAgreement.PublicKey,
        format: PublicKeyFormat = .x963
    ) -> Data {
        switch format {
        case .x963:
            return key.x963Representation
        case .compressed:
            return key.compressedRepresentation
        }
    }

    /// Decode a public key from data, auto-detecting the format.
    public static func decode(_ data: Data) throws -> P256.KeyAgreement.PublicKey {
        switch data.count {
        case 33:
            return try P256.KeyAgreement.PublicKey(compressedRepresentation: data)
        case 65:
            return try P256.KeyAgreement.PublicKey(x963Representation: data)
        default:
            throw PublicKeyError.invalidKeySize(data.count)
        }
    }
}

public enum PublicKeyError: Error, Sendable {
    case invalidKeySize(Int)
}
