import Foundation
import Observation

/// Decides whether the one-time Strength-Phase graduation reveal (US-SP06) should fire on this app
/// open - the "just crossed into `.strength`" detector behind the reveal `RootView` hosts.
///
/// The acceptance criterion is "on the first app open after `PhaseEvaluator` transitions the user to
/// `.strength`." Session completion normally persists that transition. This app-open path also
/// reconciles a still-Discipline persisted user against their full history when that history currently
/// qualifies, covering users who reached the threshold before production persistence was wired.
/// `RootView` combines the resulting persisted phase with `AppState.lastCelebratedPhase` so the reveal
/// fires once and never again.
///
/// Reconciliation is an idempotent ratchet: it writes only on `.discipline -> .strength`, never
/// downgrades, and skips both the log/evaluator work and the write once Strength is current.
@Observable
@MainActor
final class StrengthGraduationViewModel {

    /// Whether the user has *earned* the Strength Phase as of the last `evaluate()` - the signal
    /// `RootView` gates the reveal on (together with the persisted one-shot flag). `false` before the
    /// first evaluation, when there is no user, or when the library read the evaluator needs fails.
    private(set) var earnedStrength = false

    private let userService: any UserServiceProtocol
    private let workoutLogService: any WorkoutLogServiceProtocol
    private let phaseService: any PhaseServiceProtocol

    init(
        userService: any UserServiceProtocol,
        workoutLogService: any WorkoutLogServiceProtocol,
        phaseService: any PhaseServiceProtocol
    ) {
        self.userService = userService
        self.workoutLogService = workoutLogService
        self.phaseService = phaseService
    }

    /// Convenience initializer wiring the three services this needs straight off the container, so the
    /// one call site (`RootView`) does not have to name them individually.
    convenience init(services: ServiceContainer) {
        self.init(
            userService: services.userService,
            workoutLogService: services.workoutLogService,
            phaseService: services.phaseService
        )
    }

    /// Reconcile the earned phase over the user's full history and record whether the persisted result
    /// is `.strength`.
    ///
    /// Best-effort throughout: a missing user or a failed read/write leaves `earnedStrength` false, so
    /// the reveal never fires before the durable transition exists. It reads the *full* history (like
    /// the Progress tab) because the earn signals span ~8 weeks. A user already persisted at Strength
    /// returns immediately, preserving the earned milestone without a redundant evaluation or write.
    func evaluate() async {
        guard let user = try? await userService.currentUser() else {
            earnedStrength = false
            return
        }

        guard user.phase == .discipline else {
            earnedStrength = true
            return
        }

        let logs = (try? await workoutLogService.workoutLogs(from: nil, to: nil)) ?? []
        let earned = (try? await phaseService.phase(for: user, recentLogs: logs)) ?? .discipline
        guard earned == .strength else {
            earnedStrength = false
            return
        }

        do {
            let persisted = try await userService.advancePhase(to: earned, for: user.id)
            earnedStrength = persisted?.phase == .strength
        } catch {
            earnedStrength = false
        }
    }
}
