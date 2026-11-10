import Foundation
@testable import RepToday

/// Shared fixtures for the Training Day suites (M1): a fixed UTC clock, a user at any level, and logs
/// shaped the way the player writes them - stations carrying their role and Earned Reps.
enum TrainingDayFixtures {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// Tuesday 10 November 2026, noon UTC.
    static let asOf = calendar.date(from: DateComponents(year: 2026, month: 11, day: 10, hour: 12))!

    static func date(daysAgo: Int, hour: Int = 9) -> Date {
        let day = calendar.date(byAdding: .day, value: -daysAgo, to: calendar.startOfDay(for: asOf))!
        return calendar.date(byAdding: .hour, value: hour, to: day)!
    }

    static func user(
        level: FitnessLevel = .intermediate,
        phase: Phase = .discipline,
        injuries: [String] = [],
        sitsLong: Bool = false,
        asOf: Date = TrainingDayFixtures.asOf
    ) -> User {
        User(
            id: "u1",
            displayName: "Test",
            createdAt: asOf,
            profile: UserProfile(
                age: 35,
                sex: .other,
                heightCm: 175,
                weightKg: 75,
                fitnessLevel: level,
                primaryGoal: .stayActive,
                sitsLong: sitsLong,
                injuries: injuries,
                typicalAvailableMinutes: 15
            ),
            phase: phase,
            subscription: Subscription(tier: .free, provider: .apple, expiresAt: nil, trialEndsAt: nil),
            consistency: Consistency(
                weeklyGoal: 3,
                score: 50,
                workoutsThisWeek: 1,
                longestChain: 0,
                totalWorkoutsCompleted: 0,
                totalMinutesExercised: 0
            )
        )
    }

    /// One station as the player logs it: `sets` sets at `value` (reps, or seconds for a hold), carrying
    /// its role and Earned Reps.
    static func station(
        _ id: String,
        pattern: MovementPattern,
        pillar: Pillar = .strength,
        role: StationRole? = .main,
        value: Int = 15,
        earned: Int? = nil,
        sets: Int = 4,
        isHold: Bool = false,
        skipped: Bool = false,
        couldNotFinish: Bool? = nil
    ) -> LoggedExercise {
        LoggedExercise(
            id: UUID(),
            exerciseId: id,
            pillar: pillar,
            movementPattern: pattern,
            completedSets: skipped ? [] : Array(
                repeating: isHold ? CompletedSet(reps: nil, durationSeconds: value) : CompletedSet(reps: value, durationSeconds: nil),
                count: sets
            ),
            skipped: skipped,
            couldNotFinish: couldNotFinish,
            role: role,
            earnedReps: isHold ? nil : earned,
            earnedDurationSeconds: isHold ? earned : nil
        )
    }

    static func log(
        _ stations: [LoggedExercise],
        completedAt: Date,
        difficulty: PerceivedDifficulty? = .justRight,
        requestedMinutes: Int = 30
    ) -> WorkoutLog {
        WorkoutLog(
            id: UUID(),
            workoutId: UUID(),
            completedAt: completedAt,
            requestedMinutes: requestedMinutes,
            durationMinutes: requestedMinutes,
            shape: .blend,
            focusPillar: .strength,
            perceivedDifficulty: difficulty,
            exercises: stations
        )
    }

    /// A completed Training Day: one main station of the day's first ladder entry, plus a Core Sprinkle.
    static func trainingLog(_ day: TrainingDay, completedAt: Date, core: String = "core_forearm_plank") -> WorkoutLog {
        let main: LoggedExercise
        switch day {
        case .push: main = station("push_wall", pattern: .push, earned: 15)
        case .pull: main = station("pull_wall_scapular_pull", pattern: .pull, earned: 15)
        case .legs: main = station("hinge_glute_bridge", pattern: .hinge, earned: 15)
        }
        return log([main, station(core, pattern: .core, role: .core, value: 20, earned: 20, isHold: true)], completedAt: completedAt)
    }

    /// A Recovery flow: every station a recovery stretch.
    static func recoveryLog(completedAt: Date) -> WorkoutLog {
        log([
            station("mobility_cat_cow", pattern: .mobility, pillar: .mobility, role: .recovery, value: 10, sets: 1),
            station("mobility_childs_pose", pattern: .mobility, pillar: .mobility, role: .recovery, value: 45, sets: 1, isHold: true),
        ], completedAt: completedAt, difficulty: nil, requestedMinutes: 5)
    }

    /// A log written before Training Days: stations with no role and no Earned Reps.
    static func legacyLog(completedAt: Date) -> WorkoutLog {
        log([
            station("push_standard", pattern: .push, role: nil, value: 12, sets: 3),
            station("squat_bodyweight", pattern: .squat, role: nil, value: 20, sets: 3),
        ], completedAt: completedAt)
    }
}
