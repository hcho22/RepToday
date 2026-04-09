import XCTest
@testable import FitSnack

final class AIServiceTests: XCTestCase {

    // MARK: - Test Helpers

    private func makeExercise(name: String = "Push Up", metValue: Double = 5.0) -> Exercise {
        Exercise(
            id: UUID().uuidString, name: name, displayName: name,
            description: "Test exercise", instructions: ["Do it"], commonMistakes: ["Bad form"],
            muscleGroups: .init(primary: [.chest], secondary: [.triceps]),
            movementPattern: .pushHorizontal, category: .strength, difficulty: 2,
            equipment: [.none], isUnilateral: false,
            defaultReps: 10, defaultDurationSeconds: nil,
            defaultSets: 3, restBetweenSetsSeconds: 30,
            estimatedTimePerSetSeconds: 15,
            regressions: [], progressions: [],
            metValue: metValue, tags: []
        )
    }

    private func makeWorkoutExercise(name: String = "Push Up") -> WorkoutExercise {
        let exercise = makeExercise(name: name)
        return WorkoutExercise(
            id: UUID().uuidString, exerciseId: exercise.id, exercise: exercise,
            sets: 3, reps: 10, durationSeconds: nil,
            restAfterSeconds: 30, notes: nil,
            completedSets: [], skipped: false
        )
    }

    private func makeWorkout(
        exercises: [WorkoutExercise]? = nil,
        rating: Int? = 4,
        difficulty: Workout.PerceivedDifficulty? = .justRight,
        completedAt: Date? = Date()
    ) -> Workout {
        let exs = exercises ?? [makeWorkoutExercise()]
        let block = WorkoutBlock(
            id: "block1", name: "Main", type: .strength,
            exercises: exs, restBetweenExercisesSeconds: 30
        )
        return Workout(
            id: UUID().uuidString, userId: "u1", createdAt: Date(),
            requestedDurationMinutes: 15,
            mainBlocks: [block],
            status: .completed,
            completedAt: completedAt,
            actualDurationMinutes: 15,
            userRating: rating,
            perceivedDifficulty: difficulty,
            muscleGroupsWorked: ["Chest": "primary", "Triceps": "secondary"],
            focusAreas: ["upper body"]
        )
    }

