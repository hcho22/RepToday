import Foundation

// MARK: - OutsideActivity

/// A workout done outside Rep Today (`CONTEXT.md` "Outside Activity"), as the Rotation reads it: the day
/// it happened and the group it worked, if any. Logged by hand or confirmed from Apple Health in M2;
/// until then the Rotation is always handed an empty list.
struct OutsideActivity: Equatable {
    let date: Date
    /// The Training Day group it worked (run/bike/hike -> Legs, swim/row/climb -> Pull), or `nil`.
    let group: TrainingDay?
}

// MARK: - TrainingPlan

/// What today holds (ADR-0012): a Training Day for one group, or a Rest Day.
enum TrainingPlan: Equatable {
    case train(TrainingDay)
    /// A Rest Day. `next` is the group "Train anyway" starts. `isEarly` marks a Rest Day brought
    /// forward because an Outside Activity worked the only group left in the Cycle.
    case rest(next: TrainingDay, isEarly: Bool)

    /// The group a session started today trains: the planned one, or on a Rest Day the one "Train
    /// anyway" starts.
    var trainingDay: TrainingDay {
        switch self {
        case let .train(day): return day
        case let .rest(next, _): return next
        }
    }

    var isRest: Bool {
        if case .rest = self { return true }
        return false
    }
}

// MARK: - TrainingRotation

/// The Push -> Pull -> Legs Rotation (ADR-0012, US-TD04): pure and date-injected, read entirely from the
/// logs (and, from M2, the Outside Activities).
///
/// - **Advance on completion.** The Rotation moves only when a Training Day session is completed, so a
///   missed day never skips a group. A Recovery flow never moves it.
/// - **Rest Day.** Completing the last group of a Cycle owes a Rest Day. Any session-free calendar day
///   after it honors the rest and starts the next Cycle; a session started before then ("Train anyway")
///   forfeits it. A day with an Outside Activity is a day of showing up, not a rest.
/// - **Outside Activities (decision 21).** The group an activity worked gets at least one day off: when
///   it is next, it swaps behind the following group, and when it is the only group left in the Cycle the
///   Rest Day comes early - and a Cycle whose rest came early owes none at its end. An activity counts as
///   showing up and never completes a group.
/// - **Core Sprinkle.** Each Cycle's Core Sprinkle is the core ladder worked longest before the Cycle
///   began, so the ladders rotate from Cycle to Cycle (`coreLadderOrder`).
///
/// - **Trainable days.** A group the user cannot train at all - an injury removes every ladder it has
///   (`SessionAssembly.trainableDays`) - is passed over and counts as done for the Cycle, so the Rotation
///   never stalls on a day that could only ever serve stretches and a Core Sprinkle.
///
/// Existing users' logs carry no Training Day (their stations have no role), so they start at Push.
enum TrainingRotation {

    /// The Rotation's state at the start of a day.
    struct State: Equatable {
        /// Groups completed in the current Cycle.
        var completed: Set<TrainingDay> = []
        /// A Cycle is complete and its Rest Day not yet honored.
        var restOwed = false
        /// This Cycle's Rest Day already came early (an Outside Activity), so its end owes none.
        var restTakenEarly = false
        /// When the current Cycle's first session was completed, `nil` before it has one.
        var cycleStartedAt: Date?
    }

    /// Today's plan for `logs` and `activities` as of `asOf`.
    static func plan(
        logs: [WorkoutLog],
        activities: [OutsideActivity] = [],
        trainable: Set<TrainingDay> = Set(TrainingDay.allCases),
        asOf: Date,
        calendar: Calendar = .current
    ) -> TrainingPlan {
        let state = state(logs: logs, activities: activities, trainable: trainable, asOf: asOf, calendar: calendar)
        return plan(
            for: state,
            on: calendar.startOfDay(for: asOf),
            activities: activities,
            trainable: trainable,
            includingSameDay: true,
            calendar: calendar
        )
    }

