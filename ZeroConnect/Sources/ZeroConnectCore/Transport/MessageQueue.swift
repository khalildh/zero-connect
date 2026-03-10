import Foundation

/// Manages outbound messages that haven't been delivered yet.
///
/// When a message can't reach its recipient (no transport available),
/// it sits in the queue. The queue periodically retries delivery as
/// peers come and go. This enables store-and-carry-forward: a message
/// queued in a no-connectivity area gets delivered later when the user
/// walks into range of a relay peer or Meshtastic node.
public actor MessageQueue {
    private let router: MessageRouter
    private let store: MessageStore
    private var queue: [QueuedMessage] = []
    private var isRunning = false

    /// Maximum number of retry attempts before giving up on a message.
    private let maxRetries = 50

    /// How often to attempt delivery of queued messages.
    private let retryInterval: Duration = .seconds(10)

    public init(router: MessageRouter, store: MessageStore) {
        self.router = router
        self.store = store
    }

    /// Load persisted queue and start the retry loop.
    public func start() async {
        do {
            queue = try await store.loadQueuedMessages()
        } catch {
            print("[MessageQueue] Failed to load queued messages: \(error)")
        }

        guard !isRunning else { return }
        isRunning = true

        Task { [weak self] in
            guard let self else { return }
            while await self.isRunning {
                await self.processQueue()
                try? await Task.sleep(for: await self.retryInterval)
            }
        }
    }

    public func stop() {
        isRunning = false
    }

    /// Enqueue a message for delivery. Returns immediately.
    public func enqueue(_ message: Message, to contactId: UUID) {
        let queued = QueuedMessage(message: message, recipientContactId: contactId)
        queue.append(queued)
        persistQueue()
    }

    /// Number of messages waiting for delivery.
    public var pendingCount: Int {
        queue.count
    }

    /// All currently queued messages (read-only).
    public var pendingMessages: [QueuedMessage] {
        queue
    }

    // MARK: - Private

    private func processQueue() async {
        guard !queue.isEmpty else { return }

        // Refresh available peers
        await router.refreshPeers()
        let availablePeers = await router.allPeers

        guard !availablePeers.isEmpty else { return }

        var delivered: [UUID] = []

        for i in queue.indices {
            let queued = queue[i]

            // Find the contact and check if any peer can reach them
            // We use the message's recipientPublicKey to match
            do {
                // Try sending through the router — it will find the best transport
                let contact = Contact(
                    publicKey: queued.message.recipientPublicKey,
                    displayName: "Queued Recipient"
                )
                try await router.send(queued.message, to: contact)
                delivered.append(queued.id)
            } catch {
                queue[i].retryCount += 1
            }
        }

        // Remove delivered messages
        queue.removeAll { delivered.contains($0.id) }

        // Remove messages that exceeded max retries
        let expired = queue.filter { $0.retryCount >= maxRetries }
        if !expired.isEmpty {
            print("[MessageQueue] Dropping \(expired.count) messages after \(maxRetries) retries")
            queue.removeAll { $0.retryCount >= maxRetries }
        }

        if !delivered.isEmpty || !expired.isEmpty {
            persistQueue()
        }
    }

    private func persistQueue() {
        let snapshot = queue
        Task {
            do {
                try await store.saveQueuedMessages(snapshot)
            } catch {
                print("[MessageQueue] Failed to persist queue: \(error)")
            }
        }
    }
}
