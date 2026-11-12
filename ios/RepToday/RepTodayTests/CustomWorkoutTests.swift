import CoreData
import XCTest
@testable import RepToday

/// Custom Workouts (M4, US-CA04/US-CA05, decision 27): the reviewable model, its local store and its
/// sync to the account through M3's outbox, and a played one's Outside Activity record.
final class CustomWorkoutTests: XCTestCase {

    private func library() async throws -> [Exercise] {
        try await MockExerciseService().exercises()
    }

    // MARK: - The model

    func testADraftResolvesCatalogStepsAndKeepsOthersTextOnly() async throws {
        let draft = CustomWorkoutDraft(title: "T", note: "", steps: [
            .init(name: "push ups", exerciseId: "push_incline", sets: 9, reps: 500, seconds: nil, perSide: true, restSeconds: 999),
            .init(name: "Forearm Plank", exerciseId: "core_forearm_plank", sets: 2, reps: 12, seconds: nil, perSide: false, restSeconds: 20),
            .init(name: "Wall Angels", exerciseId: "not_a_movement", sets: 2, reps: nil, seconds: 45, perSide: false, restSeconds: 20),
        ])
        let workout = CustomWorkout(draft: draft, messageId: "m", proposalId: "p", library: try await library(), now: Date())
        XCTAssertFalse(workout.isAccepted)
        XCTAssertEqual(workout.steps[0].name, "Incline Push-Up", "a catalog step takes the catalog's name")
        XCTAssertEqual(workout.steps[0].sets, CustomWorkout.setRange.upperBound)
        XCTAssertEqual(workout.steps[0].reps, CustomWorkout.repRange.upperBound)
        XCTAssertEqual(workout.steps[0].restSeconds, CustomWorkout.restRange.upperBound)
        XCTAssertFalse(workout.steps[0].perSide, "per side follows the catalog movement")
        XCTAssertNil(workout.steps[1].reps, "a catalog hold is timed whatever the draft said")
        XCTAssertNotNil(workout.steps[1].seconds)
        XCTAssertNil(workout.steps[2].exerciseId, "an unknown id is a text-only step")
        XCTAssertEqual(workout.steps[2].seconds, 45)
    }

    func testTheEstimateCountsWorkBothSidesAndRest() {
        let workout = CustomWorkout(
            id: UUID(), title: "T", note: "",
            steps: [
                CustomWorkoutStep(id: UUID(), name: "A", exerciseId: nil, sets: 3, reps: nil, seconds: 40, perSide: true, restSeconds: 20),
                CustomWorkoutStep(id: UUID(), name: "B", exerciseId: nil, sets: 2, reps: 10, seconds: nil, perSide: false, restSeconds: 30),
            ],
            messageId: nil, proposalId: nil, createdAt: Date(), acceptedAt: nil
        )
        // 3 x (80 + 20) + 2 x (30 + 30) = 420 seconds.
        XCTAssertEqual(workout.estimatedMinutes, 7)
    }

    func testSwappingAStepFollowsTheNewMovementsShape() async throws {
        let movements = try await library()
        let plank = try XCTUnwrap(movements.first { $0.id == "core_forearm_plank" })
        let step = CustomWorkoutStep(id: UUID(), name: "Push", exerciseId: "push_incline", sets: 3, reps: 10, seconds: nil, perSide: false, restSeconds: 30)
        let swapped = step.swapped(to: plank)
        XCTAssertEqual(swapped.exerciseId, "core_forearm_plank")
        XCTAssertEqual(swapped.name, plank.displayName)
        XCTAssertNil(swapped.reps)
        XCTAssertNotNil(swapped.seconds)
        XCTAssertEqual(swapped.sets, 3, "sets and rest stay")
    }

    // MARK: - Persistence and sync (M3's local-first path)

