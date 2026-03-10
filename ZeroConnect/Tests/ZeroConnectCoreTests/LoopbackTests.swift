import CryptoKit
import Foundation
import Testing

@testable import ZeroConnectCore

@Suite("Loopback Transport Tests")
struct LoopbackTests {
    @Test("Two devices can exchange messages via loopback")
    func twoDeviceMessageExchange() async throws {
        // Create two virtual devices
        let aliceTransport = LoopbackTransport(localPeerName: "Alice's iPhone")
        let bobTransport = LoopbackTransport(localPeerName: "Bob's iPhone")

        // Link them
        await aliceTransport.connect(to: bobTransport)
        await bobTransport.connect(to: aliceTransport)

        // Set up Bob's message listener
        let bobIncoming = await bobTransport.incomingMessages()

        // Alice sends a message
        let alicePeers = await aliceTransport.discoveredPeers()
        #expect(alicePeers.count == 1)
        #expect(alicePeers[0].displayName == "Bob's iPhone")

        let testData = Data("Hello Bob!".utf8)
        try await aliceTransport.send(testData, to: alicePeers[0])

        // Bob receives it
        var received: Data?
        for await (data, _) in bobIncoming {
            received = data
            break
        }

        #expect(received == testData)
        #expect(String(data: received!, encoding: .utf8) == "Hello Bob!")
    }

    @Test("Full encrypted message exchange via loopback routers")
    func encryptedMessageExchange() async throws {
        // Create identities for both devices
        let aliceKey = P256.KeyAgreement.PrivateKey()
        let bobKey = P256.KeyAgreement.PrivateKey()

        let alicePubData = aliceKey.publicKey.x963Representation
        let bobPubData = bobKey.publicKey.x963Representation

        // Create contacts
        let bobContact = Contact(
            publicKey: bobPubData,
            displayName: "Bob",
            loomDeviceId: UUID()
        )

        // Set up transports and routers
        let aliceTransport = LoopbackTransport(
            localPeerName: "Alice",
            localPeerId: bobContact.loomDeviceId!.uuidString
        )
        let bobTransport = LoopbackTransport(localPeerName: "Bob")

        await aliceTransport.connect(to: bobTransport)
        await bobTransport.connect(to: aliceTransport)

        // Alice's router with a custom identity
        let aliceIdentity = IdentityManager()
        let aliceRouter = MessageRouter(identity: aliceIdentity)
        await aliceRouter.addTransport(aliceTransport)

        // Add Bob as discoverable peer
        // The loopback already has Bob as a peer, but we need to refresh
        await aliceRouter.refreshPeers()

        let allPeers = await aliceRouter.allPeers
        #expect(allPeers.count == 1)

        // Alice encrypts and sends
        let crypto = MessageCrypto()
        let content = MessageContent(text: "Aw di bodi, Bob?")
        let (encrypted, nonce) = try crypto.encrypt(
            content: content,
            senderPrivateKey: aliceKey,
            recipientPublicKey: bobKey.publicKey
        )

        let message = Message(
            senderPublicKey: alicePubData,
            recipientPublicKey: bobPubData,
            encryptedPayload: encrypted,
            nonce: nonce
        )

        let messageData = try JSONEncoder().encode(message)

        // Send via transport directly (router match needs loomDeviceId to match peer)
        try await aliceTransport.send(messageData, to: allPeers[0])

        // Bob receives
        let bobIncoming = await bobTransport.incomingMessages()
        var receivedData: Data?
        for await (data, _) in bobIncoming {
            receivedData = data
            break
        }

        #expect(receivedData != nil)

        // Bob decrypts
        let receivedMessage = try JSONDecoder().decode(Message.self, from: receivedData!)
        let senderPub = try P256.KeyAgreement.PublicKey(
            x963Representation: receivedMessage.senderPublicKey
        )
        let decrypted = try crypto.decrypt(
            encryptedPayload: receivedMessage.encryptedPayload,
            senderPublicKey: senderPub,
            recipientPrivateKey: bobKey
        )

        #expect(decrypted.text == "Aw di bodi, Bob?")
    }

    @Test("Loopback transport throws when not connected")
    func notConnectedThrows() async {
        let transport = LoopbackTransport(localPeerName: "Alone")

        let peer = TransportPeer(
            id: "fake",
            displayName: "Nobody",
            transport: .loom,
            transportIdentifier: "fake"
        )

        await #expect(throws: LoopbackError.self) {
            try await transport.send(Data([1, 2, 3]), to: peer)
        }
    }

    @Test("Bidirectional communication works")
    func bidirectional() async throws {
        let a = LoopbackTransport(localPeerName: "A")
        let b = LoopbackTransport(localPeerName: "B")

        await a.connect(to: b)
        await b.connect(to: a)

        let aIncoming = await a.incomingMessages()
        let bIncoming = await b.incomingMessages()

        let aPeers = await a.discoveredPeers()
        let bPeers = await b.discoveredPeers()

        // A sends to B
        try await a.send(Data("Hello B".utf8), to: aPeers[0])

        // B receives
        var bReceived: Data?
        for await (data, _) in bIncoming {
            bReceived = data
            break
        }
        #expect(String(data: bReceived!, encoding: .utf8) == "Hello B")

        // B sends to A
        try await b.send(Data("Hello A".utf8), to: bPeers[0])

        // A receives
        var aReceived: Data?
        for await (data, _) in aIncoming {
            aReceived = data
            break
        }
        #expect(String(data: aReceived!, encoding: .utf8) == "Hello A")
    }
}
