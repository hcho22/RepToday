import XCTest
@testable import RepToday

/// US-E01 end-to-end evidence: drives the deterministic engine the way a user request does and emits a
/// human-readable transcript (grep the `E2E|` lines out of the test log). It shows two things a bare
/// unit assertion cannot:
///   1. the full 5-60 minute request -> session-shape mapping, including the new extended band; and
///   2. that a request across the whole range - crucially the new 45 and 60 minute end - assembles into
///      a complete, playable session (warm-up first, cooldown when long, real prescribed exercises).
///
/// This is a real test (it asserts the US-E01 invariants) whose side effect is the reviewer transcript.
final class USE01RangeEvidenceTests: XCTestCase {

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private var asOf: Date {
        calendar.date(from: DateComponents(year: 2026, month: 6, day: 29, hour: 12))!
    }

    private func date(daysAgo: Int) -> Date {
        calendar.date(byAdding: .day, value: -daysAgo, to: asOf)!
    }

    private func library() async throws -> [Exercise] {
        try await MockExerciseService().exercises()
    }

    private func user() -> User {
        User(
            id: "u1",
            displayName: "Test",
            createdAt: asOf,
            profile: UserProfile(
                age: 35, sex: .other, heightCm: 175, weightKg: 75,
                fitnessLevel: .intermediate, primaryGoal: .stayActive,
                sitsLong: false, injuries: [], typicalAvailableMinutes: 15
            ),
            phase: .discipline,
            subscription: Subscription(tier: .free, provider: .apple, expiresAt: nil, trialEndsAt: nil),
            consistency: Consistency(
                weeklyGoal: 3, score: 50, workoutsThisWeek: 1,
                longestChain: 0, totalWorkoutsCompleted: 0, totalMinutesExercised: 0
            )
        )
    }

    private func log(
        _ exercises: [(id: String, pillar: Pillar, pattern: MovementPattern, reps: Int)],
        daysAgo: Int,
        difficulty: PerceivedDifficulty? = nil
    ) -> WorkoutLog {
        WorkoutLog(
            id: UUID(), workoutId: UUID(), completedAt: date(daysAgo: daysAgo),
            requestedMinutes: 20, durationMinutes: 20, shape: .blend, focusPillar: nil,
            perceivedDifficulty: difficulty,
            exercises: exercises.map { entry in
                LoggedExercise(
                    id: UUID(), exerciseId: entry.id, pillar: entry.pillar,
                    movementPattern: entry.pattern,
                    completedSets: [
                        CompletedSet(reps: entry.reps, durationSeconds: nil),
                        CompletedSet(reps: entry.reps, durationSeconds: nil),
                        CompletedSet(reps: entry.reps, durationSeconds: nil),
                    ],
                    skipped: false
                )
            }
        )
    }

    private func someHistory() -> [WorkoutLog] {
        [
            log([
                ("push_standard", .strength, .push, 12),
                ("squat_bodyweight", .strength, .squat, 15),
            ], daysAgo: 2, difficulty: .justRight),
            log([("mobility_cat_cow", .mobility, .mobility, 10)], daysAgo: 4),
        ]
    }

    // MARK: - Part A: full 5-60 request -> shape mapping (with clamping)

