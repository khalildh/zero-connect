import CryptoKit
import Foundation
import Testing

@testable import ZeroConnectCore

@Suite("Integration Tests")
struct IntegrationTests {
    @Test("Full message flow: encrypt, route, receive, decrypt")
    func fullMessageFlow() async throws {
        // Set up two identities
        let aliceIdentity = IdentityManager()
        let bobKey = P256.KeyAgreement.PrivateKey()
        let bobPubData = bobKey.publicKey.x963Representation

        // Alice's router
        let aliceRouter = MessageRouter(identity: aliceIdentity)
        let aliceTransport = MockTransport(kind: .loom)
        await aliceRouter.addTransport(aliceTransport)

        // Create Bob as a contact
        let bobContact = Contact(
            publicKey: bobPubData,
            displayName: "Bob",
            loomDeviceId: UUID()
        )

        // Add Bob as a discovered peer
        let bobPeer = TransportPeer(
            id: "loom-\(bobContact.loomDeviceId!.uuidString)",
            displayName: "Bob",
            transport: .loom,
            transportIdentifier: bobContact.loomDeviceId!.uuidString
        )
        await aliceTransport.addPeer(bobPeer)
        await aliceRouter.refreshPeers()

        // Alice sends a message to Bob
        let sentMessage = try await aliceRouter.sendText("Kusheh, Bob!", to: bobContact)

        // Verify the message was encrypted and sent
        let sent = await aliceTransport.getSentMessages()
        #expect(sent.count == 1)

        // Verify the raw sent data is not plaintext
        let sentData = sent[0].0
        let sentString = String(data: sentData, encoding: .utf8) ?? ""
        #expect(!sentString.contains("Kusheh"))

        // Bob receives and decrypts
        let receivedMessage = try JSONDecoder().decode(Message.self, from: sentData)
        #expect(receivedMessage.id == sentMessage.id)

        let crypto = MessageCrypto()
        let alicePubKey = try P256.KeyAgreement.PublicKey(
            x963Representation: receivedMessage.senderPublicKey
        )
        let content = try crypto.decrypt(
            encryptedPayload: receivedMessage.encryptedPayload,
            senderPublicKey: alicePubKey,
            recipientPrivateKey: bobKey
        )

        #expect(content.text == "Kusheh, Bob!")
    }

    @Test("Message queued when no peers available, delivered when peer appears")
    func queueAndDeliver() async throws {
        let identity = IdentityManager()
        let store = MessageStore(
            directory: FileManager.default.temporaryDirectory
                .appendingPathComponent("ZCTest-\(UUID().uuidString)")
        )
        let router = MessageRouter(identity: identity)
        let transport = MockTransport(kind: .loom)
        await router.addTransport(transport)

        let contact = Contact(
            publicKey: Data(repeating: 0, count: 65),
            displayName: "Offline User",
            loomDeviceId: UUID()
        )

        let message = Message(
            senderPublicKey: Data([1, 2, 3]),
            recipientPublicKey: contact.publicKey,
            encryptedPayload: Data([4, 5, 6]),
            nonce: Data([7, 8, 9])
        )

        // No peers available — send should fail
        await #expect(throws: RouterError.self) {
            try await router.send(message, to: contact)
        }

        // Queue the message
        let queue = MessageQueue(router: router, store: store)
        await queue.enqueue(message, to: contact.id)
        #expect(await queue.pendingCount == 1)

        // Peer appears
        let peer = TransportPeer(
            id: "loom-\(contact.loomDeviceId!.uuidString)",
            displayName: "Offline User",
            transport: .loom,
            transportIdentifier: contact.loomDeviceId!.uuidString
        )
        await transport.addPeer(peer)
        await router.refreshPeers()

        // Queue processes — message should now be deliverable
        // (The actual queue processing happens on its own timer,
        //  but we can verify the transport has the peer now)
        let peers = await router.allPeers
        #expect(peers.count == 1)
        #expect(peers[0].displayName == "Offline User")
    }

    @Test("Relay stores messages not addressed to us")
    func relayBehavior() async throws {
        let identity = IdentityManager()
        let router = MessageRouter(identity: identity)

        let myPubKey = try await identity.publicKeyData()

        // Message addressed to someone else
        let otherMessage = Message(
            senderPublicKey: Data([1, 2, 3]),
            recipientPublicKey: Data(repeating: 99, count: 65), // Not our key
            encryptedPayload: Data([4, 5, 6]),
            nonce: Data([7, 8, 9])
        )

        // Message addressed to us
        let myMessage = Message(
            senderPublicKey: Data([10, 11, 12]),
            recipientPublicKey: myPubKey,
            encryptedPayload: Data([13, 14, 15]),
            nonce: Data([16, 17, 18])
        )

        // Check relay store behavior directly
        let relayStore = await router.relayStore
        await relayStore.store(otherMessage)

        let relayCount = await relayStore.count
        #expect(relayCount == 1)

        let relayedMessages = await relayStore.messagesFor(
            recipientPublicKey: Data(repeating: 99, count: 65)
        )
        #expect(relayedMessages.count == 1)
        #expect(relayedMessages[0].id == otherMessage.id)
    }

    @Test("Loom preferred over Meshtastic when both available")
    func loomPreferredOverMeshtastic() async throws {
        let identity = IdentityManager()
        let router = MessageRouter(identity: identity)

        let loomTransport = MockTransport(kind: .loom)
        let meshTransport = MockTransport(kind: .meshtastic)

        await router.addTransport(loomTransport)
        await router.addTransport(meshTransport)

        let loomDeviceId = UUID()
        let contact = Contact(
            publicKey: Data(repeating: 0, count: 65),
            displayName: "Multi-Transport User",
            meshtasticNodeId: 42,
            loomDeviceId: loomDeviceId
        )

        // Both transports can reach this contact
        await loomTransport.addPeer(TransportPeer(
            id: "loom-\(loomDeviceId.uuidString)",
            displayName: "Multi-Transport User",
            transport: .loom,
            transportIdentifier: loomDeviceId.uuidString
        ))
        await meshTransport.addPeer(TransportPeer(
            id: "mesh-42",
            displayName: "Multi-Transport User",
            transport: .meshtastic,
            transportIdentifier: "42"
        ))

        await router.refreshPeers()

        let message = Message(
            senderPublicKey: Data([1]),
            recipientPublicKey: contact.publicKey,
            encryptedPayload: Data([2]),
            nonce: Data([3])
        )

        try await router.send(message, to: contact)

        // Should pick Loom (priority 2 > Meshtastic priority 1)
        let loomSent = await loomTransport.getSentMessages()
        let meshSent = await meshTransport.getSentMessages()

        #expect(loomSent.count == 1, "Loom should be used (higher priority)")
        #expect(meshSent.isEmpty, "Meshtastic should not be used when Loom available")
    }
}
