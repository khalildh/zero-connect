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

    @Test("Meshtastic uses compact binary encoding on the wire")
    func meshtasticCompactEncoding() async throws {
        let identity = IdentityManager()
        let router = MessageRouter(identity: identity)

        let meshTransport = MockTransport(kind: .meshtastic)
        await router.addTransport(meshTransport)

        let contact = Contact(
            publicKey: Data(repeating: 0, count: 65),
            displayName: "Mesh User",
            meshtasticNodeId: 7
        )

        let meshPeer = TransportPeer(
            id: "mesh-7",
            displayName: "Mesh User",
            transport: .meshtastic,
            transportIdentifier: "7"
        )

        await meshTransport.addPeer(meshPeer)
        await router.refreshPeers()

        let message = Message(
            senderPublicKey: Data(repeating: 1, count: 33),
            recipientPublicKey: Data(repeating: 0, count: 65),
            encryptedPayload: Data([4, 5, 6]),
            nonce: Data(repeating: 0, count: 12)
        )

        try await router.send(message, to: contact)

        let sent = await meshTransport.getSentMessages()
        #expect(sent.count == 1)

        // Wire data should be compact binary, not JSON
        let wireData = sent[0].0
        // CompactMessage starts with the UUID (16 bytes), not JSON's '{' (0x7B)
        #expect(wireData[0] != 0x7B, "Should not be JSON-encoded for Meshtastic")

        // Should be decodable as CompactMessage
        let decoded = try CompactMessage.decode(wireData)
        #expect(decoded.id == message.id)
    }

    @Test("Loom uses JSON envelope encoding on the wire")
    func loomJsonEncoding() async throws {
        let identity = IdentityManager()
        let router = MessageRouter(identity: identity)

        let loomTransport = MockTransport(kind: .loom)
        await router.addTransport(loomTransport)

        let loomDeviceId = UUID()
        let contact = Contact(
            publicKey: Data(repeating: 0, count: 65),
            displayName: "Loom User",
            loomDeviceId: loomDeviceId
        )

        let loomPeer = TransportPeer(
            id: "loom-\(loomDeviceId.uuidString)",
            displayName: "Loom User",
            transport: .loom,
            transportIdentifier: loomDeviceId.uuidString
        )

        await loomTransport.addPeer(loomPeer)
        await router.refreshPeers()

        let message = Message(
            senderPublicKey: Data([1, 2, 3]),
            recipientPublicKey: Data(repeating: 0, count: 65),
            encryptedPayload: Data([4, 5, 6]),
            nonce: Data([7, 8, 9])
        )

        try await router.send(message, to: contact)

        let sent = await loomTransport.getSentMessages()
        #expect(sent.count == 1)

        // Wire data should be JSON TransportEnvelope
        let envelope = try JSONDecoder().decode(TransportEnvelope.self, from: sent[0].0)
        if case .message(let decoded) = envelope {
            #expect(decoded.id == message.id)
        } else {
            Issue.record("Expected .message envelope")
        }
    }

    @Test("Meshtastic uses compact encoding flag")
    func compactEncodingFlag() {
        #expect(TransportKind.meshtastic.usesCompactEncoding == true)
        #expect(TransportKind.loom.usesCompactEncoding == false)
        #expect(TransportKind.server.usesCompactEncoding == false)
    }

    @Test("Large messages are fragmented for Meshtastic")
    func meshtasticFragmentation() async throws {
        let identity = IdentityManager()
        let router = MessageRouter(identity: identity)

        let meshTransport = MockTransport(kind: .meshtastic)
        await router.addTransport(meshTransport)

        let contact = Contact(
            publicKey: Data(repeating: 0, count: 65),
            displayName: "Mesh User",
            meshtasticNodeId: 7
        )

        let meshPeer = TransportPeer(
            id: "mesh-7",
            displayName: "Mesh User",
            transport: .meshtastic,
            transportIdentifier: "7"
        )

        await meshTransport.addPeer(meshPeer)
        await router.refreshPeers()

        // Create a message with a large encrypted payload that will exceed LoRa limits
        let message = Message(
            senderPublicKey: Data(repeating: 1, count: 65),
            recipientPublicKey: Data(repeating: 0, count: 65),
            encryptedPayload: Data(repeating: 42, count: 200),
            nonce: Data(repeating: 0, count: 12)
        )

        try await router.send(message, to: contact)

        let sent = await meshTransport.getSentMessages()
        // With 65+65+200+12+16+3 = 361 bytes compact, should fragment into 2+ packets
        #expect(sent.count >= 2, "Large message should be fragmented for Meshtastic")

        // Each fragment should fit in LoRa packet
        for (data, _) in sent {
            #expect(data.count <= MessageFragmenter.maxLoRaPayload,
                    "Each fragment should fit in LoRa packet")
        }
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
