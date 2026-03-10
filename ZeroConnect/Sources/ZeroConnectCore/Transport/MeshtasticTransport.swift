@preconcurrency import CoreBluetooth
import Foundation

/// Meshtastic BLE service and characteristic UUIDs.
enum MeshtasticBLE {
    nonisolated(unsafe) static let serviceUUID = CBUUID(string: "6BA1B218-15A8-461F-9FA8-5DCAE273EAFD")
    nonisolated(unsafe) static let toRadioUUID = CBUUID(string: "F75C76D2-129E-4DAD-A1DD-7866124401E7")
    nonisolated(unsafe) static let fromRadioUUID = CBUUID(string: "2C55E69E-4993-11ED-B878-0242AC120002")
    nonisolated(unsafe) static let fromNumUUID = CBUUID(string: "ED9DA18C-A800-4F66-A670-AA7547E34453")
    nonisolated(unsafe) static let logRadioUUID = CBUUID(string: "5A3D6E49-06E6-4423-9944-E9DE8CDF9547")
}

/// Transport layer for communicating with Meshtastic nodes over BLE.
/// Discovers nearby Meshtastic hardware, connects, and sends/receives
/// protobuf messages that travel over the LoRa mesh.
public actor MeshtasticTransport: Transport {
    public let kind: TransportKind = .meshtastic

    private let bleDelegate: MeshtasticBLEDelegate
    private var messageContinuation: AsyncStream<(Data, TransportPeer)>.Continuation?
    private var messageStream: AsyncStream<(Data, TransportPeer)>?
    private var isDiscovering = false

    public var isAvailable: Bool {
        bleDelegate.centralState == .poweredOn
    }

    public init() {
        self.bleDelegate = MeshtasticBLEDelegate()

        let (stream, continuation) = AsyncStream<(Data, TransportPeer)>.makeStream()
        self.messageStream = stream
        self.messageContinuation = continuation

        bleDelegate.onMessageReceived = { [weak self] data, peer in
            guard let self else { return }
            Task { await self.handleIncoming(data, from: peer) }
        }
    }

    public func startDiscovery() async throws {
        guard !isDiscovering else { return }
        isDiscovering = true
        bleDelegate.startScanning()
    }

    public func stopDiscovery() async {
        isDiscovering = false
        bleDelegate.stopScanning()
    }

    public func discoveredPeers() async -> [TransportPeer] {
        bleDelegate.discoveredNodes.map { node in
            TransportPeer(
                id: "mesh-\(node.id)",
                displayName: node.name,
                transport: .meshtastic,
                transportIdentifier: node.id,
                rssi: node.rssi
            )
        }
    }

    public func send(_ data: Data, to peer: TransportPeer) async throws {
        try bleDelegate.send(data, toNodeId: peer.transportIdentifier)
    }

    public func incomingMessages() async -> AsyncStream<(Data, TransportPeer)> {
        messageStream ?? AsyncStream { $0.finish() }
    }

    private func handleIncoming(_ data: Data, from peer: TransportPeer) {
        messageContinuation?.yield((data, peer))
    }
}

// MARK: - BLE Delegate

/// Discovered Meshtastic node info.
struct MeshtasticNode: @unchecked Sendable {
    let id: String
    let name: String
    let peripheral: CBPeripheral
    var rssi: Int
}

/// CoreBluetooth delegate that handles Meshtastic BLE communication.
/// Manages scanning, connecting, characteristic discovery, and data transfer.
final class MeshtasticBLEDelegate: NSObject, @unchecked Sendable {
    private var centralManager: CBCentralManager!
    private(set) var discoveredNodes: [MeshtasticNode] = []
    private var connectedPeripherals: [String: CBPeripheral] = [:]
    private var toRadioCharacteristics: [String: CBCharacteristic] = [:]
    private var fromRadioCharacteristics: [String: CBCharacteristic] = [:]

