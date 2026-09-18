import Foundation
import Observation

protocol CoachRuntimeProofVerifying: Sendable {
    func verifyProofOnly(timeoutSeconds: Double) async throws
}

/// Hidden QA preparation, distinct from the schema probe and the two-turn model budget.
/// Only a content-free spent marker persists; proofs and responses remain transient.
@MainActor @Observable
final class CoachRuntimeProofProbe {
    static let attemptName = "CoachRuntimeProofProbe.oneAttemptV1"
    enum Outcome: String {
        case admittedReplayDenied = "runtime-gates=verified; replay=denied; model=not-requested; distribution=unresolved"
        case failedUnverified = "runtime-gates=unverified; replay=unverified; model=not-requested; distribution=unresolved"
    }
    private let enabled: Bool
    private let defaults: UserDefaults
    private let verifier: (any CoachRuntimeProofVerifying)?
    private let timeout: Double
    private var generation = 0
    private(set) var running = false
    private(set) var outcome: Outcome?
    var attempted: Bool { defaults.object(forKey: Self.attemptName) != nil }
    var available: Bool { enabled && verifier != nil && !attempted && !running }

    init(enabled: Bool, verifier: (any CoachRuntimeProofVerifying)?, defaults: UserDefaults = .standard,
         timeout: Double = 30) {
        self.enabled = enabled; self.verifier = verifier; self.defaults = defaults; self.timeout = timeout
    }

    func run(confirmed: Bool) async {
        guard available, confirmed, let verifier, timeout.isFinite, timeout > 0, timeout <= 30 else { return }
        defaults.set(true, forKey: Self.attemptName) // Before any Apple/HTTP operation; no reset/retry.
        running = true; outcome = nil; let expected = generation
        let timeout = timeout
        defer { running = false }
        let result: Outcome
        do {
            try await boundedCoachOperation(seconds: timeout) {
                try Task.checkCancellation()
                try await verifier.verifyProofOnly(timeoutSeconds: timeout)
            }
            result = .admittedReplayDenied
        } catch {
            // Never interpolate Apple/HTTP/StoreKit errors or signed proofs into output.
            result = .failedUnverified
        }
        guard generation == expected, !Task.isCancelled else { return }
        outcome = result
    }

    func close() { generation += 1; outcome = nil }
}
