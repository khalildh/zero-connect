import Foundation

/// Splits large messages into fragments that fit within LoRa packet size limits.
///
/// Meshtastic LoRa packets have a maximum payload of ~230 bytes. A CompactMessage
/// with compressed keys is ~130 bytes for a short message, but longer messages or
/// messages with x963 keys may exceed this limit.
///
/// Fragment format (big-endian):
///   [16 bytes] original message UUID (groups fragments together)
///   [1 byte]   fragment index (0-based)
///   [1 byte]   total fragment count
///   [remaining] fragment payload
///
/// The receiver collects all fragments for a UUID, then reassembles.
public struct MessageFragmenter: Sendable {
    /// Maximum payload per LoRa packet. Conservative limit accounting for
    /// Meshtastic protocol overhead.
    public static let maxLoRaPayload = 230

    /// Header overhead per fragment (16 UUID + 1 index + 1 total).
    public static let fragmentHeaderSize = 18

    /// Max data per fragment after header.
    public static let maxFragmentData = maxLoRaPayload - fragmentHeaderSize

    /// Split data into fragments that fit within LoRa limits.
    /// Returns the original data wrapped in a single-element array if it fits.
    public static func fragment(_ data: Data, messageId: UUID) -> [Data] {
        guard data.count > maxLoRaPayload else {
            return [data] // No fragmentation needed
        }

        let chunkSize = maxFragmentData
        var fragments: [Data] = []
        var offset = 0

        // Calculate total fragments
        let totalFragments = (data.count + chunkSize - 1) / chunkSize
        guard totalFragments <= 255 else {
            // Message too large even for fragmentation
            return [data]
        }

        while offset < data.count {
            let end = min(offset + chunkSize, data.count)
            let chunk = data[offset..<end]

            var fragment = Data()

            // Message UUID (16 bytes)
            withUnsafeBytes(of: messageId.uuid) { fragment.append(contentsOf: $0) }

            // Fragment index (1 byte)
            fragment.append(UInt8(fragments.count))

            // Total fragments (1 byte)
            fragment.append(UInt8(totalFragments))

            // Payload
            fragment.append(contentsOf: chunk)

            fragments.append(fragment)
            offset = end
        }

        return fragments
    }

    /// Check if data is a fragment (has the fragment header pattern).
    /// A fragment is at least 18 bytes and fits within LoRa limits.
    public static func isFragment(_ data: Data) -> Bool {
        guard data.count >= fragmentHeaderSize, data.count <= maxLoRaPayload else {
            return false
        }
        let totalFragments = Int(data[16 + 1]) // byte at offset 17
        return totalFragments > 1
    }

    /// Extract fragment metadata without fully parsing.
    public static func fragmentInfo(_ data: Data) -> (messageId: UUID, index: Int, total: Int, payload: Data)? {
        guard data.count >= fragmentHeaderSize else { return nil }

        var uuidValue = uuid_t(0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
        withUnsafeMutableBytes(of: &uuidValue) { dest in
            data.copyBytes(to: dest.bindMemory(to: UInt8.self), from: 0..<16)
        }
        let messageId = UUID(uuid: uuidValue)

        let index = Int(data[16])
        let total = Int(data[17])
        let payload = data[fragmentHeaderSize...]

        return (messageId, index, total, Data(payload))
    }
}

/// Collects fragments and reassembles complete messages.
public actor FragmentCollector {
    private var pending: [UUID: PendingMessage] = [:]

    /// Maximum age before dropping incomplete fragment sets.
    private let maxAge: TimeInterval = 60 // 1 minute

    public init() {}

    /// Add a fragment. Returns the reassembled data if all fragments are collected.
    public func addFragment(_ data: Data) -> Data? {
        guard let info = MessageFragmenter.fragmentInfo(data) else { return nil }

        if pending[info.messageId] == nil {
            pending[info.messageId] = PendingMessage(
                totalFragments: info.total,
                receivedAt: Date()
            )
        }

        pending[info.messageId]?.fragments[info.index] = info.payload

        // Check if complete
        guard let pm = pending[info.messageId],
              pm.fragments.count == pm.totalFragments else {
            return nil
        }

        // Reassemble in order
        var reassembled = Data()
        for i in 0..<pm.totalFragments {
            guard let chunk = pm.fragments[i] else { return nil }
            reassembled.append(chunk)
        }

        pending.removeValue(forKey: info.messageId)
        return reassembled
    }

    /// Remove expired incomplete fragment sets.
    public func pruneExpired() {
        let cutoff = Date().addingTimeInterval(-maxAge)
        pending = pending.filter { $0.value.receivedAt > cutoff }
    }

    /// Number of messages currently being reassembled.
    public var pendingCount: Int {
        pending.count
    }
}

private struct PendingMessage {
    let totalFragments: Int
    var fragments: [Int: Data] = [:]
    let receivedAt: Date
}
