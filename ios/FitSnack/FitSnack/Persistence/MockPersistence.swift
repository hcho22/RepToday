import CoreData
import Foundation

/// In-memory CoreData stacks for tests and SwiftUI previews (US-A04).
///
/// `controller()` hands out a fresh, empty stack so each test stays isolated; `preview`
/// is a single stack pre-seeded with one user and a couple of logs so previews have
/// something to render. Everything lives at `/dev/null`, so nothing is written to disk.
enum MockPersistence {

    /// A fresh, empty in-memory stack. Call once per test for isolation.
    static func controller() -> PersistenceController {
        PersistenceController(inMemory: true)
    }

    /// A populated in-memory stack for SwiftUI previews.
    static let preview: PersistenceController = {
        let controller = PersistenceController(inMemory: true)
        let context = controller.viewContext
        do {
            let user = CDUser(context: context)
            try user.update(from: sampleUser)
            for log in sampleLogs {
                try CDWorkoutLog(context: context).update(from: log)
            }
            try context.save()
        } catch {
            assertionFailure("Failed to seed preview store: \(error)")
        }
        return controller
    }()

    // MARK: - Sample data

    static let sampleUser = User(
        id: "preview-user",
        displayName: "Riley",
        createdAt: Date(timeIntervalSinceReferenceDate: 760_000_000),
        profile: UserProfile(
            age: 34, sex: .female, heightCm: 168.5, weightKg: 62.0,
            fitnessLevel: .intermediate, primaryGoal: .stayActive,
            sitsLong: true, injuries: ["lower_back"], typicalAvailableMinutes: 15
        ),
        phase: .discipline,
        subscription: Subscription(tier: .free, provider: .apple, expiresAt: nil, trialEndsAt: nil),
        consistency: Consistency(
            weeklyGoal: 3, score: 78.0, workoutsThisWeek: 2,
            longestChain: 6, totalWorkoutsCompleted: 38, totalMinutesExercised: 540
        ),
        why: User.Why(statement: "get on the floor with my grandkids", openingBias: .mobility),
        duration: User.Duration(defaultMinutes: 15, onboardingSeedMinutes: 15, completedDurationEWMA: 13.5),
        coldStart: User.ColdStart(sessionsLogged: 2, active: true)
    )

    static let sampleLogs: [WorkoutLog] = {
        let day: TimeInterval = 86_400
        let base = Date(timeIntervalSinceReferenceDate: 770_000_000)
        return [
            WorkoutLog(
                id: UUID(), workoutId: UUID(),
                completedAt: base - 2 * day, durationMinutes: 15, shape: .blend,
                focusPillar: nil, perceivedDifficulty: .justRight,
                exercises: [
                    LoggedExercise(
                        id: UUID(), exerciseId: "push_standard",
                        pillar: .strength, movementPattern: .push,
                        completedSets: [CompletedSet(reps: 10, durationSeconds: nil),
                                        CompletedSet(reps: 9, durationSeconds: nil)],
                        skipped: false
                    )
                ]
            ),
            WorkoutLog(
                id: UUID(), workoutId: UUID(),
                completedAt: base, durationMinutes: 10, shape: .singleFocus,
                focusPillar: .mobility, perceivedDifficulty: .tooEasy,
                exercises: [
                    LoggedExercise(
                        id: UUID(), exerciseId: "deep_squat_hold",
                        pillar: .mobility, movementPattern: .mobility,
                        completedSets: [CompletedSet(reps: nil, durationSeconds: 45)],
                        skipped: false
                    )
                ]
            )
        ]
    }()
}
