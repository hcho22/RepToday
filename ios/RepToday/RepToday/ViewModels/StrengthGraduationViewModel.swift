import Foundation
import Observation

/// Decides whether the one-time Strength-Phase graduation reveal (US-SP06) should fire on this app
/// open - the "just crossed into `.strength`" detector behind the reveal `RootView` hosts.
///
/// The acceptance criterion is "on the first app open after `PhaseEvaluator` transitions the user to
/// `.strength`." That transition is a property of the user's *logs*, computed fresh by the same
/// deterministic `PhaseEvaluator` logic that gates the phase (`phaseService.phase(for:recentLogs:)`) -
/// **not** a read of the persisted `user.phase`, which the engine reads and which no production path
/// advances to `.strength` today. So this asks the evaluator what the user has *earned* and reports
/// whether that is the Strength Phase; `RootView` combines that with the persisted, ratcheting
/// `AppState.lastCelebratedPhase` so the reveal fires exactly at the crossing and never again.
///
/// It is read-only and presentation-only: it never writes `user.phase`, never persists anything, and
/// never gates the core loop. Like the other view models it is `@Observable`, takes its services as
/// protocols, and does all of its work off the main-actor-hop-free `async` service calls.
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

    /// Compute the earned phase over the user's full history and record whether it is `.strength`.
    ///
    /// Best-effort throughout: a missing user or a failed read simply leaves `earnedStrength` false, so
    /// the reveal never fires on an error rather than firing spuriously. It reads the *full* history
    /// (like the Progress tab) rather than the engine's bounded recent window, because the earn signals
    /// span ~8 weeks and a bounded window could understate the sustained-consistency span.
    func evaluate() async {
        guard let user = try? await userService.currentUser() else {
            earnedStrength = false
            return
        }
        let logs = (try? await workoutLogService.workoutLogs(from: nil, to: nil)) ?? []
        let earned = (try? await phaseService.phase(for: user, recentLogs: logs)) ?? .discipline
        earnedStrength = (earned == .strength)
    }
}
