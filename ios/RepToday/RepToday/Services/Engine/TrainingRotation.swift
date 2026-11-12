import Foundation

// MARK: - TrainingPlan

/// What today holds (ADR-0012): a Training Day for one group, or a day without one.
enum TrainingPlan: Equatable {
    case train(TrainingDay)
    /// No Training Day today. `next` is the group "Train anyway" starts; `reason` says why.
    case rest(next: TrainingDay, reason: RestReason)

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

    /// Why today holds no Training Day, `nil` on a Training Day.
    var restReason: RestReason? {
        if case let .rest(_, reason) = self { return reason }
        return nil
    }
}

/// Why a day holds no Training Day: the Cycle's Rest Day (owed, or brought forward by an Outside
/// Activity), or a day off for groups an Outside Activity worked (decision 21).
enum RestReason: Equatable {
    /// The Cycle is complete and its Rest Day is owed.
    case cycleComplete
    /// The Cycle's Rest Day, brought forward because an Outside Activity the day before worked the only
    /// group left. It falls on a day with no activity of its own, so it is the day the Rotation honors.
    case early
    /// Not the Cycle's Rest Day: every group left was worked by an Outside Activity and gets its day
    /// off. `groups` are those groups in Rotation order; `today` is true when today's own activities
    /// worked all of them.
    case workedOutside(groups: [TrainingDay], today: Bool)
    /// The user chose to rest on a Training Day (M4, the Coach's "rest today", `TodayChoices`). Never
    /// produced by the Rotation: resting is a session-free day, which skips no group.
    case chosen
}

// MARK: - TrainingRotation

