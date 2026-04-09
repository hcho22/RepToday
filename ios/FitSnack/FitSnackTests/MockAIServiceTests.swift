import XCTest
@testable import FitSnack

final class MockAIServiceTests: XCTestCase {

    private let service = MockAIService()

    private func makeWorkout(
        duration: Int = 15,
        focusAreas: [String] = ["Upper Body"],
        muscleGroupsWorked: [String: String] = ["chest": "primary", "triceps": "secondary"],
        exerciseCount: Int = 4
    ) -> Workout {
        let exercises = (0..<exerciseCount).map { i in
            WorkoutExercise(
                id: "we-\(i)",
                exerciseId: "ex-\(i)",
                exercise: Exercise(
                    id: "ex-\(i)", name: "Exercise \(i)", displayName: "Exercise \(i)",
                    description: "", instructions: ["Do it"], commonMistakes: [],
                    muscleGroups: Exercise.MuscleGroups(primary: [.chest], secondary: []),
                    movementPattern: .pushHorizontal, category: .strength, difficulty: 1,
                    equipment: [.none], isUnilateral: false,
                    defaultReps: 10, defaultDurationSeconds: nil,
                    defaultSets: 3, restBetweenSetsSeconds: 30,
                    estimatedTimePerSetSeconds: 15,
                    regressions: [], progressions: [],
                    metValue: 5.0, tags: []
                ),
                sets: 3, reps: 10, durationSeconds: nil,
                restAfterSeconds: 30, notes: nil,
                completedSets: [], skipped: false
            )
        }

        let block = WorkoutBlock(
            id: "block-1", name: "Upper Body", type: .strength,
            exercises: exercises, restBetweenExercisesSeconds: 30
        )

        return Workout(
            id: "w-1", userId: "user-1", createdAt: Date(),
            requestedDurationMinutes: duration,
            warmup: nil, mainBlocks: [block], cooldown: nil,
            status: .completed,
            muscleGroupsWorked: muscleGroupsWorked,
            focusAreas: focusAreas
        )
    }

    private func makeProfile() -> UserProfile {
        var profile = UserProfile.empty
        profile.displayName = "Alex"
        return profile
    }

    // MARK: - Post-Workout Summary

    func testPostWorkoutSummaryContainsWorkoutData() async throws {
        let workout = makeWorkout(duration: 15, focusAreas: ["Upper Body"])
        let profile = makeProfile()

        let response = try await service.generatePostWorkoutSummary(
            workout: workout, userProfile: profile, recentHistory: []
        )

        XCTAssertTrue(response.text.contains("15"), "Should contain duration")
        XCTAssertTrue(response.text.contains("4"), "Should contain exercise count")
        XCTAssertTrue(response.text.contains("Upper Body"), "Should contain focus area")
        XCTAssertTrue(response.text.contains("chest"), "Should contain primary muscles")
        XCTAssertTrue(response.text.contains("Alex"), "Should contain user name")
    }

    func testPostWorkoutSummaryIsOneToThreeSentences() async throws {
        let workout = makeWorkout()
        let profile = makeProfile()

        let response = try await service.generatePostWorkoutSummary(
            workout: workout, userProfile: profile, recentHistory: []
        )

        let sentenceCount = response.text.components(separatedBy: ". ")
            .filter { !$0.isEmpty }.count
        XCTAssertGreaterThanOrEqual(sentenceCount, 1)
        XCTAssertLessThanOrEqual(sentenceCount, 3)
    }

    // MARK: - Weekly Report

    func testWeeklyReportContainsStats() async throws {
        let workouts = [makeWorkout(duration: 10), makeWorkout(duration: 20)]
        let profile = makeProfile()
        let stats = GamificationStats(
            currentWeeklyStreak: 3, longestWeeklyStreak: 5,
            totalWorkoutsCompleted: 50, totalMinutesExercised: 600,
            xp: 1500, level: 4, workoutsThisWeek: 2, weeklyWorkoutGoal: 3
        )

        let result = try await service.generateWeeklyReport(
            workouts: workouts, userProfile: profile, stats: stats
        )

        XCTAssertTrue(result.contains("2 workouts"), "Should contain workout count")
        XCTAssertTrue(result.contains("30 minutes"), "Should contain total minutes")
        XCTAssertTrue(result.contains("2/3"), "Should contain goal progress")
        XCTAssertTrue(result.contains("3-week streak"), "Should contain streak")
    }

    // MARK: - Next Workout Preview

    func testNextWorkoutPreviewContainsFocus() async throws {
        let profile = makeProfile()

        let result = try await service.generateNextWorkoutPreview(
            userProfile: profile, recentHistory: [], tomorrowsFocus: "Lower Body"
        )

        XCTAssertTrue(result.contains("Lower Body"), "Should contain tomorrow's focus")
    }
}
