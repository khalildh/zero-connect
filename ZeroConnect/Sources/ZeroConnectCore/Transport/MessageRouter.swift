import CryptoKit
import Foundation

/// Routes messages through the best available transport.
///
/// The router maintains all registered transports, discovers peers across
/// all of them, and selects the highest-priority transport that can reach
/// a given recipient. The user never thinks about transport.
public actor MessageRouter {
    private var transports: [any Transport] = []
    private let crypto: MessageCrypto
    private let identity: IdentityManager
    public let relayStore = RelayStore()

    /// All peers visible across all transports, deduplicated by public key when possible.
    public private(set) var allPeers: [TransportPeer] = []

    /// Whether this device should relay messages for others.
    public var relayEnabled = true

    public init(identity: IdentityManager) {
        self.identity = identity
        self.crypto = MessageCrypto()
    }

    /// Register a transport. Call before starting discovery.
    public func addTransport(_ transport: any Transport) {
        transports.append(transport)
    }

    /// Start discovery on all transports.
    public func startAllDiscovery() async {
        for transport in transports {
            do {
                try await transport.startDiscovery()
            } catch {
                print("[MessageRouter] Failed to start \(await transport.kind) discovery: \(error)")
            }
        }

        // Start listening for incoming messages on all transports
        for transport in transports {
            Task { [weak self] in
                guard let self else { return }
                let incoming = await transport.incomingMessages()
                for await (data, peer) in incoming {
                    await self.handleIncomingData(data, from: peer)
                }
            }
        }
    }

    /// Stop all discovery.
    public func stopAllDiscovery() async {
        for transport in transports {
            await transport.stopDiscovery()
        }
    }

    /// Refresh the peer list from all transports and attempt relay delivery.
    public func refreshPeers() async {
        var combined: [TransportPeer] = []
        for transport in transports {
            let peers = await transport.discoveredPeers()
            combined.append(contentsOf: peers)
        }
        allPeers = combined

        // Attempt to forward relay messages to newly-visible peers
        if relayEnabled {
            await attemptRelayDelivery()
        }
    }

    /// Try to deliver relay messages to peers that are currently visible.
    private func attemptRelayDelivery() async {
        let relayMessages = await relayStore.allRelayMessages
        guard !relayMessages.isEmpty, !allPeers.isEmpty else { return }

        var delivered: [UUID] = []

        for relay in relayMessages {
            // Try to send to any peer — in a real implementation we'd match
            // by public key, but for now broadcast to all peers and let them
            // decide if it's for them
            let messageData: Data
            do {
                messageData = try JSONEncoder().encode(relay.message)
            } catch {
                continue
            }

            for peer in allPeers {
                do {
                    var matchedTransport: (any Transport)?
                    for transport in transports {
                        if await transport.kind == peer.transport {
                            matchedTransport = transport
                            break
                        }
                    }
                    if let transport = matchedTransport {
                        try await transport.send(messageData, to: peer)
                        delivered.append(relay.message.id)
                        break // Sent to one peer, move to next message
                    }
                } catch {
                    // Peer unreachable, try next
                    continue
                }
            }
        }

        if !delivered.isEmpty {
            await relayStore.markDelivered(messageIds: delivered)
        }
    }

    /// Send an encrypted message to a contact using the best available transport.
    ///
    /// The router:
    /// 1. Finds all transports that can reach this contact
    /// 2. Picks the highest-priority one
    /// 3. Serializes and sends the encrypted message
    public func send(
        _ message: Message,
        to contact: Contact
    ) async throws {
        let messageData = try JSONEncoder().encode(message)

        // Find peers that match this contact
        let reachablePeers = findPeersForContact(contact)

        guard let bestPeer = reachablePeers
            .sorted(by: { $0.transport.priority > $1.transport.priority })
            .first
        else {
            throw RouterError.noTransportAvailable
        }

        // Find the transport that owns this peer
        var matchedTransport: (any Transport)?
        for transport in transports {
            if await transport.kind == bestPeer.transport {
                matchedTransport = transport
                break
            }
        }

        guard let transport = matchedTransport else {
            throw RouterError.noTransportAvailable
        }

        try await transport.send(messageData, to: bestPeer)
    }

    /// Create and send an encrypted text message to a contact.
    public func sendText(
        _ text: String,
        to contact: Contact
    ) async throws -> Message {
        let privateKey = try await identity.privateKey()
        let senderPubKeyData = try await identity.publicKeyData()

        let recipientPubKey = try P256.KeyAgreement.PublicKey(
            x963Representation: contact.publicKey
        )

        let content = MessageContent(text: text)
        let (encrypted, nonce) = try crypto.encrypt(
            content: content,
            senderPrivateKey: privateKey,
            recipientPublicKey: recipientPubKey
        )

        let message = Message(
            senderPublicKey: senderPubKeyData,
            recipientPublicKey: contact.publicKey,
            encryptedPayload: encrypted,
            nonce: nonce
        )

        try await send(message, to: contact)
        return message
    }

    // MARK: - Private

    /// Callback for incoming messages. Set by the app layer.
    public private(set) var onMessageReceived: (@Sendable (Message, TransportPeer) -> Void)?

    public func setMessageHandler(_ handler: @escaping @Sendable (Message, TransportPeer) -> Void) {
        onMessageReceived = handler
    }

    private func handleIncomingData(_ data: Data, from peer: TransportPeer) async {
        do {
            let message = try JSONDecoder().decode(Message.self, from: data)

            // Check if this message is for us
            let myPubKey = try? await identity.publicKeyData()
            if message.recipientPublicKey == myPubKey {
                onMessageReceived?(message, peer)
            } else if relayEnabled {
                // Not for us — store for relay
                await relayStore.store(message)
            }
        } catch {
            print("[MessageRouter] Failed to decode message from \(peer.displayName): \(error)")
        }
    }

    private func findPeersForContact(_ contact: Contact) -> [TransportPeer] {
        allPeers.filter { peer in
            // Match by Meshtastic node ID
            if let nodeId = contact.meshtasticNodeId,
               peer.transport == .meshtastic,
               peer.transportIdentifier == String(nodeId) {
                return true
            }
            // Match by Loom device ID
            if let loomId = contact.loomDeviceId,
               peer.transport == .loom,
               peer.transportIdentifier == loomId.uuidString {
                return true
            }
            return false
        }
    }
}

public enum RouterError: Error, Sendable {
    case noTransportAvailable
    case contactNotReachable
}
