import Foundation

/// Transport layer for communicating via a lightweight message buffer server.
///
/// The server is a "dumb mailbox" — it stores opaque encrypted blobs it cannot read.
/// Messages are fetched by the recipient when they come online. The server never
/// sees plaintext, never authenticates users by identity, and is replaceable.
///
/// Stage 1: Stub implementation. Stores messages locally as a simulation.
/// Stage 2: HTTP/WebSocket client to a real server endpoint.
public actor ServerTransport: Transport {
    public let kind: TransportKind = .server

    private var serverURL: URL?
    private var messageContinuation: AsyncStream<(Data, TransportPeer)>.Continuation?
    private var messageStream: AsyncStream<(Data, TransportPeer)>?
    private var isDiscoveringFlag = false

    // In Stage 1, the server is simulated — messages are queued locally
    private var outbox: [(Data, String)] = [] // (data, recipientPublicKeyHex)

    public var isAvailable: Bool {
        serverURL != nil
    }

    public init(serverURL: URL? = nil) {
        self.serverURL = serverURL

        let (stream, continuation) = AsyncStream<(Data, TransportPeer)>.makeStream()
        self.messageStream = stream
        self.messageContinuation = continuation
    }

    public func configure(url: URL) {
        self.serverURL = url
    }

    public func startDiscovery() async throws {
        // Server transport doesn't discover peers — it sends to known public keys.
        // In a real implementation, this would establish a WebSocket connection
        // and start polling for new messages.
        isDiscoveringFlag = true
    }

    public func stopDiscovery() async {
        isDiscoveringFlag = false
    }

    public func discoveredPeers() async -> [TransportPeer] {
        // Server transport doesn't discover peers dynamically.
        // Any contact with a known public key is reachable via server.
        []
    }

    public func send(_ data: Data, to peer: TransportPeer) async throws {
        guard serverURL != nil else {
            throw ServerTransportError.notConfigured
        }

        // Stage 2: POST the encrypted blob to the server
        // POST /messages { recipient: <pubkey>, payload: <encrypted blob> }
        //
        // For now, just queue it locally
        outbox.append((data, peer.transportIdentifier))
        print("[ServerTransport] Queued message for server delivery (stub)")
    }

    public func incomingMessages() async -> AsyncStream<(Data, TransportPeer)> {
        messageStream ?? AsyncStream { $0.finish() }
    }

    /// Returns queued messages that haven't been sent to the server yet.
    public func pendingMessages() -> [(Data, String)] {
        outbox
    }

    /// Clears sent messages from the outbox.
    public func clearSent(count: Int) {
        outbox.removeFirst(min(count, outbox.count))
    }
}

public enum ServerTransportError: Error, Sendable {
    case notConfigured
    case serverUnreachable
    case uploadFailed(statusCode: Int)
}
