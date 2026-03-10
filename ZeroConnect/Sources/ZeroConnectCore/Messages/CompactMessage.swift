import Foundation

/// A compact binary encoding for messages that minimizes byte count.
///
/// Standard JSON encoding of a Message is ~400+ bytes, far too large for
/// Meshtastic LoRa (max ~230 bytes per packet). CompactMessage encodes
/// the same data in ~130 bytes using binary packing:
///
/// Format (big-endian):
///   [16 bytes] message UUID
///   [1 byte]   sender public key length
///   [N bytes]  sender public key (typically 33 or 65 bytes)
///   [1 byte]   recipient public key length
///   [N bytes]  recipient public key
///   [8 bytes]  timestamp (Unix epoch seconds, Double)
///   [12 bytes] nonce
///   [remaining] encrypted payload
public struct CompactMessage: Sendable {
    /// Encode a Message into compact binary format.
    public static func encode(_ message: Message) -> Data {
        var data = Data()

        // UUID (16 bytes)
        let uuid = message.id
        withUnsafeBytes(of: uuid.uuid) { data.append(contentsOf: $0) }

        // Sender public key (1 byte length + key data)
        data.append(UInt8(message.senderPublicKey.count))
        data.append(message.senderPublicKey)

        // Recipient public key (1 byte length + key data)
        data.append(UInt8(message.recipientPublicKey.count))
        data.append(message.recipientPublicKey)

        // Timestamp (8 bytes, Double)
        var timestamp = message.timestamp.timeIntervalSince1970
        withUnsafeBytes(of: &timestamp) { data.append(contentsOf: $0) }

        // Nonce (variable, but typically 12 bytes for ChaChaPoly)
        data.append(UInt8(message.nonce.count))
        data.append(message.nonce)

        // Encrypted payload (remaining bytes)
        data.append(message.encryptedPayload)

        return data
    }

    /// Decode a Message from compact binary format.
    public static func decode(_ data: Data) throws -> Message {
        guard data.count >= 16 + 1 + 1 + 8 + 1 else {
            throw CompactMessageError.tooShort
        }

        var offset = 0

        // UUID (16 bytes) — copy to aligned buffer
        var uuidValue = uuid_t(0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
        withUnsafeMutableBytes(of: &uuidValue) { dest in
            data.copyBytes(to: dest.bindMemory(to: UInt8.self), from: offset..<offset + 16)
        }
        offset += 16
        let messageId = UUID(uuid: uuidValue)

        // Sender public key
        let senderLen = Int(data[offset])
        offset += 1
        guard offset + senderLen <= data.count else { throw CompactMessageError.truncated }
        let senderKey = data[offset..<offset + senderLen]
        offset += senderLen

        // Recipient public key
        let recipientLen = Int(data[offset])
        offset += 1
        guard offset + recipientLen <= data.count else { throw CompactMessageError.truncated }
        let recipientKey = data[offset..<offset + recipientLen]
        offset += recipientLen

        // Timestamp (8 bytes) — copy to aligned buffer
        guard offset + 8 <= data.count else { throw CompactMessageError.truncated }
        var timestamp: Double = 0
        withUnsafeMutableBytes(of: &timestamp) { dest in
            data.copyBytes(to: dest.bindMemory(to: UInt8.self), from: offset..<offset + 8)
        }
        offset += 8

        // Nonce
        let nonceLen = Int(data[offset])
        offset += 1
        guard offset + nonceLen <= data.count else { throw CompactMessageError.truncated }
        let nonce = data[offset..<offset + nonceLen]
        offset += nonceLen

        // Encrypted payload (remaining)
        let payload = data[offset...]

        return Message(
            id: messageId,
            senderPublicKey: Data(senderKey),
            recipientPublicKey: Data(recipientKey),
            encryptedPayload: Data(payload),
            timestamp: Date(timeIntervalSince1970: timestamp),
            nonce: Data(nonce)
        )
    }
}

public enum CompactMessageError: Error, Sendable {
    case tooShort
    case truncated
}
