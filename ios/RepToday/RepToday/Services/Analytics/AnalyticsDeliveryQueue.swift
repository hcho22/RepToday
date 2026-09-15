import Foundation
import UIKit

/// The durable unit written by the delivery queue after synchronous acceptance.
///
/// `eventId` is generated once and travels unchanged through every retry. The Convex sink uses it
/// as an idempotency key, so an interrupted response can be replayed without inflating a metric.
/// The already-encoded body deliberately snapshots the install id at event time: account deletion
/// rotates the provider for the *next* event, while this event remains attributed to the anonymous
/// install that emitted it.
struct PendingAnalyticsDelivery: Codable, Equatable, Sendable {
    let eventId: String
    let body: Data
    let createdAtMs: Int64
    let consentGeneration: Int
    var attemptCount: Int
}

private struct AcceptedAnalyticsEvent: Sendable {
    let event: AnalyticsEvent
    let eventId: String
    let installId: String
    let createdAtMs: Int64
    let consentGeneration: Int
    let backgroundActivity: AnalyticsBackgroundActivity
}

private final class AnalyticsAcceptanceBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [AcceptedAnalyticsEvent] = []

    func append(_ event: AcceptedAnalyticsEvent, limit: Int) -> [AcceptedAnalyticsEvent] {
        lock.lock()
        events.append(event)
        let overflowCount = max(0, events.count - limit)
        let evicted = Array(events.prefix(overflowCount))
        if overflowCount > 0 {
            events.removeFirst(overflowCount)
        }
        lock.unlock()
        return evicted
    }

    func takeAll() -> [AcceptedAnalyticsEvent] {
        lock.lock()
        let result = events
        events = []
        lock.unlock()
        return result
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return events.count
    }
}

/// Minimal durable storage seam. Production writes one small atomic JSON file; tests use memory.
/// Calls are serialized by `AnalyticsDeliveryQueue`.
protocol AnalyticsOutboxStorage: Sendable {
    func load() throws -> [PendingAnalyticsDelivery]
    func save(_ deliveries: [PendingAnalyticsDelivery]) throws
}

/// Process-local storage for the Debug URLProtocol probe and focused unit tests. It deliberately
/// cannot leak probe work into a later ordinary app launch.
final class VolatileAnalyticsOutboxStorage: AnalyticsOutboxStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var deliveries: [PendingAnalyticsDelivery]

    init(deliveries: [PendingAnalyticsDelivery] = []) {
        self.deliveries = deliveries
    }

    func load() throws -> [PendingAnalyticsDelivery] {
        lock.lock()
        defer { lock.unlock() }
        return deliveries
    }

    func save(_ deliveries: [PendingAnalyticsDelivery]) throws {
        lock.lock()
        self.deliveries = deliveries
        lock.unlock()
    }
}

/// A bounded on-device outbox under Application Support.
final class FileAnalyticsOutboxStorage: AnalyticsOutboxStorage, @unchecked Sendable {
    private let fileURL: URL
    private let fileManager: FileManager

    init(fileURL: URL = FileAnalyticsOutboxStorage.defaultFileURL(), fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    func load() throws -> [PendingAnalyticsDelivery] {
        guard fileManager.fileExists(atPath: fileURL.path) else { return [] }
        return try JSONDecoder().decode([PendingAnalyticsDelivery].self, from: Data(contentsOf: fileURL))
    }

    func save(_ deliveries: [PendingAnalyticsDelivery]) throws {
        if deliveries.isEmpty {
            guard fileManager.fileExists(atPath: fileURL.path) else { return }
            try fileManager.removeItem(at: fileURL)
            return
        }

        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(deliveries)
        try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    private static func defaultFileURL(fileManager: FileManager = .default) -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return base
            .appendingPathComponent("RepTodayAnalytics", isDirectory: true)
            .appendingPathComponent("outbox-v1.json", isDirectory: false)
    }
}

enum AnalyticsDeliveryOutcome: Equatable, Sendable {
    case success
    case retryableFailure
    case permanentFailure
}

/// Network seam used by the queue. It returns a classified outcome and never throws into product
/// code: retryable transport/5xx/408/429 failures remain in the outbox; other 4xx responses retire
/// as permanently invalid so a malformed event cannot retry forever.
protocol AnalyticsDeliveryTransport: Sendable {
    func send(_ request: URLRequest) async -> AnalyticsDeliveryOutcome
}

struct URLSessionAnalyticsDeliveryTransport: AnalyticsDeliveryTransport, @unchecked Sendable {
    let session: URLSession

