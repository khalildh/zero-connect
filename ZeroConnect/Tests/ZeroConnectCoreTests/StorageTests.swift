import Foundation
import Testing

@testable import ZeroConnectCore

@Suite("MessageStore Tests")
struct StorageTests {
    func makeTemporaryStore() -> MessageStore {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ZeroConnectTests-\(UUID().uuidString)", isDirectory: true)
        return MessageStore(directory: dir)
    }

    @Test("Save and load contacts round-trip")
    func contactPersistence() async throws {
        let store = makeTemporaryStore()

        let contacts = [
            Contact(publicKey: Data([1, 2, 3]), displayName: "Ibrahim"),
            Contact(publicKey: Data([4, 5, 6]), displayName: "Fatmata"),
        ]

        try await store.saveContacts(contacts)
        let loaded = try await store.loadContacts()

        #expect(loaded.count == 2)
        #expect(loaded[0].displayName == "Ibrahim")
        #expect(loaded[1].displayName == "Fatmata")
    }

    @Test("Load contacts from empty store returns empty array")
    func emptyContactStore() async throws {
        let store = makeTemporaryStore()
        let loaded = try await store.loadContacts()
        #expect(loaded.isEmpty)
    }

    @Test("Save and load messages for a contact")
    func messagePersistence() async throws {
        let store = makeTemporaryStore()
        let contactId = UUID()

        let messages = [
            StoredMessage(
                message: Message(
                    senderPublicKey: Data([1]),
                    recipientPublicKey: Data([2]),
                    encryptedPayload: Data([3]),
                    nonce: Data([4])
                ),
                deliveryState: .delivered,
                direction: .received,
                decryptedText: "Aw di bodi?"
            ),
            StoredMessage(
                message: Message(
                    senderPublicKey: Data([2]),
                    recipientPublicKey: Data([1]),
                    encryptedPayload: Data([5]),
                    nonce: Data([6])
                ),
                deliveryState: .queued,
                direction: .sent,
                decryptedText: "A de ya, tenki"
            ),
        ]

        try await store.saveMessages(messages, for: contactId)
        let loaded = try await store.loadMessages(for: contactId)

        #expect(loaded.count == 2)
        #expect(loaded[0].decryptedText == "Aw di bodi?")
        #expect(loaded[1].decryptedText == "A de ya, tenki")
        #expect(loaded[0].deliveryState == .delivered)
        #expect(loaded[1].direction == .sent)
    }

    @Test("Load all conversations for multiple contacts")
    func allConversations() async throws {
        let store = makeTemporaryStore()
        let id1 = UUID()
        let id2 = UUID()

        let msg1 = StoredMessage(
            message: Message(
                senderPublicKey: Data(), recipientPublicKey: Data(),
                encryptedPayload: Data(), nonce: Data()
            ),
            deliveryState: .delivered, direction: .received, decryptedText: "Hello"
        )
        let msg2 = StoredMessage(
            message: Message(
                senderPublicKey: Data(), recipientPublicKey: Data(),
                encryptedPayload: Data(), nonce: Data()
            ),
            deliveryState: .queued, direction: .sent, decryptedText: "Hi"
        )

        try await store.saveMessages([msg1], for: id1)
        try await store.saveMessages([msg2], for: id2)

        let all = try await store.loadAllConversations(contactIds: [id1, id2])
        #expect(all.count == 2)
        #expect(all[id1]?.count == 1)
        #expect(all[id2]?.count == 1)
    }

    @Test("Queued messages persist and reload")
    func queuedMessagePersistence() async throws {
        let store = makeTemporaryStore()

        let msg = Message(
            senderPublicKey: Data([1]),
            recipientPublicKey: Data([2]),
            encryptedPayload: Data([3]),
            nonce: Data([4])
        )
        let queued = QueuedMessage(message: msg, recipientContactId: UUID())

        try await store.saveQueuedMessages([queued])
        let loaded = try await store.loadQueuedMessages()

        #expect(loaded.count == 1)
        #expect(loaded[0].retryCount == 0)
        #expect(loaded[0].message.id == msg.id)
    }
}
