import Foundation

/// Persists messages and contacts to disk using JSON files.
/// Simple file-based storage suitable for Stage 1 PoC.
public actor MessageStore {
    private let baseURL: URL

    public init(directory: URL? = nil) {
        if let directory {
            self.baseURL = directory
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            self.baseURL = appSupport.appendingPathComponent("ZeroConnect", isDirectory: true)
        }
    }

    // MARK: - Contacts

    public func loadContacts() throws -> [Contact] {
        let url = contactsFileURL()
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([Contact].self, from: data)
    }

    public func saveContacts(_ contacts: [Contact]) throws {
        try ensureDirectory()
        let data = try JSONEncoder().encode(contacts)
        try data.write(to: contactsFileURL(), options: .atomic)
    }

    // MARK: - Messages

    public func loadMessages(for contactId: UUID) throws -> [StoredMessage] {
        let url = messagesFileURL(for: contactId)
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([StoredMessage].self, from: data)
    }

    public func saveMessages(_ messages: [StoredMessage], for contactId: UUID) throws {
        try ensureDirectory(subdirectory: "messages")
        let data = try JSONEncoder().encode(messages)
        try data.write(to: messagesFileURL(for: contactId), options: .atomic)
    }

    public func loadAllConversations(contactIds: [UUID]) throws -> [UUID: [StoredMessage]] {
        var result: [UUID: [StoredMessage]] = [:]
        for id in contactIds {
            let messages = try loadMessages(for: id)
            if !messages.isEmpty {
                result[id] = messages
            }
        }
        return result
    }

    // MARK: - Queued Messages (store-and-forward)

    public func loadQueuedMessages() throws -> [QueuedMessage] {
        let url = queueFileURL()
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([QueuedMessage].self, from: data)
    }

    public func saveQueuedMessages(_ messages: [QueuedMessage]) throws {
        try ensureDirectory()
        let data = try JSONEncoder().encode(messages)
        try data.write(to: queueFileURL(), options: .atomic)
    }

    // MARK: - Private

    private func ensureDirectory(subdirectory: String? = nil) throws {
        var url = baseURL
        if let sub = subdirectory {
            url = url.appendingPathComponent(sub, isDirectory: true)
        }
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    private func contactsFileURL() -> URL {
        baseURL.appendingPathComponent("contacts.json")
    }

    private func messagesFileURL(for contactId: UUID) -> URL {
        baseURL
            .appendingPathComponent("messages", isDirectory: true)
            .appendingPathComponent("\(contactId.uuidString).json")
    }

    private func queueFileURL() -> URL {
        baseURL.appendingPathComponent("queued-messages.json")
    }
}

/// A message waiting to be sent when a transport becomes available.
public struct QueuedMessage: Codable, Identifiable, Sendable {
    public let id: UUID
    public let message: Message
    public let recipientContactId: UUID
    public let queuedAt: Date
    public var retryCount: Int

    public init(message: Message, recipientContactId: UUID) {
        self.id = UUID()
        self.message = message
        self.recipientContactId = recipientContactId
        self.queuedAt = Date()
        self.retryCount = 0
    }
}