    func send(_ request: URLRequest) async -> AnalyticsDeliveryOutcome {
        do {
            let (_, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { return .retryableFailure }
            switch http.statusCode {
            case 200..<300:
                return .success
            case 408, 429, 500...599:
                return .retryableFailure
            default:
                return .permanentFailure
            }
        } catch {
            return .retryableFailure
        }
    }
}

/// Ends one iOS background-execution assertion. The closure form keeps UIKit identifiers out of
/// the deterministic test seam.
final class AnalyticsBackgroundLease: @unchecked Sendable {
    private let lock = NSLock()
    private let endOperation: @Sendable () -> Void
    private var hasEnded = false

    init(end: @escaping @Sendable () -> Void) {
        self.endOperation = end
    }

    func end() {
        lock.lock()
        guard !hasEnded else {
            lock.unlock()
            return
        }
        hasEnded = true
        lock.unlock()
        endOperation()
    }
}

private final class AnalyticsBackgroundActivity: @unchecked Sendable {
    private let lock = NSLock()
    private var lease: AnalyticsBackgroundLease?
    private var hasFinished = false

    func install(_ lease: AnalyticsBackgroundLease) {
        lock.lock()
        if hasFinished {
            lock.unlock()
            lease.end()
            return
        }
        self.lease = lease
        lock.unlock()
    }

    func finish() {
        lock.lock()
        guard !hasFinished else {
            lock.unlock()
            return
        }
        hasFinished = true
        let lease = self.lease
        self.lease = nil
        lock.unlock()
        lease?.end()
    }
}

/// Acquires a short `beginBackgroundTask` lease around an in-flight POST. This is the iOS mechanism
/// that lets an event emitted as the app leaves the foreground finish during ordinary suspension.
/// If iOS expires the lease, the request is cancelled and its durable row remains for the next
/// foreground or relaunch.
struct AnalyticsBackgroundExecution: @unchecked Sendable {
    private let beginOperation: @Sendable (
        @escaping @Sendable () -> Void
    ) -> AnalyticsBackgroundLease

    init(
        begin: @escaping @Sendable (
            @escaping @Sendable () -> Void
        ) -> AnalyticsBackgroundLease
    ) {
        self.beginOperation = begin
    }

    func begin(expirationHandler: @escaping @Sendable () -> Void) -> AnalyticsBackgroundLease {
        beginOperation(expirationHandler)
    }

    static let live = AnalyticsBackgroundExecution { expirationHandler in
        let begin = {
            MainActor.assumeIsolated {
                UIApplication.shared.beginBackgroundTask(
                    withName: "RepTodayAnalyticsDelivery",
                    expirationHandler: expirationHandler
                )
            }
        }
        let identifier = if Thread.isMainThread {
            begin()
        } else {
            DispatchQueue.main.sync(execute: begin)
        }
        return AnalyticsBackgroundLease {
            guard identifier != .invalid else { return }
            if Thread.isMainThread {
                MainActor.assumeIsolated {
                    UIApplication.shared.endBackgroundTask(identifier)
                }
            } else {
                DispatchQueue.main.async {
                    UIApplication.shared.endBackgroundTask(identifier)
                }
            }
        }
    }

    static let none = AnalyticsBackgroundExecution { _ in
        AnalyticsBackgroundLease {}
    }
}

/// Thread-safe cancellation handle shared by the queue actor and UIKit's expiration callback.
private final class AnalyticsSendCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var task: Task<AnalyticsDeliveryOutcome, Never>?
    private var wasCancelled = false

    func install(_ task: Task<AnalyticsDeliveryOutcome, Never>) {
        lock.lock()
        if wasCancelled {
            lock.unlock()
            task.cancel()
            return
        }
        self.task = task
        lock.unlock()
    }

