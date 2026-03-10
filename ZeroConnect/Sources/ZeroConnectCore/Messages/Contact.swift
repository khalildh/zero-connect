import Foundation

/// A contact whose public key was exchanged via QR code.
public struct Contact: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let publicKey: Data
    public var displayName: String
    public let dateAdded: Date
    /// Meshtastic node ID if known (linked when seen on both networks)
    public var meshtasticNodeId: UInt32?
    /// Loom device ID if known
    public var loomDeviceId: UUID?

    public init(
        id: UUID = UUID(),
        publicKey: Data,
        displayName: String,
        dateAdded: Date = Date(),
        meshtasticNodeId: UInt32? = nil,
        loomDeviceId: UUID? = nil
    ) {
        self.id = id
        self.publicKey = publicKey
        self.displayName = displayName
        self.dateAdded = dateAdded
        self.meshtasticNodeId = meshtasticNodeId
        self.loomDeviceId = loomDeviceId
    }
}