/// The Push -> Pull -> Legs Rotation (ADR-0012, US-TD04): pure and date-injected, read entirely from the
/// logs and the logged Outside Activities (M2). The logs must be the full history: the replay starts a
/// Cycle at the first Training Day it is given, so a window that begins mid-Cycle misaligns every Cycle
/// after it.
///
/// - **Advance on completion.** The Rotation moves only when a Training Day session is completed, so a
///   missed day never skips a group. A Recovery flow never moves it.
/// - **Rest Day.** Completing the last group of a Cycle owes a Rest Day. Any session-free calendar day
///   after it honors the rest and starts the next Cycle; a session started before then ("Train anyway")
///   forfeits it. A day with an Outside Activity is a day of showing up, not a rest.
/// - **Outside Activities (decision 21).** The group an activity worked gets at least one day off: when
///   it is next, it swaps behind the following group, and when it is the only group left in the Cycle the
///   Rest Day comes early - and a Cycle whose rest came early owes none at its end. The early Rest Day
///   falls the day after the activity, if that day has no activity of its own; any other day the groups
///   left are resting is a day off (`RestReason.workedOutside`), not the Cycle's Rest Day. An activity
///   counts as showing up and never completes a group.
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
            } else if case .rest(_, reason: .early) = plan(
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
    /// each Cycle leads with a different ladder. `logs`, `activities` and `trainable` are the ones `plan`
    /// reads, so the Cycle is the one Today shows.
    static func coreLadderOrder(
        canonical: [String],
        library: [Exercise],
        logs: [WorkoutLog],
        activities: [OutsideActivity] = [],
        trainable: Set<TrainingDay> = Set(TrainingDay.allCases),
        asOf: Date,
        calendar: Calendar = .current
    ) -> [String] {
        let cycleStart = state(
            logs: logs,
            activities: activities,
            trainable: trainable,
            asOf: asOf,
            calendar: calendar
        ).cycleStartedAt ?? asOf
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

    // MARK: Cycle strip

    /// The Cycle as the Welcome Page's strip shows it (decision 19): the groups already done this Cycle,
    /// then today (a Training Day, the Rest Day, or a day off an Outside Activity gave), then what is still
    /// to come, in the order the Rotation will serve it. A group the user cannot train at all is left off,
    /// and a Rest Day already taken early this Cycle shows as done.
    static func cycleSteps(
        logs: [WorkoutLog],
        activities: [OutsideActivity] = [],
        trainable: Set<TrainingDay> = Set(TrainingDay.allCases),
        asOf: Date,
        calendar: Calendar = .current
    ) -> [CycleStep] {
        let state = state(logs: logs, activities: activities, trainable: trainable, asOf: asOf, calendar: calendar)
        let today = plan(logs: logs, activities: activities, trainable: trainable, asOf: asOf, calendar: calendar)
        let groups = TrainingDay.rotation.filter { trainable.contains($0) }
        let shown = groups.isEmpty ? TrainingDay.rotation : groups
        let done = shown.filter { state.completed.contains($0) }.map { CycleStep(.day($0), .done) }
        var steps = done
        let upcoming = shown.filter { !state.completed.contains($0) }
        switch today {
        case .rest(_, reason: .cycleComplete):
            steps.append(CycleStep(.rest, .today))
        case .rest(_, reason: .early), .rest(_, reason: .chosen):
            // `.chosen` never comes from the Rotation (it is a choice applied on top, `TodayChoices`); it is
            // drawn as a rest today with every group still ahead.
            steps.append(CycleStep(.rest, .today))
            steps += upcoming.map { CycleStep(.day($0), .upcoming) }
        case let .rest(_, reason: .workedOutside(offGroups, workedToday)):
            if state.restTakenEarly { steps.append(CycleStep(.rest, .done)) }
            steps.append(CycleStep(.dayOff, .today))
            // A last group worked today rests tomorrow too, so the Cycle's Rest Day comes before it.
            let restFirst = !state.restTakenEarly && workedToday && offGroups.count == 1
            if restFirst { steps.append(CycleStep(.rest, .upcoming)) }
            steps += upcoming.map { CycleStep(.day($0), .upcoming) }
            if !state.restTakenEarly && !restFirst { steps.append(CycleStep(.rest, .upcoming)) }
        case let .train(day):
            if state.restTakenEarly { steps.append(CycleStep(.rest, .done)) }
            steps.append(CycleStep(.day(day), .today))
            steps += upcoming.filter { $0 != day }.map { CycleStep(.day($0), .upcoming) }
            if !state.restTakenEarly { steps.append(CycleStep(.rest, .upcoming)) }
        }
        return steps
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
        if state.restOwed { return .rest(next: first, reason: .cycleComplete) }
        let remaining = TrainingDay.rotation.filter { !state.completed.contains($0) && trainable.contains($0) }
        guard let next = remaining.first else { return .train(first) }
        let yesterday = calendar.date(byAdding: .day, value: -1, to: day) ?? day
        var activeToday = false
        var workedToday = Set<TrainingDay>()
        var rested = Set<TrainingDay>()
        for activity in activities {
            let activityDay = calendar.startOfDay(for: activity.date)
            let isToday = includingSameDay && activityDay == day
            guard isToday || activityDay == yesterday else { continue }
            if isToday { activeToday = true }
            guard let group = activity.group else { continue }
            rested.insert(group)
            if isToday { workedToday.insert(group) }
        }
        guard rested.contains(next) else { return .train(next) }
        if let swapped = remaining.dropFirst().first(where: { !rested.contains($0) }) {
            return .train(swapped)
        }
        if !state.restTakenEarly && remaining.count == 1 && !activeToday {
            return .rest(next: next, reason: .early)
        }
        return .rest(next: next, reason: .workedOutside(groups: remaining, today: workedToday.isSuperset(of: remaining)))
    }
}

// MARK: - CycleStep

/// One step of the Cycle strip (`TrainingRotation.cycleSteps`): a Training Day or the Rest Day, and
/// whether it is done, today, or still to come.
struct CycleStep: Equatable, Hashable, Identifiable {
    enum Kind: Equatable, Hashable {
        case day(TrainingDay)
        case rest
        /// A day off for groups an Outside Activity worked (`RestReason.workedOutside`).
        case dayOff
    }

    enum Status: Equatable, Hashable {
        case done
        case today
        case upcoming
    }

    let kind: Kind
    let status: Status

    init(_ kind: Kind, _ status: Status) {
        self.kind = kind
        self.status = status
    }

    var id: String {
        switch kind {
        case let .day(day): return day.rawValue
        case .rest: return "rest"
        case .dayOff: return "dayOff"
        }
    }

    /// The short name on the strip: "Push", "Pull", "Legs", "Rest", "Day off".
    var title: String {
        switch kind {
        case .day(.push): return "Push"
        case .day(.pull): return "Pull"
        case .day(.legs): return "Legs"
        case .rest: return "Rest"
        case .dayOff: return "Day off"
        }
    }

    /// What VoiceOver reads for the step: "Push, done", "Day off, today", "Rest, coming up".
    var accessibilityLabel: String {
        switch status {
        case .done: return "\(title), done"
        case .today: return "\(title), today"
        case .upcoming: return "\(title), coming up"
        }
    }
}