    func cancel() {
        lock.lock()
        wasCancelled = true
        let task = self.task
        lock.unlock()
        task?.cancel()
    }
}

/// Serial, bounded delivery state machine behind `LiveAnalyticsService`.
///
/// Acceptance is synchronous into a lock-backed buffer under a background-execution lease. The
/// actor encodes and persists afterward, then drains at most four deliveries, each with a ten-second
/// request timeout owned by the transport. Retryable failures remain durable for foreground/relaunch
/// recovery; every item is capped at three attempts, seven days, and a 50-item queue. Oldest work is
/// evicted first so an exit-adjacent completion or subscription event is not crowded out by a stale
/// backlog.
actor AnalyticsDeliveryQueue {
    static let maxPendingEvents = 50
    static let maxAttempts = 3
    static let maxPersistenceAttempts = 3
    static let maxDeliveriesPerDrain = 4
    static let maxAge: TimeInterval = 7 * 24 * 60 * 60

    private let endpoint: URL
    private let secret: String
    private let installId: @Sendable () -> String
    private let isEnabled: @Sendable () -> Bool
    private let consentGeneration: @Sendable () -> Int
    private let transport: any AnalyticsDeliveryTransport
    private let storage: any AnalyticsOutboxStorage
    private let backgroundExecution: AnalyticsBackgroundExecution
    private let now: @Sendable () -> Date
    private let newEventId: @Sendable () -> String
    private nonisolated let acceptanceBuffer = AnalyticsAcceptanceBuffer()

    private var deliveries: [PendingAnalyticsDelivery] = []
    private var hasLoaded = false
    private var isDraining = false
    private var drainRequested = false
    private var activeCancellation: AnalyticsSendCancellation?

    init(
        endpoint: URL,
        secret: String,
        installId: @escaping @Sendable () -> String,
        isEnabled: @escaping @Sendable () -> Bool,
        consentGeneration: @escaping @Sendable () -> Int,
        transport: any AnalyticsDeliveryTransport,
        storage: any AnalyticsOutboxStorage,
        backgroundExecution: AnalyticsBackgroundExecution,
        now: @escaping @Sendable () -> Date,
        newEventId: @escaping @Sendable () -> String
    ) {
        self.endpoint = endpoint
        self.secret = secret
        self.installId = installId
        self.isEnabled = isEnabled
        self.consentGeneration = consentGeneration
        self.transport = transport
        self.storage = storage
        self.backgroundExecution = backgroundExecution
        self.now = now
        self.newEventId = newEventId
    }

    nonisolated func accept(_ event: AnalyticsEvent) {
        guard isEnabled() else { return }
        let generation = consentGeneration()
        guard isEnabled(), generation == consentGeneration() else { return }
        let eventId = newEventId()
        let backgroundActivity = AnalyticsBackgroundActivity()
        let backgroundLease = backgroundExecution.begin {
            backgroundActivity.finish()
        }
        backgroundActivity.install(backgroundLease)
        let accepted = AcceptedAnalyticsEvent(
            event: event,
            eventId: eventId,
            installId: installId(),
            createdAtMs: milliseconds(now()),
            consentGeneration: generation,
            backgroundActivity: backgroundActivity
        )
        let evicted = acceptanceBuffer.append(accepted, limit: Self.maxPendingEvents)
        for event in evicted {
            event.backgroundActivity.finish()
        }
        Task(priority: .utility) { await self.persistAcceptedEvents() }
    }

    private func persistAcceptedEvents() {
        let accepted = acceptanceBuffer.takeAll()
        guard !accepted.isEmpty else { return }
        loadIfNeeded()
        pruneIneligibleAndExpired()

        let original = deliveries
        var persistable: [AcceptedAnalyticsEvent] = []
        for acceptedEvent in accepted {
            guard isEligible(acceptedEvent) else {
                acceptedEvent.backgroundActivity.finish()
                continue
            }
            guard let body = try? AnalyticsWireBody.encode(
                acceptedEvent.event,
                installId: acceptedEvent.installId,
                eventId: acceptedEvent.eventId
            ) else {
                acceptedEvent.backgroundActivity.finish()
                continue
            }
            persistable.append(acceptedEvent)
            deliveries.append(
                PendingAnalyticsDelivery(
                    eventId: acceptedEvent.eventId,
                    body: body,
                    createdAtMs: acceptedEvent.createdAtMs,
                    consentGeneration: acceptedEvent.consentGeneration,
                    attemptCount: 0
                )
            )
        }
        if deliveries.count > Self.maxPendingEvents {
            deliveries.removeFirst(deliveries.count - Self.maxPendingEvents)
        }
        var didPersist = false
        for _ in 0..<Self.maxPersistenceAttempts {
            if persist() {
                didPersist = true
                break
            }
        }
        if !didPersist {
            deliveries = original
        }
        for acceptedEvent in persistable {
            acceptedEvent.backgroundActivity.finish()
        }
        guard didPersist else { return }
        pruneIneligibleAndExpired()
        scheduleDrain()
    }

    /// Called on app launch and foreground. It is intentionally safe to call often:
    /// one actor-owned drain runs at a time and each invocation has a fixed work cap.
    func resumePendingDelivery() {
        persistAcceptedEvents()
        loadIfNeeded()
        guard isEnabled() else {
            activeCancellation?.cancel()
            discardAll()
            return
        }
        pruneIneligibleAndExpired()
        scheduleDrain()
    }

    /// Called after the persisted setting changes. Generation mismatch makes an opt-out permanent
    /// even if a rapid re-enable races this actor message: pre-opt-out work is ineligible forever.
    func consentDidChange() {
        if !isEnabled() {
            activeCancellation?.cancel()
            let accepted = acceptanceBuffer.takeAll()
            for event in accepted {
                event.backgroundActivity.finish()
            }
        } else {
            persistAcceptedEvents()
        }
        loadIfNeeded()
        pruneIneligibleAndExpired()
        if !isEnabled() {
            discardAll()
        } else {
            scheduleDrain()
        }
    }

    var pendingCount: Int {
        persistAcceptedEvents()
        loadIfNeeded()
        pruneIneligibleAndExpired()
        return deliveries.count + acceptanceBuffer.count
    }

    private func scheduleDrain() {
        guard !deliveries.isEmpty else { return }
        if isDraining {
            drainRequested = true
            return
        }
        Task(priority: .utility) { await self.drain() }
    }

    private func drain() async {
        guard !isDraining else { return }
        isDraining = true
        defer {
            isDraining = false
            activeCancellation = nil
            if drainRequested {
                drainRequested = false
                scheduleDrain()
            }
        }

        var deliveryCount = 0
        while deliveryCount < Self.maxDeliveriesPerDrain {
            guard isEnabled() else {
                activeCancellation?.cancel()
                discardAll()
                return
            }
            pruneIneligibleAndExpired()
            guard var delivery = deliveries.first else { return }

            delivery.attemptCount += 1
            let beforeAttempt = deliveries
            deliveries[0] = delivery
            guard persist() else {
                deliveries = beforeAttempt
                return
            }

            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.timeoutInterval = LiveAnalyticsService.requestTimeoutSeconds
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(secret, forHTTPHeaderField: LiveAnalyticsService.secretHeaderField)
            request.httpBody = delivery.body

            let cancellation = AnalyticsSendCancellation()
            activeCancellation = cancellation
            let backgroundActivity = AnalyticsBackgroundActivity()
            let lease = backgroundExecution.begin {
                cancellation.cancel()
                backgroundActivity.finish()
            }
            backgroundActivity.install(lease)

            // This is the send-time consent gate. The lease was acquired first so suspension cannot
            // strand the gap between the check and request start; no bytes are attempted until both
            // consent and the generation captured at enqueue still match.
            guard isEligible(delivery) else {
                cancellation.cancel()
                backgroundActivity.finish()
                remove(delivery.eventId)
                return
            }

            let sendTask = Task(priority: .utility) { [transport] in
                await transport.send(request)
            }
            cancellation.install(sendTask)
            let outcome = await sendTask.value
            activeCancellation = nil
            backgroundActivity.finish()
            deliveryCount += 1

            // Opt-out may have run while the request was in flight. Its generation invalidates the
            // row even if Settings was toggled back on before this continuation resumed.
            guard isEligible(delivery) else {
                remove(delivery.eventId)
                return
            }
            guard deliveries.contains(where: { $0.eventId == delivery.eventId }) else {
                return
            }

            switch outcome {
            case .success, .permanentFailure:
                remove(delivery.eventId)
            case .retryableFailure:
                if delivery.attemptCount >= Self.maxAttempts {
                    remove(delivery.eventId)
                }
                // Recovery is deliberately lifecycle/new-emission driven rather than an immediate
                // retry loop: offline mode must not burn all three attempts in one foreground beat.
                return
            }
        }
    }

    private func loadIfNeeded() {
        guard !hasLoaded else { return }
        hasLoaded = true
        do {
            deliveries = try storage.load()
        } catch {
            deliveries = []
            try? storage.save([])
        }
    }

    private func pruneIneligibleAndExpired() {
        let nowMs = milliseconds(now())
        let maxAgeMs = Int64(Self.maxAge * 1_000)
        let currentGeneration = consentGeneration()
        let original = deliveries
        deliveries.removeAll { delivery in
            delivery.consentGeneration != currentGeneration
                || delivery.attemptCount >= Self.maxAttempts
                || nowMs - delivery.createdAtMs > maxAgeMs
        }
        if deliveries != original {
            _ = persist()
        }
    }

    private func isEligible(_ delivery: PendingAnalyticsDelivery) -> Bool {
        isEnabled() && delivery.consentGeneration == consentGeneration()
    }

    private func isEligible(_ event: AcceptedAnalyticsEvent) -> Bool {
        isEnabled() && event.consentGeneration == consentGeneration()
    }

    private func discardAll() {
        let original = deliveries
        deliveries = []
        if !persist() {
            deliveries = original
        }
    }

    private func remove(_ eventId: String) {
        let original = deliveries
        deliveries.removeAll { $0.eventId == eventId }
        if !persist() {
            // Replaying after a retirement write failure is why the sink owns idempotency.
            deliveries = original
        }
    }

    @discardableResult
    private func persist() -> Bool {
        do {
            try storage.save(deliveries)
            return true
        } catch {
            return false
        }
    }

    nonisolated private func milliseconds(_ date: Date) -> Int64 {
        Int64(date.timeIntervalSince1970 * 1_000)
    }
}
