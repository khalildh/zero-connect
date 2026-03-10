import CryptoKit
import Foundation

/// Routes messages through the best available transport.
///
/// The router maintains all registered transports, discovers peers across
/// all of them, and selects the highest-priority transport that can reach
/// a given recipient. The user never thinks about transport.
///
/// Wire protocol:
/// - Loom/Server: JSON-encoded `TransportEnvelope`
/// - Meshtastic: `CompactMessage` binary encoding (saves ~45% vs JSON)
public actor MessageRouter {
    private var transports: [any Transport] = []
    private let crypto: MessageCrypto
    private let identity: IdentityManager
    public let relayStore: RelayStore
    private let fragmentCollector = FragmentCollector()

    /// All peers visible across all transports, deduplicated by public key when possible.
    public private(set) var allPeers: [TransportPeer] = []

    /// Whether this device should relay messages for others.
    public var relayEnabled = true

    public init(identity: IdentityManager, store: MessageStore? = nil) {
        self.identity = identity
        self.crypto = MessageCrypto()
        self.relayStore = RelayStore(store: store)
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
                let transportKind = await transport.kind
                let incoming = await transport.incomingMessages()
                for await (data, peer) in incoming {
                    await self.handleIncomingData(data, from: peer, transportKind: transportKind)
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
                        let wireData = try encodeForWire(
                            envelope: .message(relay.message),
                            transportKind: peer.transport
                        )
                        try await transport.send(wireData, to: peer)
                        delivered.append(relay.message.id)
                        break // Sent to one peer, move to next message
                    }
                } catch {
                    continue
                }
            }
        }

        if !delivered.isEmpty {
            await relayStore.markDelivered(messageIds: delivered)
        }
    }

    /// Send an encrypted message to a contact using the best available transport.
    public func send(
        _ message: Message,
        to contact: Contact
    ) async throws {
        let reachablePeers = findPeersForContact(contact)

        guard let bestPeer = reachablePeers
            .sorted(by: { $0.transport.priority > $1.transport.priority })
            .first
        else {
            throw RouterError.noTransportAvailable
        }

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

        let wireData = try encodeForWire(
            envelope: .message(message),
            transportKind: bestPeer.transport
        )

        // Fragment for bandwidth-constrained transports
        if bestPeer.transport.usesCompactEncoding {
            let fragments = MessageFragmenter.fragment(wireData, messageId: message.id)
            for fragment in fragments {
                try await transport.send(fragment, to: bestPeer)
            }
        } else {
            try await transport.send(wireData, to: bestPeer)
        }
    }

    /// Send a delivery receipt back to the sender.
    public func sendReceipt(
        _ receipt: DeliveryReceipt,
        to senderPublicKey: Data
    ) async {
        // Find a peer we can reach that has this public key
        // For now, broadcast the receipt — the sender will recognize their message ID
        let wireData: Data
        do {
            wireData = try JSONEncoder().encode(TransportEnvelope.receipt(receipt))
        } catch {
            print("[MessageRouter] Failed to encode receipt: \(error)")
            return
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
                    let peerWireData: Data
                    if peer.transport.usesCompactEncoding {
                        // Receipts are small enough for LoRa as JSON envelope
                        peerWireData = wireData
                    } else {
                        peerWireData = wireData
                    }
                    try await transport.send(peerWireData, to: peer)
                }
            } catch {
                continue
            }
        }
    }

    /// Create and send an encrypted text message to a contact.
    public func sendText(
        _ text: String,
        to contact: Contact
    ) async throws -> Message {
        let privateKey = try await identity.privateKey()
        let senderPubKeyData = try await identity.publicKeyData()

        let recipientPubKey = try PublicKeyUtils.decode(contact.publicKey)

        let content = MessageContent(text: text)
        let (encrypted, nonce) = try crypto.encrypt(
            content: content,
            senderPrivateKey: privateKey,
            recipientPublicKey: recipientPubKey
        )

        // Use compressed keys for compact encoding when going over Meshtastic
        let senderKeyForMessage: Data
        let reachablePeers = findPeersForContact(contact)
        let bestTransport = reachablePeers
            .sorted(by: { $0.transport.priority > $1.transport.priority })
            .first?.transport

        if bestTransport?.usesCompactEncoding == true {
            let senderPubKey = try PublicKeyUtils.decode(senderPubKeyData)
            senderKeyForMessage = PublicKeyUtils.encode(senderPubKey, format: .compressed)
        } else {
            senderKeyForMessage = senderPubKeyData
        }

        let message = Message(
            senderPublicKey: senderKeyForMessage,
            recipientPublicKey: contact.publicKey,
            encryptedPayload: encrypted,
            nonce: nonce
        )

        try await send(message, to: contact)
        return message
    }

    // MARK: - Callbacks

    /// Callback for incoming messages. Set by the app layer.
    public private(set) var onMessageReceived: (@Sendable (Message, TransportPeer) -> Void)?

    /// Callback for incoming delivery receipts.
    public private(set) var onReceiptReceived: (@Sendable (DeliveryReceipt) -> Void)?

    public func setMessageHandler(_ handler: @escaping @Sendable (Message, TransportPeer) -> Void) {
        onMessageReceived = handler
    }

    public func setReceiptHandler(_ handler: @escaping @Sendable (DeliveryReceipt) -> Void) {
        onReceiptReceived = handler
    }

    // MARK: - Wire Encoding

    /// Encode an envelope for the wire based on transport type.
    private func encodeForWire(envelope: TransportEnvelope, transportKind: TransportKind) throws -> Data {
        if transportKind.usesCompactEncoding {
            // Meshtastic: use compact binary for messages, JSON for receipts
            switch envelope {
            case .message(let message):
                return CompactMessage.encode(message)
            case .receipt:
                return try JSONEncoder().encode(envelope)
            }
        } else {
            return try JSONEncoder().encode(envelope)
        }
    }

    /// Decode incoming wire data based on the transport it came from.
    private func decodeFromWire(_ data: Data, transportKind: TransportKind) throws -> TransportEnvelope {
        if transportKind.usesCompactEncoding {
            // Try compact binary first (messages), fall back to JSON (receipts/envelopes)
            if let message = try? CompactMessage.decode(data) {
                return .message(message)
            }
            return try JSONDecoder().decode(TransportEnvelope.self, from: data)
        } else {
            // Try envelope format first, fall back to bare Message for backwards compatibility
            if let envelope = try? JSONDecoder().decode(TransportEnvelope.self, from: data) {
                return envelope
            }
            let message = try JSONDecoder().decode(Message.self, from: data)
            return .message(message)
        }
    }

    // MARK: - Incoming

    private func handleIncomingData(_ data: Data, from peer: TransportPeer, transportKind: TransportKind) async {
        // Check if this is a fragment that needs reassembly
        if transportKind.usesCompactEncoding, MessageFragmenter.isFragment(data) {
            if let reassembled = await fragmentCollector.addFragment(data) {
                await processDecodedData(reassembled, from: peer, transportKind: transportKind)
            }
            // Fragment collected but not yet complete — wait for more
            return
        }

        await processDecodedData(data, from: peer, transportKind: transportKind)
    }

    private func processDecodedData(_ data: Data, from peer: TransportPeer, transportKind: TransportKind) async {
        do {
            let envelope = try decodeFromWire(data, transportKind: transportKind)

            switch envelope {
            case .message(let message):
                await handleIncomingMessage(message, from: peer)
            case .receipt(let receipt):
                onReceiptReceived?(receipt)
            }
        } catch {
            print("[MessageRouter] Failed to decode from \(peer.displayName): \(error)")
        }
    }

    private func handleIncomingMessage(_ message: Message, from peer: TransportPeer) async {
        // Check if this message is for us
        let myPubKey = try? await identity.publicKeyData()
        if message.recipientPublicKey == myPubKey {
            onMessageReceived?(message, peer)

            // Send delivery receipt back
            let receipt = DeliveryReceipt(messageId: message.id, status: .delivered)
            await sendReceipt(receipt, to: message.senderPublicKey)
        } else if relayEnabled {
            // Not for us — store for relay
            await relayStore.store(message)
        }
    }

    private func findPeersForContact(_ contact: Contact) -> [TransportPeer] {
        allPeers.filter { peer in
            if let nodeId = contact.meshtasticNodeId,
               peer.transport == .meshtastic,
               peer.transportIdentifier == String(nodeId) {
                return true
            }
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