    private var testProfile: UserProfile {
        UserProfile(
            id: "test-user",
            displayName: "Test User",
            age: 30,
            sex: .male,
            heightCm: 175,
            weightKg: 75,
            fitnessLevel: .intermediate,
            primaryGoal: .buildMuscle,
            injuries: "",
            availableEquipment: [.none],
            weeklyWorkoutGoal: 3,
            typicalAvailableMinutes: 15,
            unitSystem: .imperial,
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    // MARK: - AIPromptBuilder Tests

    func testPostWorkoutPromptContainsExerciseDetails() {
        let workout = makeWorkout()
        let prompt = AIPromptBuilder.postWorkoutPrompt(
            workout: workout, profile: testProfile, recentHistory: []
        )

        XCTAssertTrue(prompt.contains("15 minutes"), "Should include duration")
        XCTAssertTrue(prompt.contains("Push Up"), "Should include exercise name")
        XCTAssertTrue(prompt.contains("4/5"), "Should include rating")
        XCTAssertTrue(prompt.contains("Just Right"), "Should include difficulty")
    }

    func testPostWorkoutPromptOmitsPII() {
        let workout = makeWorkout()
        let prompt = AIPromptBuilder.postWorkoutPrompt(
            workout: workout, profile: testProfile, recentHistory: []
        )

        XCTAssertFalse(prompt.contains("Test User"), "Should not include display name")
        XCTAssertFalse(prompt.contains("test-user"), "Should not include user ID")
    }

    func testSanitizedProfileOnlyIncludesSafeFields() {
        let sanitized = AIPromptBuilder.sanitizedProfile(testProfile)

        XCTAssertTrue(sanitized.contains("30"), "Should include age")
        XCTAssertTrue(sanitized.contains("male"), "Should include sex")
        XCTAssertTrue(sanitized.contains("75"), "Should include weight")
        XCTAssertTrue(sanitized.contains("intermediate"), "Should include fitness level")
        XCTAssertFalse(sanitized.contains("Test User"), "Should not include name")
        XCTAssertFalse(sanitized.contains("test-user"), "Should not include ID")
    }

    func testWeeklyReportPromptContainsStats() {
        let workouts = [makeWorkout(), makeWorkout()]
        let prompt = AIPromptBuilder.weeklyReportPrompt(
            workouts: workouts, profile: testProfile,
            streak: 3, xp: 500, level: 4
        )

        XCTAssertTrue(prompt.contains("3 weeks"), "Should include streak")
        XCTAssertTrue(prompt.contains("500"), "Should include XP")
        XCTAssertTrue(prompt.contains("Level 4"), "Should include level")
    }

    func testNextWorkoutPreviewPromptContainsGoal() {
        let prompt = AIPromptBuilder.nextWorkoutPreviewPrompt(
            recentHistory: [makeWorkout()], profile: testProfile
        )

        XCTAssertTrue(prompt.contains("build_muscle"), "Should include primary goal")
        XCTAssertTrue(prompt.contains("15 minutes"), "Should include typical duration")
    }

    func testExerciseSummaryFormatsCorrectly() {
        let workout = makeWorkout()
        let summary = AIPromptBuilder.exerciseSummary(workout)

        XCTAssertTrue(summary.contains("Push Up"), "Should include exercise name")
        XCTAssertTrue(summary.contains("3x"), "Should include set count")
    }

    func testMuscleSummaryFormatsCorrectly() {
        let workout = makeWorkout()
        let summary = AIPromptBuilder.muscleSummary(workout)

        XCTAssertTrue(summary.contains("Primary:"), "Should label primary muscles")
        XCTAssertTrue(summary.contains("Chest"), "Should include primary muscle")
    }

    func testLast7DaysSummaryWithNoHistory() {
        let summary = AIPromptBuilder.last7DaysSummary([])
        XCTAssertEqual(summary, "No workouts in the last 7 days.")
    }

    func testLast7DaysSummaryWithRecentWorkouts() {
        let workout = makeWorkout(completedAt: Date())
        let summary = AIPromptBuilder.last7DaysSummary([workout])

        XCTAssertTrue(summary.contains("1 workouts"), "Should count workouts")
        XCTAssertTrue(summary.contains("15 total minutes"), "Should sum minutes")
    }

    func testMovementPatternStalenessWithNoHistory() {
        let staleness = AIPromptBuilder.movementPatternStaleness([])
        XCTAssertEqual(staleness, "No prior workout data.")
    }

    func testMovementPatternStalenessWithHistory() {
        let workout = makeWorkout(completedAt: Date())
        let staleness = AIPromptBuilder.movementPatternStaleness([workout])

        XCTAssertTrue(staleness.contains("push_horizontal"), "Should include movement pattern")
        XCTAssertTrue(staleness.contains("0 days ago"), "Should show days since last workout")
    }

    // MARK: - MockAIService Tests

    func testMockAIServicePostWorkoutSummary() async throws {
        let service = MockAIService()
        let workout = makeWorkout()

        let response = try await service.generatePostWorkoutSummary(
            workout: workout, userProfile: testProfile, recentHistory: []
        )

        XCTAssertFalse(response.text.isEmpty, "Should return non-empty text")
        XCTAssertTrue(response.isFallback, "Mock should mark as fallback")
        XCTAssertTrue(response.text.contains("15-minute"), "Should include duration")
        XCTAssertTrue(response.text.contains("upper body"), "Should include focus area")
    }

    func testMockAIServiceWeeklyReport() async throws {
        let service = MockAIService()
        let stats = GamificationStats(
            currentWeeklyStreak: 2, longestWeeklyStreak: 5,
            totalWorkoutsCompleted: 20, totalMinutesExercised: 300,
            xp: 500, level: 4, workoutsThisWeek: 2, weeklyWorkoutGoal: 3
        )

        let report = try await service.generateWeeklyReport(
            workouts: [makeWorkout()], userProfile: testProfile, stats: stats
        )

        XCTAssertFalse(report.isEmpty)
        XCTAssertTrue(report.contains("1 workouts"), "Should count workouts")
        XCTAssertTrue(report.contains("2/3"), "Should include goal progress")
        XCTAssertTrue(report.contains("2-week streak"), "Should include streak")
    }

    func testMockAIServiceNextWorkoutPreview() async throws {
        let service = MockAIService()

        let preview = try await service.generateNextWorkoutPreview(
            userProfile: testProfile, recentHistory: [makeWorkout()],
            tomorrowsFocus: "lower body"
        )

        XCTAssertFalse(preview.isEmpty)
        XCTAssertTrue(preview.contains("lower body"), "Should include focus area")
    }

    // MARK: - AITextResponse Tests

    func testAITextResponseDefaults() {
        let response = AITextResponse(text: "Hello")
        XCTAssertFalse(response.isFromCache)
        XCTAssertFalse(response.isFallback)
    }

    func testAITextResponseCached() {
        let response = AITextResponse(text: "Cached", isFromCache: true)
        XCTAssertTrue(response.isFromCache)
        XCTAssertFalse(response.isFallback)
    }

    func testAITextResponseFallback() {
        let response = AITextResponse(text: "Fallback", isFallback: true)
        XCTAssertFalse(response.isFromCache)
        XCTAssertTrue(response.isFallback)
    }

    // MARK: - AIServiceError Tests

    func testAIServiceErrorDescriptions() {
        XCTAssertNotNil(AIServiceError.noAPIKey.errorDescription)
        XCTAssertNotNil(AIServiceError.invalidResponse.errorDescription)
        XCTAssertNotNil(AIServiceError.rateLimited.errorDescription)
        XCTAssertNotNil(AIServiceError.clientError(400).errorDescription)
        XCTAssertNotNil(AIServiceError.serverError(500).errorDescription)
        XCTAssertNotNil(AIServiceError.unexpectedStatus(301).errorDescription)
    }

    // MARK: - APIKeyManager Tests

    func testAPIKeyManagerStoreAndRetrieve() {
        let testKey = "test-api-key-\(UUID().uuidString)"

        let stored = APIKeyManager.store(apiKey: testKey)
        XCTAssertTrue(stored, "Store should succeed")

        let retrieved = APIKeyManager.retrieve()
        XCTAssertEqual(retrieved, testKey, "Retrieved key should match stored key")

        // Clean up
        APIKeyManager.delete()
    }

    func testAPIKeyManagerDelete() {
        let testKey = "delete-test-\(UUID().uuidString)"
        APIKeyManager.store(apiKey: testKey)

        let deleted = APIKeyManager.delete()
        XCTAssertTrue(deleted, "Delete should succeed")

        let retrieved = APIKeyManager.retrieve()
        XCTAssertNil(retrieved, "Key should be nil after delete")
    }

    func testAPIKeyManagerHasKey() {
        APIKeyManager.delete() // Start clean
        XCTAssertFalse(APIKeyManager.hasKey, "Should not have key initially")

        APIKeyManager.store(apiKey: "test-key")
        XCTAssertTrue(APIKeyManager.hasKey, "Should have key after store")

        APIKeyManager.delete()
        XCTAssertFalse(APIKeyManager.hasKey, "Should not have key after delete")
    }

    func testAPIKeyManagerOverwrite() {
        APIKeyManager.store(apiKey: "first-key")
        APIKeyManager.store(apiKey: "second-key")

        let retrieved = APIKeyManager.retrieve()
        XCTAssertEqual(retrieved, "second-key", "Should return the latest stored key")

        APIKeyManager.delete()
    }

    // MARK: - SDWorkout AI Summary Cache

    func testSDWorkoutAISummaryDefaultsToNil() {
        let workout = makeWorkout()
        let sd = SDWorkout(from: workout)
        XCTAssertNil(sd.aiSummary, "AI summary should default to nil")
    }

    func testSDWorkoutAISummaryPersists() {
        let workout = makeWorkout()
        let sd = SDWorkout(from: workout)
        sd.aiSummary = "Great workout focusing on chest!"
        XCTAssertEqual(sd.aiSummary, "Great workout focusing on chest!")
    }

    func testSDWorkoutUpdateDoesNotOverwriteAISummary() {
        let workout = makeWorkout()
        let sd = SDWorkout(from: workout)
        sd.aiSummary = "Cached summary"

        // Update from a new workout (which doesn't carry aiSummary)
        var updatedWorkout = workout
        updatedWorkout.userRating = 5
        sd.update(from: updatedWorkout)

        XCTAssertEqual(sd.aiSummary, "Cached summary", "Update should not overwrite cached AI summary")
    }
}