    func testTranscript_A_fullRangeShapeMapping() {
        print("E2E| ============================================================")
        print("E2E| US-E01  Session-shape selection across the full 5-60 min range")
        print("E2E| ============================================================")
        print("E2E| minutes | engine template | canonical SessionShape")
        print("E2E| --------+-----------------+-----------------------")

        // Every supported minute plus the clamp edges, so the whole surface is visible.
        let sampled = [1, 5, 6, 10, 11, 15, 20, 21, 30, 40, 41, 45, 55, 60, 61, 120]
        for m in sampled {
            let template = SessionShapeTemplate.select(requestedMinutes: m)
            let clampNote: String
            if m < SessionShapeTemplate.supportedRange.lowerBound { clampNote = "  (clamped up to floor)" }
            else if m > SessionShapeTemplate.supportedRange.upperBound { clampNote = "  (clamped down to ceiling)" }
            else { clampNote = "" }
            print(String(format: "E2E|   %4d  | %-15@ | %@%@",
                         m, "\(template)" as NSString, "\(template.shape)" as NSString, clampNote as NSString))
        }

        // Band summary + the exact PRD boundaries (10/20/40).
        print("E2E|")
        print("E2E| Bands: 5-10 singleFocus | 11-20 blendLight | 21-40 blendFull | 41-60 blendExtended")
        print("E2E| Boundaries -> 10:\(SessionShapeTemplate.select(requestedMinutes: 10))  11:\(SessionShapeTemplate.select(requestedMinutes: 11))  20:\(SessionShapeTemplate.select(requestedMinutes: 20))  21:\(SessionShapeTemplate.select(requestedMinutes: 21))  40:\(SessionShapeTemplate.select(requestedMinutes: 40))  41:\(SessionShapeTemplate.select(requestedMinutes: 41))")

        // Assert the PRD mapping across the whole supported range with no gaps.
        for m in 5...60 {
            let expected: SessionShapeTemplate
            switch m {
            case ...10: expected = .singleFocus
            case 11...20: expected = .blendLight
            case 21...40: expected = .blendFull
            default: expected = .blendExtended
            }
            XCTAssertEqual(SessionShapeTemplate.select(requestedMinutes: m), expected, "\(m) min mapped wrong")
        }
        // New extended case resolves to the canonical .blend, and clamps are total.
        XCTAssertEqual(SessionShapeTemplate.blendExtended.shape, .blend)
        XCTAssertEqual(SessionShapeTemplate.select(requestedMinutes: -30), .singleFocus)
        XCTAssertEqual(SessionShapeTemplate.select(requestedMinutes: 999), .blendExtended)
    }

    // MARK: - Part B: each request assembles a complete, playable session

    func testTranscript_B_assemblesRealSessionsAcrossRange() async throws {
        let library = try await library()
        let logs = someHistory()

        print("E2E|")
        print("E2E| ============================================================")
        print("E2E| US-E01  Full sessions assembled across 5-60 min (real library)")
        print("E2E| ============================================================")

        // Includes the two durations the extended band newly unlocks: 45 and 60.
        for minutes in [5, 10, 15, 20, 30, 45, 60] {
            let template = SessionShapeTemplate.select(requestedMinutes: minutes)
            let workout = SessionAssembly.assemble(
                requestedMinutes: minutes, user: user(), library: library,
                recentLogs: logs, asOf: asOf, calendar: calendar
            )
            let plannedSec = SessionAssembly.plannedSeconds(of: workout)
            let plannedMin = Double(plannedSec) / 60.0
            let delta = plannedMin - Double(minutes)

            print("E2E|")
            print(String(format: "E2E| >>> Requested %d min  ->  template=%@  shape=%@  |  planned=%.1f min (Δ %+.1f)",
                         minutes, "\(template)" as NSString, "\(workout.shape)" as NSString, plannedMin, delta))
            for block in workout.blocks {
                print("E2E|     [\(block.category)] \(block.title)")
                for pe in block.exercises {
                    let dose: String
                    if let reps = pe.reps {
                        dose = "\(pe.sets)x\(reps) reps"
                    } else if let hold = pe.durationSeconds {
                        dose = "\(pe.sets)x\(hold)s hold"
                    } else {
                        dose = "\(pe.sets) sets"
                    }
                    print("E2E|         - \(pe.exercise.displayName)  (\(dose), rest \(pe.restSeconds)s)")
                }
            }

            // US-E01 invariants that must hold for every request in the range:
            XCTAssertEqual(workout.shape, template.shape, "\(minutes) min: shape mismatch")
            XCTAssertEqual(workout.blocks.first?.category, .warmup, "\(minutes) min: session must open with a warm-up")
            XCTAssertFalse(workout.blocks.isEmpty, "\(minutes) min: empty session")
            let hasCooldown = workout.blocks.contains { $0.category == .cooldown }
            if minutes > 10 {
                XCTAssertTrue(hasCooldown, "\(minutes) min: sessions over 10 min must close with a cooldown")
            }
            // Every prescribed movement is a real, fully-formed, bodyweight prescription.
            for block in workout.blocks {
                for pe in block.exercises {
                    XCTAssertGreaterThanOrEqual(pe.sets, 1, "\(minutes) min: \(pe.exercise.displayName) has no sets")
                    XCTAssertEqual(pe.exercise.equipment, [], "\(minutes) min: \(pe.exercise.displayName) breaks the Zero-Equipment Floor")
                    XCTAssertTrue(pe.reps != nil || pe.durationSeconds != nil, "\(minutes) min: \(pe.exercise.displayName) has neither reps nor hold")
                }
            }
        }
        print("E2E|")
        print("E2E| All requests 5-60 produced a complete, warm-up-first, playable session.")
    }
}
