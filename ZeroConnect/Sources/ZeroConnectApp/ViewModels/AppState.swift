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

    let identity: IdentityManager
    let router: MessageRouter

    private let loomTransport: LoomTransport
    private let meshtasticTransport: MeshtasticTransport

    init() {
        let identity = IdentityManager()
        self.identity = identity
        self.router = MessageRouter(identity: identity)
        self.loomTransport = LoomTransport()
        self.meshtasticTransport = MeshtasticTransport()

        Task { [router, loomTransport, meshtasticTransport] in
            await router.addTransport(loomTransport)
            await router.addTransport(meshtasticTransport)
        }

        Task {
            await setupMessageHandler()
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
    }

    func myQRString() async throws -> String {
        let pubKeyData = try await identity.publicKeyData()
        let deviceName = deviceName()
        let qr = QRCodeIdentity(publicKey: pubKeyData, displayName: deviceName)
        return try qr.encodeToString()
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
                    compactRepresentation: message.senderPublicKey
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
    }

    private func deviceName() -> String {
        #if os(iOS)
        UIDevice.current.name
        #else
        Host.current().localizedName ?? "Mac"
        #endif
    }
}
