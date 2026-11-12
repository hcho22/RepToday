import Foundation

/// Reads today's plan the way Today builds it, for the Coach's turn (M4, US-CA03): the Rotation's plan
/// with today's choices applied, and - on a Training Day - the engine's session at today's length, so
/// the Coach can talk about the session on the user's screen and propose swapping one of its movements.
///
/// Only the phone's engine can compute this, which is why the app sends it with each turn; the server
/// reads everything else from the user's own records. Best-effort: anything unreadable sends no snapshot
/// rather than failing the turn.
struct CoachTodayReader: Sendable {
    let userService: any UserServiceProtocol
    let workoutLogService: any WorkoutLogServiceProtocol
    let outsideActivityService: any OutsideActivityServiceProtocol
    let sessionPolicyService: any SessionPolicyServiceProtocol
    let workoutEngine: any WorkoutEngineProtocol
    let todayChoices: any TodayChoicesStoring
    var now: @Sendable () -> Date = { Date() }
    var calendar: Calendar = .current

    init(
        userService: any UserServiceProtocol,
        workoutLogService: any WorkoutLogServiceProtocol,
        outsideActivityService: any OutsideActivityServiceProtocol,
        sessionPolicyService: any SessionPolicyServiceProtocol,
        workoutEngine: any WorkoutEngineProtocol,
        todayChoices: any TodayChoicesStoring,
        now: @escaping @Sendable () -> Date = { Date() },
        calendar: Calendar = .current
    ) {
        self.userService = userService
        self.workoutLogService = workoutLogService
        self.outsideActivityService = outsideActivityService
        self.sessionPolicyService = sessionPolicyService
        self.workoutEngine = workoutEngine
        self.todayChoices = todayChoices
        self.now = now
        self.calendar = calendar
    }

    init(services: ServiceContainer) {
        self.init(
            userService: services.userService,
            workoutLogService: services.workoutLogService,
            outsideActivityService: services.outsideActivityService,
            sessionPolicyService: services.sessionPolicyService,
            workoutEngine: services.workoutEngine,
            todayChoices: services.todayChoices
        )
    }

    func snapshot() async -> CoachTodaySnapshot? {
        let asOf = now()
        guard let user = try? await userService.currentUser(),
              let history = try? await workoutLogService.workoutLogs(from: nil, to: nil) else { return nil }
        let activities = (try? await outsideActivityService.activities(from: nil, to: nil)) ?? []
        let lookback = calendar.date(byAdding: .day, value: -ReadyViewModel.recentLogLookbackDays, to: asOf)
        let recentLogs = lookback.map { start in history.filter { $0.completedAt >= start } } ?? history
        guard let rotation = try? await workoutEngine.trainingPlan(
            user: user,
            recentLogs: recentLogs,
            history: history,
            activities: activities,
            asOf: asOf
        ) else { return nil }
        let choices = todayChoices.choices(on: TodayChoices.dayKey(for: asOf, calendar: calendar))
        let plan = choices.applied(to: rotation)
        let minutes = choices.minutes ?? user.duration.defaultMinutes
        let localDate = TodayChoices.dayKey(for: asOf, calendar: calendar)
        let offset = (calendar.timeZone.secondsFromGMT(for: asOf)) / 60
        guard !plan.isRest else {
            return CoachTodaySnapshot(
                localDate: localDate,
                utcOffsetMinutes: offset,
                kind: .rest,
                trainingDay: plan.trainingDay,
                minutes: minutes,
                movements: []
            )
        }
        var movements: [CoachTodaySnapshot.Movement] = []
        if let policy = try? await sessionPolicyService.currentPolicy(for: user),
           let generated = try? await workoutEngine.generateWorkout(
               requestedMinutes: minutes,
               user: user,
               recentLogs: recentLogs,
               history: history,
               activities: activities,
               sessionPolicy: policy,
               variation: .none,
               trainingDay: plan.trainingDay
           ) {
            // The session on the user's screen: today's swaps applied exactly as Today applies them.
            let workout = await choices.applyingSwaps(
                to: generated, user: user, recentLogs: recentLogs, sessionPolicy: policy, engine: workoutEngine
            )
            movements = workout.blocks
                .flatMap(\.exercises)
                .map { CoachTodaySnapshot.Movement(id: $0.exercise.id, name: $0.exercise.displayName) }
        }
        return CoachTodaySnapshot(
            localDate: localDate,
            utcOffsetMinutes: offset,
            kind: .train,
            trainingDay: plan.trainingDay,
            minutes: minutes,
            movements: Array(movements.prefix(16))
        )
    }
}
