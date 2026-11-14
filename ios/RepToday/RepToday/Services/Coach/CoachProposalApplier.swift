import Foundation

/// Applies a Coach proposal the user confirmed, and undoes it (M4, US-CA03, ADR-0017).
///
/// Every action goes through the same on-device paths the user's own controls take - the Outside
/// Activity store Today logs to, the user aggregate Settings saves Focus Areas through, today's choices
/// Today's own buttons write, the reminders Settings lists - so each change is saved locally first and
/// reaches the account through M3's outbox like any other edit. Nothing here talks to the Coach.
///
/// The set of actions is the closed `CoachProposal.Action`: a de-load, a Return, the cold start, the
/// progression pace, the earned phase and the injury flags have no case, so no proposal can reach them
/// (ADR-0005). A Custom Workout is accepted separately (`acceptCustomWorkout`), and is a saved artifact
/// of its own rather than a change to the program.
struct CoachProposalApplier: Sendable {
    let userService: any UserServiceProtocol
    let outsideActivityService: any OutsideActivityServiceProtocol
    let todayChoices: any TodayChoicesStoring
    let reminders: CoachReminderService
    let customWorkouts: any CustomWorkoutServiceProtocol
    /// Tells Today its inputs changed, so it rebuilds the session on screen.
    let planInputsChanged: @Sendable @MainActor () -> Void
    var now: @Sendable () -> Date = { Date() }
    var calendar: Calendar = .current

    /// What it takes to put a change back.
    enum Undo: Equatable, Sendable {
        case deleteActivity(UUID)
        case restoreRest(CoachProposal.RestChoice?)
        case restoreLength(Int?)
        case restoreSwap(exerciseId: String)
        case restoreFocusAreas([FocusArea])
        case deleteReminder(UUID)
        case removeCustomWorkout(UUID)
    }

    enum ApplyError: Error, Equatable {
        /// There is no profile to change.
        case noUser
        /// Notifications are off, so a reminder could not be set.
        case notificationsOff
        /// A Custom Workout is accepted through `acceptCustomWorkout`, never applied as an action.
        case notAnAction
    }

    /// Applies `action` and returns how to undo it.
    func apply(_ action: CoachProposal.Action) async throws -> Undo {
        let undo: Undo
        switch action {
        case let .outsideActivity(type, minutes, distanceMeters, day):
            let activity = OutsideActivity(
                type: type,
                date: activityDate(day),
                durationMinutes: min(max(minutes, 1), OutsideActivity.maxDurationMinutes),
                distanceMeters: type.hasDistance ? distanceMeters : nil
            )
            try await outsideActivityService.save(activity)
            undo = .deleteActivity(activity.id)
        case let .restChoice(choice):
            let before = todayChoices.update(on: todayKey) { $0.rest = choice }
            undo = .restoreRest(before.rest)
        case let .todayLength(minutes):
            let before = todayChoices.update(on: todayKey) { $0.minutes = minutes }
            undo = .restoreLength(before.minutes)
        case let .swapMovement(exerciseId, _):
            todayChoices.update(on: todayKey) { choices in
                if !choices.swappedOut.contains(exerciseId) { choices.swappedOut.append(exerciseId) }
            }
            undo = .restoreSwap(exerciseId: exerciseId)
        case let .focusAreas(areas):
            guard var user = try await userService.currentUser() else { throw ApplyError.noUser }
            let before = user.profile.focusAreas
            user.profile.focusAreas = areas.canonicallyOrdered
            try await userService.save(user)
            undo = .restoreFocusAreas(before)
        case let .reminder(hour, minute, weekdays):
            let reminder = CoachReminder(hour: hour, minute: minute, weekdays: weekdays, createdAt: now())
            do {
                try await reminders.save(reminder)
            } catch CoachReminderError.permissionDenied {
                throw ApplyError.notificationsOff
            }
            undo = .deleteReminder(reminder.id)
        case .customWorkout:
            throw ApplyError.notAnAction
        }
        await planInputsChanged()
        return undo
    }

