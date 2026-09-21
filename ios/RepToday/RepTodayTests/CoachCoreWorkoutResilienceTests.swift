import XCTest
@testable import RepToday

/// Integration coverage for the product boundary that matters most: the optional premium Coach and
/// the deterministic core workout share a container, but the core path never depends on a Coach
/// response. This uses the same Ready/player/completion services the production views compose.
@MainActor
final class CoachCoreWorkoutResilienceTests: XCTestCase {
    private actor UnauthorizedCoachTransport: CoachProxyTransport {
        private(set) var callCount = 0

        func post(
            to url: URL,
            jsonBody: Data,
            headers: [String: String],
            timeoutSeconds: Double
        ) async throws -> (data: Data, statusCode: Int) {
            callCount += 1
            return (Data(#"{"error":"unauthorized"}"#.utf8), 401)
        }
    }

    private func replacingCoach(in base: ServiceContainer, with client: CoachProxyClient?) -> ServiceContainer {
        ServiceContainer(
            exerciseService: base.exerciseService,
            workoutEngine: base.workoutEngine,
            sessionPolicyService: base.sessionPolicyService,
            consistencyService: base.consistencyService,
            phaseService: base.phaseService,
            userService: base.userService,
            workoutLogService: base.workoutLogService,
            activeSessionStore: base.activeSessionStore,
            sessionCompletionService: base.sessionCompletionService,
            healthKitService: base.healthKitService,
            subscriptionService: base.subscriptionService,
            authService: base.authService,
            analyticsService: base.analyticsService,
            accountDeletionService: base.accountDeletionService,
            coachClient: client,
            coachPolicyService: base.coachPolicyService
        )
    }

    private func workoutSignature(_ workout: Workout) -> [String] {
        workout.blocks.flatMap { block in
            ["block:\(block.category.rawValue):\(block.title)"] + block.exercises.map { prescription in
                [
                    prescription.exercise.id,
                    String(prescription.sets),
                    prescription.reps.map { String($0) } ?? "-",
                    prescription.durationSeconds.map { String($0) } ?? "-",
                    String(prescription.restSeconds),
                ].joined(separator: ":")
            }
        }
    }

    func testUnavailableAndUnauthorizedCoachLeaveGenerationStartProgressionAndCompletionIntact() async throws {
        for rejectsCoach in [false, true] {
            let base = ServiceContainer.mock()
            let denyingTransport = UnauthorizedCoachTransport()
            let coachClient = rejectsCoach
                ? CoachProxyClient(
                    endpoint: URL(string: "https://proxy.example.com/coach")!,
                    safetyIdentifier: testCoachSafetyIdentifier,
                    transport: denyingTransport
                )
                : nil
            let services = replacingCoach(in: base, with: coachClient)
            let user = MockPersistence.sampleUser
            try await services.userService.save(user)

            // First exercise the optional integration in its unavailable or authorization-rejected
            // state. A tuning-shaped question is deliberate: a rejected send must not write even the
            // Coach's already-bounded preference policy.
            let coach = CoachViewModel(services: services)
            coach.grantDataSharingConsent()
            coach.draft = "focus my push"
            await coach.send()

            if rejectsCoach {
                let coachCallCount = await denyingTransport.callCount
                XCTAssertEqual(coachCallCount, 1)
                XCTAssertEqual(coach.errorMessage, CoachViewModel.genericFailureMessage)
                XCTAssertTrue(coach.canRetry)
            } else {
                XCTAssertFalse(coach.isAvailable)
                XCTAssertTrue(coach.messages.isEmpty)
                XCTAssertNil(coach.errorMessage)
            }
            let policyAfterCoach = try await services.sessionPolicyService.currentPolicy(for: user)
            XCTAssertEqual(policyAfterCoach, .default,
                           "an unavailable or rejected Coach must not mutate the program")

            // Follow the production Ready composition into the deterministic engine.
            let ready = ReadyViewModel(
                userService: services.userService,
                sessionPolicyService: services.sessionPolicyService,
                workoutEngine: services.workoutEngine,
                workoutLogService: services.workoutLogService,
                consistencyService: services.consistencyService,
                activeSessionStore: services.activeSessionStore,
                analytics: services.analyticsService
            )
            await ready.load()
            let workout = try XCTUnwrap(ready.workout)
            XCTAssertNil(ready.errorMessage)

            // Compare the meaningful plan (excluding intentionally fresh UUIDs/timestamps) with a
            // direct call through the same deterministic engine inputs. Coach state is not an input.
            let expected = try await services.workoutEngine.generateWorkout(
                requestedMinutes: ready.requestedMinutes,
                user: user,
                recentLogs: ready.recentLogs,
                sessionPolicy: ready.policy
            )
            XCTAssertEqual(workoutSignature(workout), workoutSignature(expected))

            // Follow the production player composition through start, meaningful progression, and
            // the real shared completion service, then read the durable log back from the container.
            let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
            let player = ActiveSessionViewModel(
                workout: workout,
                swapEngine: services.workoutEngine,
                user: ready.user,
                recentLogs: ready.recentLogs,
                sessionPolicy: ready.policy,
                store: ready.sessionStore,
                userId: ready.user?.id,
                completionService: services.sessionCompletionService,
                analytics: services.analyticsService,
                now: { now }
            )
            player.start()
            XCTAssertEqual(player.startedAt, now)
            XCTAssertFalse(player.isComplete)

            player.completeSet()
            XCTAssertGreaterThan(player.completedSetCount, 0, "the active session must advance real work")
            var remainingAdvanceBudget = 500
            while !player.isComplete, remainingAdvanceBudget > 0 {
                player.completeSet()
                remainingAdvanceBudget -= 1
            }
            XCTAssertTrue(player.isComplete, "the on-device player must reach completion without Coach")
            XCTAssertGreaterThan(remainingAdvanceBudget, 0, "the progression walk must stay bounded")
            await player.completionTask?.value

            let logs = try await services.workoutLogService.workoutLogs(from: nil, to: nil)
            XCTAssertEqual(logs.count, 1)
            XCTAssertEqual(logs.first?.workoutId, workout.id)
            XCTAssertTrue(logs.first?.exercises.contains { !$0.completedSets.isEmpty } == true)
        }
    }
}