    func testAnAcceptedWorkoutIsSavedLocallyAndQueuedForTheAccount() async throws {
        let stack = SyncTestStack()
        var workout = CustomWorkout(draft: CoachFixture.draft, messageId: "m", proposalId: "p", library: try await library(), now: SyncFixtures.base)
        do {
            try await stack.customWorkouts.save(workout)
            XCTFail("an unaccepted workout is never stored")
        } catch {}
        workout.acceptedAt = SyncFixtures.base
        try await stack.customWorkouts.save(workout)
        let outbox = try await stack.outbox()
        XCTAssertEqual(outbox, ["customWorkout:\(workout.id.uuidString)"])

        let server = FakeAccountServer()
        try await stack.engine(server).sync()
        let row = await server.row(.customWorkout, recordId: workout.id.uuidString)
        guard case .customWorkout(let payload)? = row?.content else { return XCTFail("the workout did not reach the account") }
        XCTAssertEqual(try SyncPayloadCoder.decode(CustomWorkout.self, from: payload), workout)

        try await stack.customWorkouts.markPlayed(id: workout.id, at: SyncFixtures.base.addingTimeInterval(60))
        try await stack.engine(server).sync()
        let played = await server.row(.customWorkout, recordId: workout.id.uuidString)
        guard case .customWorkout(let playedPayload)? = played?.content else { return XCTFail() }
        XCTAssertEqual(try SyncPayloadCoder.decode(CustomWorkout.self, from: playedPayload).playedAt.count, 1)

        try await stack.customWorkouts.delete(id: workout.id)
        try await stack.engine(server).sync()
        let deleted = await server.row(.customWorkout, recordId: workout.id.uuidString)
        XCTAssertEqual(deleted?.content, .deleted, "a removed workout reaches the account as a deletion")
    }

    func testAWorkoutAcceptedOnAnotherDeviceArrives() async throws {
        let stack = SyncTestStack()
        var workout = CustomWorkout(draft: CoachFixture.draft, messageId: "m", proposalId: "p", library: try await library(), now: SyncFixtures.base)
        workout.acceptedAt = SyncFixtures.base
        let server = FakeAccountServer()
        await server.seed(.customWorkout, recordId: workout.id.uuidString, clientUpdatedAt: SyncFixtures.base,
                          content: .customWorkout(payload: try SyncPayloadCoder.encode(workout)))
        try await stack.engine(server).sync()
        let local = try await stack.customWorkouts.workouts()
        XCTAssertEqual(local, [workout])
        let outbox = try await stack.outbox()
        XCTAssertTrue(outbox.isEmpty, "a pulled record is never echoed back")
    }

    func testAPlayedWorkoutsOutsideActivityKeepsItsFieldsThroughCoreDataAndSync() async throws {
        let stack = SyncTestStack()
        let activity = OutsideActivity(
            type: .other, date: SyncFixtures.base, durationMinutes: 18,
            customWorkoutId: UUID(), customWorkoutTitle: "Desk Reset", customWorkoutGroup: .legs
        )
        try await stack.activities.save(activity)
        let stored = try await stack.activities.activities(from: nil, to: nil)
        XCTAssertEqual(stored, [activity])
        XCTAssertEqual(stored.first?.group, .legs)
        XCTAssertEqual(stored.first?.label, "Custom Workout: Desk Reset")

        // A build that predates Custom Workouts reads the same payload as an ordinary outside workout.
        struct OldActivity: Decodable { let type: String; let durationMinutes: Int }
        let payload = try SyncPayloadCoder.encode(activity)
        XCTAssertEqual(try SyncPayloadCoder.decode(OldActivity.self, from: payload).type, "other")
    }

    func testTheCustomWorkoutStoreLivesOnTheDeviceNeverInICloud() throws {
        let model = try XCTUnwrap(PersistenceController.modelVersion(named: "RepToday 4"))
        XCTAssertTrue(try XCTUnwrap(model.entities(forConfigurationName: "Local")).contains { $0.name == "CDCustomWorkout" })
        XCTAssertFalse(try XCTUnwrap(model.entities(forConfigurationName: "Cloud")).contains { $0.name == "CDCustomWorkout" })
    }
}
