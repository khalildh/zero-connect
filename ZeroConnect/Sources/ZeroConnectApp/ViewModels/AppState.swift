import CryptoKit
import Foundation
import SwiftUI
import ZeroConnectCore

/// Main app state that coordinates the transport layer and UI.
@MainActor
final class AppState: ObservableObject {
    @Published var contacts: [Contact] = []
    @Published var conversations: [UUID: [StoredMessage]] = [:] // keyed by contact ID
    @Published var nearbyPeers: [TransportPeer] = []
    @Published var isDiscovering = false
    @Published var pendingQueueCount = 0

    let identity: IdentityManager
    let router: MessageRouter
    let store: MessageStore
    private let messageQueue: MessageQueue

    private let loomTransport: LoomTransport
    private let meshtasticTransport: MeshtasticTransport

    var displayName: String {
        deviceName()
    }

    init() {
        let identity = IdentityManager()
        let store = MessageStore()
        let router = MessageRouter(identity: identity)

        self.identity = identity
        self.store = store
        self.router = router
        self.messageQueue = MessageQueue(router: router, store: store)
        self.loomTransport = LoomTransport()
        self.meshtasticTransport = MeshtasticTransport()

        Task { [router, loomTransport, meshtasticTransport] in
            await router.addTransport(loomTransport)
            await router.addTransport(meshtasticTransport)
        }

        Task {
            await setupMessageHandler()
            await loadPersistedData()
            await messageQueue.start()
        }
    }

    // MARK: - Discovery

    func startDiscovery() async {
        isDiscovering = true
        await router.startAllDiscovery()

        // Periodically refresh peers
        Task {
            while isDiscovering {
                await router.refreshPeers()
                nearbyPeers = await router.allPeers
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    func stopDiscovery() async {
        isDiscovering = false
        await router.stopAllDiscovery()
    }

    // MARK: - Messaging

    func sendMessage(text: String, to contact: Contact) async {
        do {
            let message = try await router.sendText(text, to: contact)
            let stored = StoredMessage(
                message: message,
                deliveryState: .queued,
                direction: .sent,
                decryptedText: text
            )
            appendMessage(stored, for: contact.id)
        } catch {
            print("[AppState] Failed to send: \(error)")
        }
    }

    // MARK: - Contacts

    func addContact(from qrString: String) throws {
        let qrIdentity = try QRCodeIdentity.decode(from: qrString)
        let contact = qrIdentity.toContact()

        guard !contacts.contains(where: { $0.publicKey == contact.publicKey }) else {
            return // Already have this contact
        }

        contacts.append(contact)
        persistContacts()
    }

    func myQRString() async throws -> String {
        let pubKeyData = try await identity.publicKeyData()
        let deviceName = deviceName()
        let qr = QRCodeIdentity(publicKey: pubKeyData, displayName: deviceName)
        return try qr.encodeToString()
    }

    // MARK: - Persistence

    private func loadPersistedData() async {
        do {
            let loadedContacts = try await store.loadContacts()
            contacts = loadedContacts
            let contactIds = loadedContacts.map(\.id)
            conversations = try await store.loadAllConversations(contactIds: contactIds)
        } catch {
            print("[AppState] Failed to load persisted data: \(error)")
        }
    }

    private func persistContacts() {
        Task {
            do {
                try await store.saveContacts(contacts)
            } catch {
                print("[AppState] Failed to save contacts: \(error)")
            }
        }
    }

    private func persistMessages(for contactId: UUID) {
        guard let messages = conversations[contactId] else { return }
        Task {
            do {
                try await store.saveMessages(messages, for: contactId)
            } catch {
                print("[AppState] Failed to save messages: \(error)")
            }
        }
    }

    // MARK: - Private

    private func setupMessageHandler() async {
        await router.setMessageHandler { [weak self] message, peer in
            Task { @MainActor in
                self?.handleReceivedMessage(message, from: peer)
            }
        }
    }

    private func handleReceivedMessage(_ message: Message, from peer: TransportPeer) {
        // Find the contact by sender public key
        guard let contact = contacts.first(where: { $0.publicKey == message.senderPublicKey }) else {
            print("[AppState] Received message from unknown sender")
            return
        }

        // Decrypt and store
        Task {
            var decryptedText: String?
            do {
                let privateKey = try await identity.privateKey()
                let senderPubKey = try P256.KeyAgreement.PublicKey(
                    x963Representation: message.senderPublicKey
                )
                let crypto = MessageCrypto()
                let content = try crypto.decrypt(
                    encryptedPayload: message.encryptedPayload,
                    senderPublicKey: senderPubKey,
                    recipientPrivateKey: privateKey
                )
                decryptedText = content.text
            } catch {
                print("[AppState] Failed to decrypt: \(error)")
            }

            await MainActor.run {
                let stored = StoredMessage(
                    message: message,
                    deliveryState: .delivered,
                    direction: .received,
                    decryptedText: decryptedText
                )
                appendMessage(stored, for: contact.id)
            }
        }
    }

    private func appendMessage(_ stored: StoredMessage, for contactId: UUID) {
        if conversations[contactId] == nil {
            conversations[contactId] = []
        }
        conversations[contactId]?.append(stored)
        persistMessages(for: contactId)
    }

    private func deviceName() -> String {
        #if os(iOS)
        UIDevice.current.name
        #else
        Host.current().localizedName ?? "Mac"
        #endif
    }
}