    /// The Rotation's state at the start of `asOf`'s day: every Training Day log and session-free day
    /// before it replayed in order.
    static func state(
        logs: [WorkoutLog],
        activities: [OutsideActivity] = [],
        trainable: Set<TrainingDay> = Set(TrainingDay.allCases),
        asOf: Date,
        calendar: Calendar = .current
    ) -> State {
        let today = calendar.startOfDay(for: asOf)
        let trainingLogs = logs
            .filter { $0.trainingDay != nil && $0.completedAt < today }
            .sorted { $0.completedAt < $1.completedAt }
        var state = State()
        let byDay = Dictionary(grouping: trainingLogs) { calendar.startOfDay(for: $0.completedAt) }
        let activityDays = Set(activities.map { calendar.startOfDay(for: $0.date) })

        var day = trainingLogs.first.map { calendar.startOfDay(for: $0.completedAt) } ?? today
        while day < today {
            if let sessions = byDay[day] {
                for log in sessions {
                    record(log, into: &state, trainable: trainable)
                }
            } else if activityDays.contains(day) {
                // An Outside Activity counts as showing up, so its day is not a rest.
            } else if state.restOwed {
                state = State()
            } else if case .rest(_, isEarly: true) = plan(
                for: state,
                on: day,
                activities: activities,
                trainable: trainable,
                includingSameDay: false,
                calendar: calendar
            ) {
                state.restTakenEarly = true
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        // Today's own completed sessions count too: a Legs session finished this morning owes today's
        // rest, and a Push session finished this morning moves today's next group on.
        for log in logs.filter({ $0.trainingDay != nil && $0.completedAt >= today && $0.completedAt <= asOf })
            .sorted(by: { $0.completedAt < $1.completedAt }) {
            record(log, into: &state, trainable: trainable)
        }
        return state
    }

    /// The group "Train anyway" starts on a Rest Day, and the group a session generated for `logs`
    /// trains whatever today's plan says.
    static func trainingDay(
        logs: [WorkoutLog],
        activities: [OutsideActivity] = [],
        trainable: Set<TrainingDay> = Set(TrainingDay.allCases),
        asOf: Date,
        calendar: Calendar = .current
    ) -> TrainingDay {
        plan(logs: logs, activities: activities, trainable: trainable, asOf: asOf, calendar: calendar).trainingDay
    }

    // MARK: Core Sprinkle

    /// The core ladders in Core Sprinkle order for the current Cycle: the ladder worked longest before
    /// the Cycle began first (never-worked ladders ahead of worked ones, then `canonical` order), so
    /// each Cycle leads with a different ladder.
    static func coreLadderOrder(
        canonical: [String],
        library: [Exercise],
        logs: [WorkoutLog],
        asOf: Date,
        calendar: Calendar = .current
    ) -> [String] {
        let cycleStart = state(logs: logs, asOf: asOf, calendar: calendar).cycleStartedAt ?? asOf
        let ladderById = Dictionary(library.map { ($0.id, $0.progressionChainId) }, uniquingKeysWith: { first, _ in first })
        var lastWorked: [String: Date] = [:]
        for log in logs where log.completedAt < cycleStart {
            for logged in log.exercises where logged.countsForProgression {
                guard let ladder = ladderById[logged.exerciseId], canonical.contains(ladder) else { continue }
                lastWorked[ladder] = max(lastWorked[ladder] ?? .distantPast, log.completedAt)
            }
        }
        return canonical.enumerated().sorted { lhs, rhs in
            let l = lastWorked[lhs.element]
            let r = lastWorked[rhs.element]
            if (l == nil) != (r == nil) { return l == nil }
            if let l, let r, l != r { return l < r }
            return lhs.offset < rhs.offset
        }.map(\.element)
    }

    // MARK: Internals

    private static func record(_ log: WorkoutLog, into state: inout State, trainable: Set<TrainingDay>) {
        guard let day = log.trainingDay else { return }
        let skipped = Set(TrainingDay.rotation).subtracting(trainable)
        if state.restOwed || state.completed.union(skipped).count == TrainingDay.rotation.count {
            // "Train anyway": the owed rest is forfeited and a new Cycle starts.
            state = State()
        }
        if state.cycleStartedAt == nil { state.cycleStartedAt = log.completedAt }
        state.completed.insert(day)
        guard state.completed.union(skipped).count == TrainingDay.rotation.count else { return }
        if state.restTakenEarly {
            state = State()
        } else {
            state.restOwed = true
        }
    }

    /// The plan for a day that starts in `state`: rest when owed, else the first group not yet done this
    /// Cycle - unless an Outside Activity the day before (or, planning today, earlier today) worked it.
    private static func plan(
        for state: State,
        on day: Date,
        activities: [OutsideActivity],
        trainable: Set<TrainingDay>,
        includingSameDay: Bool,
        calendar: Calendar
    ) -> TrainingPlan {
        let first = TrainingDay.rotation.first { trainable.contains($0) } ?? .push
        if state.restOwed { return .rest(next: first, isEarly: false) }
        let remaining = TrainingDay.rotation.filter { !state.completed.contains($0) && trainable.contains($0) }
        guard let next = remaining.first else { return .train(first) }
        let yesterday = calendar.date(byAdding: .day, value: -1, to: day) ?? day
        let rested = Set(activities.compactMap { activity -> TrainingDay? in
            let activityDay = calendar.startOfDay(for: activity.date)
            return (includingSameDay && activityDay == day) || activityDay == yesterday ? activity.group : nil
        })
        guard rested.contains(next) else { return .train(next) }
        if let swapped = remaining.dropFirst().first(where: { !rested.contains($0) }) {
            return .train(swapped)
        }
        return .rest(next: next, isEarly: !state.restTakenEarly && remaining.count == 1)
    }
}
