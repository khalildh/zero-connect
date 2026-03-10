import Foundation

/// A discovered peer on any transport.
public struct TransportPeer: Identifiable, Hashable, Sendable {
    public let id: String
    public let displayName: String
    public let transport: TransportKind
    /// Raw transport-specific identifier (Loom device ID, Meshtastic node ID, etc.)
    public let transportIdentifier: String
    /// Signal strength if available
    public var rssi: Int?

    public init(
        id: String,
        displayName: String,
        transport: TransportKind,
        transportIdentifier: String,
        rssi: Int? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.transport = transport
        self.transportIdentifier = transportIdentifier
        self.rssi = rssi
    }
}

/// Which transport a peer or message is using.
public enum TransportKind: String, Codable, Sendable, CaseIterable {
    case loom       // Wi-Fi / AWDL via Loom
    case meshtastic // LoRa via BLE to Meshtastic node
    case server     // Internet via message buffer server

    /// Bandwidth priority (higher = prefer this transport).
    public var priority: Int {
        switch self {
        case .server: return 3
        case .loom: return 2
        case .meshtastic: return 1
        }
    }

    /// Whether this transport should use compact binary encoding (for bandwidth-constrained links).
    public var usesCompactEncoding: Bool {
        self == .meshtastic
    }
}

/// Protocol that all transports implement.
/// Each transport handles discovery, connection, and data transfer
/// for its specific medium (Loom, Meshtastic, server).
public protocol Transport: Actor {
    /// The kind of transport.
    var kind: TransportKind { get }

    /// Whether this transport is currently available.
    var isAvailable: Bool { get }

    /// Start discovering nearby peers.
    func startDiscovery() async throws

    /// Stop discovering.
    func stopDiscovery() async

    /// Currently discovered peers.
    func discoveredPeers() async -> [TransportPeer]

    /// Send a serialized message to a peer.
    func send(_ data: Data, to peer: TransportPeer) async throws

    /// Stream of incoming (data, fromPeer) tuples.
    func incomingMessages() async -> AsyncStream<(Data, TransportPeer)>
}