    var centralState: CBManagerState { centralManager.state }
    var onMessageReceived: (@Sendable (Data, TransportPeer) -> Void)?

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    func startScanning() {
        guard centralManager.state == .poweredOn else { return }
        centralManager.scanForPeripherals(
            withServices: [MeshtasticBLE.serviceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
    }

    func stopScanning() {
        centralManager.stopScan()
    }

    func send(_ data: Data, toNodeId nodeId: String) throws {
        guard let peripheral = connectedPeripherals[nodeId],
              let characteristic = toRadioCharacteristics[nodeId] else {
            throw MeshtasticTransportError.nodeNotConnected
        }

        // Meshtastic expects data written to TORADIO characteristic
        let writeType: CBCharacteristicWriteType =
            characteristic.properties.contains(.writeWithoutResponse)
            ? .withoutResponse
            : .withResponse

        peripheral.writeValue(data, for: characteristic, type: writeType)
    }

    private func connectToNode(_ peripheral: CBPeripheral) {
        peripheral.delegate = self
        centralManager.connect(peripheral, options: nil)
    }

    /// Read all pending packets from FROMRADIO by draining.
    private func drainFromRadio(peripheral: CBPeripheral) {
        let nodeId = peripheral.identifier.uuidString
        guard let characteristic = fromRadioCharacteristics[nodeId] else { return }
        peripheral.readValue(for: characteristic)
    }
}

// MARK: - CBCentralManagerDelegate

extension MeshtasticBLEDelegate: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            startScanning()
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let id = peripheral.identifier.uuidString

        // Skip if already discovered
        if discoveredNodes.contains(where: { $0.id == id }) {
            // Update RSSI
            if let idx = discoveredNodes.firstIndex(where: { $0.id == id }) {
                discoveredNodes[idx].rssi = RSSI.intValue
            }
            return
        }

        let node = MeshtasticNode(
            id: id,
            name: peripheral.name ?? "Meshtastic \(id.prefix(4))",
            peripheral: peripheral,
            rssi: RSSI.intValue
        )

        discoveredNodes.append(node)
        connectToNode(peripheral)
    }

    func centralManager(
        _ central: CBCentralManager,
        didConnect peripheral: CBPeripheral
    ) {
        let id = peripheral.identifier.uuidString
        connectedPeripherals[id] = peripheral
        peripheral.discoverServices([MeshtasticBLE.serviceUUID])
    }

    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        let id = peripheral.identifier.uuidString
        connectedPeripherals.removeValue(forKey: id)
        toRadioCharacteristics.removeValue(forKey: id)
        fromRadioCharacteristics.removeValue(forKey: id)

        // Auto-reconnect after delay
        let peripheralRef = peripheral
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.connectToNode(peripheralRef)
        }
    }
}

// MARK: - CBPeripheralDelegate

extension MeshtasticBLEDelegate: CBPeripheralDelegate {
    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverServices error: Error?
    ) {
        guard let services = peripheral.services else { return }
        for service in services where service.uuid == MeshtasticBLE.serviceUUID {
            peripheral.discoverCharacteristics(
                [
                    MeshtasticBLE.toRadioUUID,
                    MeshtasticBLE.fromRadioUUID,
                    MeshtasticBLE.fromNumUUID,
                ],
                for: service
            )
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        guard let characteristics = service.characteristics else { return }
        let id = peripheral.identifier.uuidString

        for characteristic in characteristics {
            switch characteristic.uuid {
            case MeshtasticBLE.toRadioUUID:
                toRadioCharacteristics[id] = characteristic
            case MeshtasticBLE.fromRadioUUID:
                fromRadioCharacteristics[id] = characteristic
            case MeshtasticBLE.fromNumUUID:
                // Subscribe to notifications — triggers packet drain
                peripheral.setNotifyValue(true, for: characteristic)
            default:
                break
            }
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        let id = peripheral.identifier.uuidString

        switch characteristic.uuid {
        case MeshtasticBLE.fromNumUUID:
            // FROMNUM notification means packets are pending — drain them
            drainFromRadio(peripheral: peripheral)

        case MeshtasticBLE.fromRadioUUID:
            guard let data = characteristic.value, !data.isEmpty else { return }

            let peer = TransportPeer(
                id: "mesh-\(id)",
                displayName: discoveredNodes.first(where: { $0.id == id })?.name ?? "Unknown",
                transport: .meshtastic,
                transportIdentifier: id
            )

            onMessageReceived?(data, peer)

            // Continue draining
            drainFromRadio(peripheral: peripheral)

        default:
            break
        }
    }
}

public enum MeshtasticTransportError: Error, Sendable {
    case nodeNotConnected
    case writeError
    case notAvailable
}
