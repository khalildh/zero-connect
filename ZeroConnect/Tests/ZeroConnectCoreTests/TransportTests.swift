import Foundation
import Testing

@testable import ZeroConnectCore

/// A mock transport for testing message routing.
actor MockTransport: Transport {
    let kind: TransportKind
    var isAvailable: Bool = true

    private var peers: [TransportPeer] = []
    private var sentMessages: [(Data, TransportPeer)] = []
    private var messageContinuation: AsyncStream<(Data, TransportPeer)>.Continuation?
    private var messageStream: AsyncStream<(Data, TransportPeer)>?

    init(kind: TransportKind) {
        self.kind = kind
        let (stream, continuation) = AsyncStream<(Data, TransportPeer)>.makeStream()
        self.messageStream = stream
        self.messageContinuation = continuation
    }

    func addPeer(_ peer: TransportPeer) {
        peers.append(peer)
    }

    func startDiscovery() async throws {}
    func stopDiscovery() async {}

    func discoveredPeers() async -> [TransportPeer] {
        peers
    }

    func send(_ data: Data, to peer: TransportPeer) async throws {
        sentMessages.append((data, peer))
    }

    func incomingMessages() async -> AsyncStream<(Data, TransportPeer)> {
        messageStream ?? AsyncStream { $0.finish() }
    }

    func simulateIncoming(_ data: Data, from peer: TransportPeer) {
        messageContinuation?.yield((data, peer))
    }

    func getSentMessages() -> [(Data, TransportPeer)] {
        sentMessages
    }
}

@Suite("MessageRouter Tests")
struct TransportTests {
    @Test("Router selects highest priority transport")
    func routerPriority() async throws {
        let identity = IdentityManager()
        let router = MessageRouter(identity: identity)

        let loomTransport = MockTransport(kind: .loom)
        let meshTransport = MockTransport(kind: .meshtastic)

        await router.addTransport(loomTransport)
        await router.addTransport(meshTransport)

        let contact = Contact(
            publicKey: Data([1, 2, 3]),
            displayName: "Test",
            loomDeviceId: UUID()
        )

        let loomPeer = TransportPeer(
            id: "loom-\(contact.loomDeviceId!.uuidString)",
            displayName: "Test",
            transport: .loom,
            transportIdentifier: contact.loomDeviceId!.uuidString
        )
        let meshPeer = TransportPeer(
            id: "mesh-123",
            displayName: "Test",
            transport: .meshtastic,
            transportIdentifier: "123"
        )

        await loomTransport.addPeer(loomPeer)
        await meshTransport.addPeer(meshPeer)
        await router.refreshPeers()

        // Send a message — should go via Loom (priority 2 > meshtastic 1)
        let message = Message(
            senderPublicKey: Data([4, 5, 6]),
            recipientPublicKey: Data([1, 2, 3]),
            encryptedPayload: Data([7, 8, 9]),
            nonce: Data([10, 11, 12])
        )

        try await router.send(message, to: contact)

        let loomSent = await loomTransport.getSentMessages()
        let meshSent = await meshTransport.getSentMessages()

        #expect(loomSent.count == 1, "Message should be sent via Loom")
        #expect(meshSent.isEmpty, "Meshtastic should not be used when Loom is available")
    }

    @Test("Router falls back to lower priority transport")
    func routerFallback() async throws {
        let identity = IdentityManager()
        let router = MessageRouter(identity: identity)

        let meshTransport = MockTransport(kind: .meshtastic)
        await router.addTransport(meshTransport)

        let contact = Contact(
            publicKey: Data([1, 2, 3]),
            displayName: "Test",
            meshtasticNodeId: 42
        )

        let meshPeer = TransportPeer(
            id: "mesh-42",
            displayName: "Test",
            transport: .meshtastic,
            transportIdentifier: "42"
        )

        await meshTransport.addPeer(meshPeer)
        await router.refreshPeers()

        let message = Message(
            senderPublicKey: Data([4, 5, 6]),
            recipientPublicKey: Data([1, 2, 3]),
            encryptedPayload: Data([7, 8, 9]),
            nonce: Data([10, 11, 12])
        )

        try await router.send(message, to: contact)

        let sent = await meshTransport.getSentMessages()
        #expect(sent.count == 1, "Should fall back to Meshtastic")
    }

    @Test("Router throws when no transport available")
    func routerNoTransport() async throws {
        let identity = IdentityManager()
        let router = MessageRouter(identity: identity)

        let contact = Contact(
            publicKey: Data([1, 2, 3]),
            displayName: "Unreachable"
        )

        let message = Message(
            senderPublicKey: Data([4, 5, 6]),
            recipientPublicKey: Data([1, 2, 3]),
            encryptedPayload: Data([7, 8, 9]),
            nonce: Data([10, 11, 12])
        )

        await #expect(throws: RouterError.self) {
            try await router.send(message, to: contact)
        }
    }

    @Test("TransportKind priority ordering is correct")
    func transportPriority() {
        #expect(TransportKind.server.priority > TransportKind.loom.priority)
        #expect(TransportKind.loom.priority > TransportKind.meshtastic.priority)
    }
}

@Suite("ServerTransport Tests")
struct ServerTransportTests {
    @Test("Server transport queues messages when configured")
    func serverQueuesMessages() async throws {
        let server = ServerTransport(serverURL: URL(string: "https://example.com")!)

        let peer = TransportPeer(
            id: "server-abc",
            displayName: "Remote User",
            transport: .server,
            transportIdentifier: "abc123"
        )

        try await server.send(Data([1, 2, 3]), to: peer)

        let pending = await server.pendingMessages()
        #expect(pending.count == 1)
    }

    @Test("Server transport throws when not configured")
    func serverNotConfigured() async {
        let server = ServerTransport()

        let peer = TransportPeer(
            id: "server-abc",
            displayName: "Remote User",
            transport: .server,
            transportIdentifier: "abc123"
        )

        await #expect(throws: ServerTransportError.self) {
            try await server.send(Data([1, 2, 3]), to: peer)
        }
    }
}