    /// Puts a change back the way it was.
    func undo(_ undo: Undo) async throws {
        switch undo {
        case let .deleteActivity(id):
            try await outsideActivityService.delete(id: id)
        case let .restoreRest(choice):
            todayChoices.update(on: todayKey) { $0.rest = choice }
        case let .restoreLength(minutes):
            todayChoices.update(on: todayKey) { $0.minutes = minutes }
        case let .restoreSwap(exerciseId):
            todayChoices.update(on: todayKey) { $0.swappedOut.removeAll { $0 == exerciseId } }
        case let .restoreFocusAreas(areas):
            guard var user = try await userService.currentUser() else { throw ApplyError.noUser }
            user.profile.focusAreas = areas
            try await userService.save(user)
        case let .deleteReminder(id):
            await reminders.delete(id: id)
        case let .removeCustomWorkout(id):
            try await customWorkouts.delete(id: id)
        }
        await planInputsChanged()
    }

    /// Accepts a reviewed Custom Workout (US-CA05): only now is it saved - and only an accepted workout
    /// can be played (FR-11).
    func acceptCustomWorkout(_ workout: CustomWorkout) async throws -> (CustomWorkout, Undo) {
        var accepted = workout
        accepted.acceptedAt = now()
        try await customWorkouts.save(accepted)
        return (accepted, .removeCustomWorkout(accepted.id))
    }

    private var todayKey: String { TodayChoices.dayKey(for: now(), calendar: calendar) }

    /// When an activity logged for `day` happened: now, or noon yesterday.
    private func activityDate(_ day: CoachProposal.Day) -> Date {
        switch day {
        case .today:
            return now()
        case .yesterday:
            let yesterday = calendar.date(byAdding: .day, value: -1, to: now()) ?? now()
            return calendar.date(bySettingHour: 12, minute: 0, second: 0, of: yesterday) ?? yesterday
        }
    }
}

/// Records a played Custom Workout (US-CA05, decision 27, FR-8): as an Outside Activity, never as a
/// session. It is the player's completion service for a Custom Workout, so the player's own completion
/// screen works unchanged while nothing reaches the session log - no ladder, Earned Reps, Foundation,
/// Training Day or Consistency-as-a-session ever reads it. The Outside Activity counts as showing up and
/// gives the group the workout worked (`CustomWorkout.trainedGroup`) at least a day off.
struct CustomWorkoutCompletionRecorder: SessionCompletionServiceProtocol {
    let workout: CustomWorkout
    let library: [Exercise]
    let outsideActivityService: any OutsideActivityServiceProtocol
    let customWorkouts: any CustomWorkoutServiceProtocol

    func recordCompletedSession(_ log: WorkoutLog, user: User, recentLogs: [WorkoutLog]) async throws {
        guard workout.isAccepted else { throw CustomWorkoutServiceError.notAccepted }
        let activity = OutsideActivity(
            type: .other,
            date: log.completedAt,
            durationMinutes: min(max(log.durationMinutes, 1), OutsideActivity.maxDurationMinutes),
            customWorkoutId: workout.id,
            customWorkoutTitle: workout.title,
            customWorkoutGroup: workout.trainedGroup(library: library)
        )
        try await outsideActivityService.save(activity)
        try await customWorkouts.markPlayed(id: workout.id, at: log.completedAt)
    }

    /// A Custom Workout's rating changes nothing: it never feeds progression.
    func recordPerceivedDifficulty(_ difficulty: PerceivedDifficulty?, forLog log: WorkoutLog) async throws {}

    /// A Custom Workout never earns a phase.
    func recordEarnedPhase() async throws {}
}

/// The Coach's on-device state, torn down with the account (US-AU05): accepted Custom Workouts, the
/// reminders the Coach or Settings scheduled (and every notification Rep Today has pending or
/// delivered), and today's choices.
/// The conversation itself lives with the account and goes with the server step.
struct CoachDeviceTeardown: Sendable {
    let customWorkouts: any CustomWorkoutServiceProtocol
    let reminders: CoachReminderService
    let todayChoices: any TodayChoicesStoring

    func erase() async throws {
        try await customWorkouts.deleteAll()
        await reminders.removeAll()
        todayChoices.clear()
    }
}
