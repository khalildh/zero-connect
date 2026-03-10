import Foundation
import Loom
import Network

/// Bridges @MainActor-bound Loom objects so they can be used from the LoomTransport actor.
@MainActor
final class LoomBridge: Sendable {
    private var node: LoomNode?
    private var discovery: LoomDiscovery?

    nonisolated init() {}

    func setup(
        serviceType: String,
        onMessage: @escaping @Sendable (Data, TransportPeer) -> Void
    ) throws {
        let config = LoomNetworkConfiguration(serviceType: serviceType, enablePeerToPeer: true)
        let node = LoomNode(configuration: config)
        self.node = node

        let discovery = node.makeDiscovery()
        discovery.enablePeerToPeer = true
        self.discovery = discovery
    }

    func startDiscovery() {
        discovery?.startDiscovery()
    }

    func stopDiscovery() async {
        discovery?.stopDiscovery()
        await node?.stopAdvertising()
    }

    func startAdvertising(
        onMessage: @escaping @Sendable (Data, TransportPeer) -> Void
    ) async throws {
        guard let node else { return }

        let deviceName = Self.currentDeviceName()
        let helloReq = LoomSessionHelloRequest(
            deviceID: UUID(),
            deviceName: deviceName,
            deviceType: Self.currentDeviceType(),
            advertisement: LoomPeerAdvertisement()
        )

        _ = try await node.startAuthenticatedAdvertising(
            serviceName: deviceName,
            helloProvider: { helloReq },
            onSession: { session in
                Task {
                    for await stream in session.incomingStreams {
                        var messageData = Data()
                        for await chunk in stream.incomingBytes {
                            messageData.append(chunk)
                        }
                        if !messageData.isEmpty {
                            let peer = TransportPeer(
                                id: "loom-incoming-\(UUID().uuidString)",
                                displayName: "Loom Peer",
                                transport: .loom,
                                transportIdentifier: ""
                            )
                            onMessage(messageData, peer)
                        }
                    }
                }
            }
        )
    }

    func currentPeers() -> [LoomPeer] {
        discovery?.discoveredPeers ?? []
    }

    func connect(
        toEndpoint endpoint: NWEndpoint
    ) async throws -> LoomAuthenticatedSession {
        guard let node else { throw LoomTransportError.peerNotFound }

        let helloReq = LoomSessionHelloRequest(
            deviceID: UUID(),
            deviceName: Self.currentDeviceName(),
            deviceType: Self.currentDeviceType(),
            advertisement: LoomPeerAdvertisement()
        )

        return try await node.connect(
            to: endpoint,
            using: .tcp,
            hello: helloReq,
            queue: .main
        )
    }

    func findPeerEndpoint(transportIdentifier: String) -> NWEndpoint? {
        discovery?.discoveredPeers
            .first(where: { $0.id.uuidString == transportIdentifier })?
            .endpoint
    }

    static func currentDeviceName() -> String {
        #if os(iOS)
        UIDevice.current.name
        #else
        Host.current().localizedName ?? "Mac"
        #endif
    }

    static func currentDeviceType() -> DeviceType {
        #if os(iOS)
        .iPhone
        #else
        .mac
        #endif
    }
}

/// Transport layer using Loom for local peer discovery and communication
/// over Wi-Fi (same network) and AWDL (peer-to-peer, no router needed).
public actor LoomTransport: Transport {
    public let kind: TransportKind = .loom

    private let serviceType: String
    private let bridge = LoomBridge()
    private var peers: [TransportPeer] = []
    private var activeSessions: [String: LoomAuthenticatedSession] = [:]
    private var messageContinuation: AsyncStream<(Data, TransportPeer)>.Continuation?
    private var messageStream: AsyncStream<(Data, TransportPeer)>?
    private var isDiscoveringFlag = false

    public var isAvailable: Bool { true }

    public init(serviceType: String = "_zeroconnect._tcp") {
        self.serviceType = serviceType

        let (stream, continuation) = AsyncStream<(Data, TransportPeer)>.makeStream()
        self.messageStream = stream
        self.messageContinuation = continuation
    }

    public func startDiscovery() async throws {
        guard !isDiscoveringFlag else { return }
        isDiscoveringFlag = true

        let svcType = serviceType
        let cont = messageContinuation

        await MainActor.run {
            try! bridge.setup(serviceType: svcType, onMessage: { data, peer in
                cont?.yield((data, peer))
            })
            bridge.startDiscovery()
        }

        try await bridge.startAdvertising(onMessage: { data, peer in
            cont?.yield((data, peer))
        })

        // Periodically refresh peers
        Task { [weak self] in
            guard let self else { return }
            while await self.isDiscoveringFlag {
                await self.refreshPeers()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    public func stopDiscovery() async {
        isDiscoveringFlag = false
        await bridge.stopDiscovery()
    }

    public func discoveredPeers() async -> [TransportPeer] {
        peers
    }

    public func send(_ data: Data, to peer: TransportPeer) async throws {
        // Reuse existing session if available
        if let session = activeSessions[peer.id] {
            let stream = try await session.openStream(label: "msg")
            try await stream.send(data)
            try await stream.close()
            return
        }

        // Find the Loom peer endpoint and connect
        let transportId = peer.transportIdentifier
        guard let endpoint = await MainActor.run(body: {
            bridge.findPeerEndpoint(transportIdentifier: transportId)
        }) else {
            throw LoomTransportError.peerNotFound
        }

        let session = try await bridge.connect(toEndpoint: endpoint)

        activeSessions[peer.id] = session

        let sendStream = try await session.openStream(label: "msg")
        try await sendStream.send(data)
        try await sendStream.close()

        // Listen for incoming on this session
        let cont = messageContinuation
        Task {
            for await stream in session.incomingStreams {
                var messageData = Data()
                for await chunk in stream.incomingBytes {
                    messageData.append(chunk)
                }
                if !messageData.isEmpty {
                    cont?.yield((messageData, peer))
                }
            }
        }
    }

    public func incomingMessages() async -> AsyncStream<(Data, TransportPeer)> {
        messageStream ?? AsyncStream { $0.finish() }
    }

    // MARK: - Private

    private func refreshPeers() async {
        let loomPeers: [LoomPeer] = await MainActor.run {
            bridge.currentPeers()
        }

        peers = loomPeers.map { loomPeer in
            TransportPeer(
                id: "loom-\(loomPeer.id.uuidString)",
                displayName: loomPeer.name,
                transport: .loom,
                transportIdentifier: loomPeer.id.uuidString
            )
        }
    }
}

public enum LoomTransportError: Error, Sendable {
    case peerNotFound
    case connectionFailed
}
