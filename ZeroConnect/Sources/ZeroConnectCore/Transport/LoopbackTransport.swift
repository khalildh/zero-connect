import Foundation

/// A virtual transport for testing and development.
///
/// Two LoopbackTransport instances connected as a pair simulate a
/// bidirectional link. Messages sent on one are received by the other.
/// This lets you test the full messaging flow without hardware.
public actor LoopbackTransport: Transport {
    public let kind: TransportKind = .loom  // Presents as Loom for routing purposes

    private var peers: [TransportPeer] = []
    private var messageContinuation: AsyncStream<(Data, TransportPeer)>.Continuation?
    private var messageStream: AsyncStream<(Data, TransportPeer)>?
    private weak var partner: LoopbackTransport?
    private let localPeer: TransportPeer

    public var isAvailable: Bool { true }

    public init(localPeerName: String, localPeerId: String = UUID().uuidString) {
        self.localPeer = TransportPeer(
            id: "loopback-\(localPeerId)",
            displayName: localPeerName,
            transport: .loom,
            transportIdentifier: localPeerId
        )

        let (stream, continuation) = AsyncStream<(Data, TransportPeer)>.makeStream()
        self.messageStream = stream
        self.messageContinuation = continuation
    }

    /// Connect two loopback transports as a pair.
    public static func makePair(
        name1: String = "Device A",
        name2: String = "Device B"
    ) -> (LoopbackTransport, LoopbackTransport) {
        let a = LoopbackTransport(localPeerName: name1)
        let b = LoopbackTransport(localPeerName: name2)
        // Partner linking happens via connect()
        return (a, b)
    }

    /// Link this transport to its partner.
    public func connect(to other: LoopbackTransport) async {
        self.partner = other
        let otherPeer = await other.localPeer
        self.peers = [otherPeer]
    }

    public func startDiscovery() async throws {
        // Already discovered via connect()
    }

    public func stopDiscovery() async {}

    public func discoveredPeers() async -> [TransportPeer] {
        peers
    }

    public func send(_ data: Data, to peer: TransportPeer) async throws {
        guard let partner else {
            throw LoopbackError.notConnected
        }
        await partner.receive(data, from: localPeer)
    }

    public func incomingMessages() async -> AsyncStream<(Data, TransportPeer)> {
        messageStream ?? AsyncStream { $0.finish() }
    }

    /// Called by the partner transport to deliver a message to us.
    func receive(_ data: Data, from peer: TransportPeer) {
        messageContinuation?.yield((data, peer))
    }
}

public enum LoopbackError: Error, Sendable {
    case notConnected
}
