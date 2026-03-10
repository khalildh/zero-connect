import Foundation
import Testing

@testable import ZeroConnectCore

@Suite("RelayStore Tests")
struct RelayTests {
    @Test("Store and retrieve relay messages by recipient")
    func storeAndRetrieve() async {
        let store = RelayStore()

        let msg1 = Message(
            senderPublicKey: Data([1]),
            recipientPublicKey: Data([10, 20, 30]),
            encryptedPayload: Data([100]),
            nonce: Data([200])
        )
        let msg2 = Message(
            senderPublicKey: Data([2]),
            recipientPublicKey: Data([40, 50, 60]),
            encryptedPayload: Data([101]),
            nonce: Data([201])
        )
        let msg3 = Message(
            senderPublicKey: Data([3]),
            recipientPublicKey: Data([10, 20, 30]), // Same recipient as msg1
            encryptedPayload: Data([102]),
            nonce: Data([202])
        )

        await store.store(msg1)
        await store.store(msg2)
        await store.store(msg3)

        let forRecipient1 = await store.messagesFor(recipientPublicKey: Data([10, 20, 30]))
        let forRecipient2 = await store.messagesFor(recipientPublicKey: Data([40, 50, 60]))
        let forUnknown = await store.messagesFor(recipientPublicKey: Data([99, 99, 99]))

        #expect(forRecipient1.count == 2)
        #expect(forRecipient2.count == 1)
        #expect(forUnknown.isEmpty)
    }

    @Test("Duplicate messages are not stored")
    func noDuplicates() async {
        let store = RelayStore()

        let msg = Message(
            senderPublicKey: Data([1]),
            recipientPublicKey: Data([2]),
            encryptedPayload: Data([3]),
            nonce: Data([4])
        )

        await store.store(msg)
        await store.store(msg) // Same message again

        let count = await store.count
        #expect(count == 1)
    }

    @Test("Mark delivered removes messages")
    func markDelivered() async {
        let store = RelayStore()

        let msg1 = Message(
            senderPublicKey: Data([1]),
            recipientPublicKey: Data([2]),
            encryptedPayload: Data([3]),
            nonce: Data([4])
        )
        let msg2 = Message(
            senderPublicKey: Data([5]),
            recipientPublicKey: Data([6]),
            encryptedPayload: Data([7]),
            nonce: Data([8])
        )

        await store.store(msg1)
        await store.store(msg2)
        #expect(await store.count == 2)

        await store.markDelivered(messageIds: [msg1.id])
        #expect(await store.count == 1)

        let remaining = await store.allRelayMessages
        #expect(remaining[0].message.id == msg2.id)
    }

    @Test("Capacity limit enforced")
    func capacityLimit() async {
        let store = RelayStore()

        // Store more than max (100) messages
        for i in 0..<105 {
            let msg = Message(
                senderPublicKey: Data([UInt8(i % 256)]),
                recipientPublicKey: Data([2]),
                encryptedPayload: Data([3]),
                nonce: Data([UInt8(i % 256)])
            )
            await store.store(msg)
        }

        let count = await store.count
        #expect(count <= 100)
    }

    @Test("Relay messages persist to disk and reload")
    func relayPersistence() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ZCTest-Relay-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let messageStore = MessageStore(directory: tempDir)

        // Store messages with persistence
        let relay1 = RelayStore(store: messageStore)
        let msg = Message(
            senderPublicKey: Data([1, 2, 3]),
            recipientPublicKey: Data([4, 5, 6]),
            encryptedPayload: Data([7, 8, 9]),
            nonce: Data([10, 11, 12])
        )
        await relay1.store(msg)
        #expect(await relay1.count == 1)

        // Allow persistence task to complete
        try await Task.sleep(for: .milliseconds(100))

        // Load into a new RelayStore — should recover the message
        let relay2 = RelayStore(store: messageStore)
        await relay2.loadFromDisk()

        let count = await relay2.count
        #expect(count == 1)

        let loaded = await relay2.allRelayMessages
        #expect(loaded[0].message.id == msg.id)
    }
}
