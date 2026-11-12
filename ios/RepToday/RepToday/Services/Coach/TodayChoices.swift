import Foundation

/// What the user chose about today's session - rest or train anyway, its length, movements swapped out
/// (M4, US-CA03). Kept for one calendar day, so Today and the Coach read the same choices whichever
/// set them: Today's own controls write here, and so does a confirmed Coach proposal
/// (`CoachProposalApplier`). A new day starts with none.
///
/// These are choices about *today*, not records: nothing here moves the Rotation, a ladder or the
/// Consistency Score. Resting today is a session-free day like any other (a missed day never skips a
/// group, ADR-0012), and "train anyway" only lets today's session be built - completing it is what
/// moves the Rotation, exactly as before. They stay on the device and are cleared with the account.
struct TodayChoices: Codable, Equatable, Sendable {
    /// The local day the choices belong to, `yyyy-MM-dd`.
    var day: String
    var rest: CoachProposal.RestChoice?
    /// The session length chosen for today, one of the duration chips.
    var minutes: Int?
    /// Catalog ids of movements swapped out of today's session; Rep Today picks each substitute.
    var swappedOut: [String] = []

    static func empty(on day: String) -> TodayChoices {
        TodayChoices(day: day, rest: nil, minutes: nil, swappedOut: [])
    }

    var isEmpty: Bool { rest == nil && minutes == nil && swappedOut.isEmpty }

    /// The local day key for `date`.
    static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// Today's plan once the rest choice is applied: resting turns a Training Day into a Rest Day the
    /// user chose (`RestReason.chosen`), and training anyway turns a Rest Day into the next Training Day.
    func applied(to plan: TrainingPlan) -> TrainingPlan {
        switch (plan, rest) {
        case let (.train(day), .restToday?):
            return .rest(next: day, reason: .chosen)
        case let (.rest(next, _), .trainAnyway?):
            return .train(next)
        default:
            return plan
        }
    }

    /// Today's session as the user sees it: each movement swapped out today replaced the way the swap
    /// control replaces it (`ExerciseSwap`), in the order the swaps were made, so a substitute swapped out
    /// later is replaced in turn. A movement with no alternative stays. Today and the Coach's view of
    /// today both read the session through this, so they cannot disagree.
    func applyingSwaps(
        to generated: Workout,
        user: User,
        recentLogs: [WorkoutLog],
        sessionPolicy: SessionPolicy,
        engine: any WorkoutEngineProtocol
    ) async -> Workout {
        var workout = generated
        for exerciseId in swappedOut {
            for (blockIndex, block) in workout.blocks.enumerated() {
                guard let index = block.exercises.firstIndex(where: { $0.exercise.id == exerciseId }) else { continue }
                let outcome = try? await engine.swapExercise(
                    block.exercises[index],
                    in: workout,
                    user: user,
                    recentLogs: recentLogs,
                    sessionPolicy: sessionPolicy
                )
                if case .substituted(let substitute)? = outcome {
                    workout.blocks[blockIndex].exercises[index] = substitute
                }
            }
        }
        return workout
    }
}

/// Where today's choices are kept.
protocol TodayChoicesStoring: AnyObject, Sendable {
    /// The choices for `day`, or none when the stored ones belong to another day.
    func choices(on day: String) -> TodayChoices
    func save(_ choices: TodayChoices)
    /// Forgets every choice (account deletion).
    func clear()
}

extension TodayChoicesStoring {
    /// Reads today's choices, changes them and saves them, returning what was there before (for Undo).
    @discardableResult
    func update(on day: String, _ change: (inout TodayChoices) -> Void) -> TodayChoices {
        let before = choices(on: day)
        var after = before
        change(&after)
        save(after)
        return before
    }
}

/// The production store, in `UserDefaults`.
final class DefaultsTodayChoicesStore: TodayChoicesStoring, @unchecked Sendable {
    // Safe: `UserDefaults` is thread-safe, and the lock serializes each read-modify-write.
    private let defaults: UserDefaults
    private let lock = NSLock()
    static let key = "Coach.todayChoices"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func choices(on day: String) -> TodayChoices {
        lock.lock()
        defer { lock.unlock() }
        guard let data = defaults.data(forKey: Self.key),
              let stored = try? JSONDecoder().decode(TodayChoices.self, from: data),
              stored.day == day else {
            return .empty(on: day)
        }
        return stored
    }

    func save(_ choices: TodayChoices) {
        lock.lock()
        defer { lock.unlock() }
        if choices.isEmpty {
            defaults.removeObject(forKey: Self.key)
        } else if let data = try? JSONEncoder().encode(choices) {
            defaults.set(data, forKey: Self.key)
        }
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        defaults.removeObject(forKey: Self.key)
    }
}

/// An in-memory store for previews and tests.
final class InMemoryTodayChoicesStore: TodayChoicesStoring, @unchecked Sendable {
    // Safe: every access goes through the lock.
    private let lock = NSLock()
    private var stored: TodayChoices?

    init(_ choices: TodayChoices? = nil) {
        stored = choices
    }

    func choices(on day: String) -> TodayChoices {
        lock.lock()
        defer { lock.unlock() }
        guard let stored, stored.day == day else { return .empty(on: day) }
        return stored
    }

    func save(_ choices: TodayChoices) {
        lock.lock()
        defer { lock.unlock() }
        stored = choices.isEmpty ? nil : choices
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        stored = nil
    }
}
