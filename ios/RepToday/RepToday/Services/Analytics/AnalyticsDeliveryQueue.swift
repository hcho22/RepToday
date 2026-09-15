import Foundation
import UIKit

/// The durable unit handed from `LiveAnalyticsService` to the delivery queue.
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
struct AnalyticsBackgroundLease: @unchecked Sendable {
    private let endOperation: @Sendable () async -> Void

    init(end: @escaping @Sendable () async -> Void) {
        self.endOperation = end
    }

    func end() async {
        await endOperation()
    }
}

/// Acquires a short `beginBackgroundTask` lease around an in-flight POST. This is the iOS mechanism
/// that lets an event emitted as the app leaves the foreground finish during ordinary suspension.
/// If iOS expires the lease, the request is cancelled and its durable row remains for the next
/// foreground or relaunch.
struct AnalyticsBackgroundExecution: @unchecked Sendable {
    private let beginOperation: @Sendable (
        @escaping @Sendable () -> Void
    ) async -> AnalyticsBackgroundLease

    init(
        begin: @escaping @Sendable (
            @escaping @Sendable () -> Void
        ) async -> AnalyticsBackgroundLease
    ) {
        self.beginOperation = begin
    }

    func begin(expirationHandler: @escaping @Sendable () -> Void) async -> AnalyticsBackgroundLease {
        await beginOperation(expirationHandler)
    }

    static let live = AnalyticsBackgroundExecution { expirationHandler in
        let identifier = await MainActor.run {
            UIApplication.shared.beginBackgroundTask(
                withName: "RepTodayAnalyticsDelivery",
                expirationHandler: expirationHandler
            )
        }
        return AnalyticsBackgroundLease {
            guard identifier != .invalid else { return }
            await MainActor.run {
                UIApplication.shared.endBackgroundTask(identifier)
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
/// Enqueue persists before returning, but never waits on a request. A drain gets at most four
/// deliveries, each with a ten-second request timeout owned by the transport. Retryable failures
/// remain durable for foreground/relaunch recovery; every item is capped at three attempts, seven
/// days, and a 50-item queue. Oldest work is evicted first so an exit-adjacent completion or
/// subscription event is not crowded out by a stale backlog.
actor AnalyticsDeliveryQueue {
    static let maxPendingEvents = 50
    static let maxAttempts = 3
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

    func enqueue(_ event: AnalyticsEvent) {
        guard isEnabled() else { return }
        loadIfNeeded()

        let generation = consentGeneration()
        guard isEnabled() else {
            discardAll()
            return
        }

        pruneIneligibleAndExpired()
        let eventId = newEventId()
        guard let body = try? AnalyticsWireBody.encode(event, installId: installId(), eventId: eventId) else {
            return
        }
        // Consent can change while encoding. Re-read both facts before the durable hand-off.
        guard isEnabled(), generation == consentGeneration() else {
            discardAll()
            return
        }

        let original = deliveries
        if deliveries.count >= Self.maxPendingEvents {
            deliveries.removeFirst(deliveries.count - Self.maxPendingEvents + 1)
        }
        deliveries.append(
            PendingAnalyticsDelivery(
                eventId: eventId,
                body: body,
                createdAtMs: milliseconds(now()),
                consentGeneration: generation,
                attemptCount: 0
            )
        )
        guard persist() else {
            deliveries = original
            return
        }
        scheduleDrain()
    }

    /// Called on app launch and foreground. It is intentionally safe to call often:
    /// one actor-owned drain runs at a time and each invocation has a fixed work cap.
    func resumePendingDelivery() {
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
        activeCancellation?.cancel()
        loadIfNeeded()
        pruneIneligibleAndExpired()
        if !isEnabled() {
            discardAll()
        } else {
            scheduleDrain()
        }
    }

    var pendingCount: Int {
        loadIfNeeded()
        pruneIneligibleAndExpired()
        return deliveries.count
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
            let lease = await backgroundExecution.begin {
                cancellation.cancel()
            }

            // This is the send-time consent gate. The lease was acquired first so suspension cannot
            // strand the gap between the check and request start; no bytes are attempted until both
            // consent and the generation captured at enqueue still match.
            guard isEligible(delivery) else {
                cancellation.cancel()
                await lease.end()
                remove(delivery.eventId)
                return
            }

            let sendTask = Task(priority: .utility) { [transport] in
                await transport.send(request)
            }
            cancellation.install(sendTask)
            let outcome = await sendTask.value
            activeCancellation = nil
            await lease.end()
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

    private func milliseconds(_ date: Date) -> Int64 {
        Int64(date.timeIntervalSince1970 * 1_000)
    }
}
