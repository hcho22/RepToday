import XCTest
@testable import RepToday

/// The Coach tab's behavior (M4, US-CA01/US-CA02/US-CA03/US-CA04/US-CA05/US-CA08): the server-decided
/// gate, the consent gate, the persistent conversation, every tool's apply and Undo, the closed action
/// set, and the Custom Workout acceptance gate - each read back from the stores an action writes.
@MainActor
final class CoachViewModelTests: XCTestCase {

    // MARK: - The gate (US-CA02)

    func testAFreeAccountSeesThePreviewAndNeverTalksToTheCoach() async {
        let fixture = CoachFixture(premium: false)
        await fixture.viewModel.load()
        XCTAssertEqual(fixture.viewModel.access, .free)
        fixture.viewModel.draft = "hello"
        await fixture.viewModel.send()
        let sent = await fixture.coach.sent
        XCTAssertTrue(sent.isEmpty)
    }

    /// Returning to the tab re-checks Premium with the known state still on screen: only the first load
    /// shows the spinner, so a re-check never flashes "Loading" over the preview or the conversation.
    func testARecheckKeepsTheKnownStateOnScreenUntilItHasAnAnswer() async {
        let fixture = CoachFixture(premium: false)
        await fixture.viewModel.load()
        XCTAssertEqual(fixture.viewModel.access, .free)

        await fixture.entitlements.set(premium: true)
        let recheck = Task { await fixture.viewModel.load() }
        await Task.yield()
        XCTAssertEqual(fixture.viewModel.access, .free, "the preview stays while the re-check waits on the server")
        await recheck.value
        XCTAssertEqual(fixture.viewModel.access, .premium)
    }

    func testAPremiumAccountOpensTheCoachWithItsSavedConversation() async {
        let saved = [
            CoachMessage(id: "m1", role: .user, text: "I like mornings", createdAt: CoachFixture.now, proposals: []),
            CoachMessage(id: "m2", role: .coach, text: "Mornings it is.", createdAt: CoachFixture.now, proposals: []),
        ]
        let fixture = CoachFixture(coach: MockCoachService(history: saved))
        await fixture.viewModel.load()
        XCTAssertEqual(fixture.viewModel.access, .premium)
        XCTAssertEqual(fixture.viewModel.messages, saved, "the conversation is the account's, loaded from the server")
    }

    func testPremiumOnThisPhoneIsLinkedToTheAccountBeforeTheCoachOpens() async {
        let premium = Subscription(tier: .premium, provider: .apple, expiresAt: nil, trialEndsAt: nil)
        let fixture = CoachFixture(premium: false, subscription: premium)
        await fixture.viewModel.load()
        XCTAssertEqual(fixture.viewModel.access, .premium, "a StoreKit purchase made before accounts unlocks the Coach once linked")
    }

    func testASubscriptionOnAnotherAccountIsExplainedNotUnlocked() async {
        let premium = Subscription(tier: .premium, provider: .apple, expiresAt: nil, trialEndsAt: nil)
        let fixture = CoachFixture(premium: false, subscription: premium)
        await fixture.entitlements.setLinkOutcome(nil, error: .linkedToOtherAccount)
        await fixture.viewModel.load()
        XCTAssertEqual(fixture.viewModel.access, .unconfirmed(message: CoachCopy.linkedToOtherAccount))
    }

    func testAServerRefusalMidConversationReturnsToThePreview() async {
        let fixture = CoachFixture()
        await fixture.viewModel.load()
        await fixture.coach.setReply { _ in throw CoachServiceError.notPremium }
        fixture.viewModel.draft = "hello"
        await fixture.viewModel.send()
        XCTAssertEqual(fixture.viewModel.access, .free, "the server checks Premium on every turn and the tab follows it")
        XCTAssertTrue(fixture.viewModel.messages.isEmpty, "the refused message is not left in the conversation")
    }

    // MARK: - Consent (US-AC04/US-CA07)

    func testNothingIsSentBeforeTheDisclosureIsAcknowledged() async {
        let fixture = CoachFixture(consent: false)
        await fixture.viewModel.load()
        XCTAssertTrue(fixture.viewModel.needsDataSharingConsent)
        fixture.viewModel.draft = "hello"
        await fixture.viewModel.send()
        await fixture.viewModel.sendQuickAction(CoachViewModel.quickActions[0])
        await fixture.viewModel.retry()
        let sent = await fixture.coach.sent
        XCTAssertTrue(sent.isEmpty)
        fixture.viewModel.grantDataSharingConsent()
        await fixture.viewModel.send()
        let afterConsent = await fixture.coach.sent
        XCTAssertEqual(afterConsent.count, 1)
    }

    // MARK: - Sending (US-CA01/US-CA03)

    func testATurnAppendsTheStoredMessagesAndSendsTodaysPlan() async throws {
        let fixture = CoachFixture()
        await fixture.viewModel.load()
        fixture.viewModel.draft = "  Why push today?  "
        await fixture.viewModel.send()
        XCTAssertEqual(fixture.viewModel.messages.map(\.role), [.user, .coach])
        XCTAssertEqual(fixture.viewModel.messages.first?.text, "Why push today?")
        XCTAssertEqual(fixture.viewModel.draft, "")
        let sent = await fixture.coach.sent
        let today = try XCTUnwrap(sent.first?.today, "the phone sends the plan only it can compute")
        XCTAssertEqual(today.localDate, CoachFixture.today)
        XCTAssertEqual(today.kind, .train)
        XCTAssertFalse(today.movements.isEmpty, "today's movements, so the Coach can propose a swap")
    }

    func testAFailedTurnIsRetryableWithTheSameMessageAndNoDuplicate() async {
        let fixture = CoachFixture()
        await fixture.viewModel.load()
        await fixture.coach.setReply { _ in throw CoachServiceError.offline }
        fixture.viewModel.draft = "hello"
        await fixture.viewModel.send()
        XCTAssertEqual(fixture.viewModel.errorMessage, CoachCopy.couldNotAnswer)
        XCTAssertTrue(fixture.viewModel.canRetry)
        XCTAssertEqual(fixture.viewModel.messages.count, 1, "the question stays on screen")

        await fixture.coach.setReply { _ in ("You're back.", []) }
        await fixture.viewModel.retry()
        XCTAssertNil(fixture.viewModel.errorMessage)
        XCTAssertEqual(fixture.viewModel.messages.map(\.text), ["hello", "You're back."])
        XCTAssertFalse(fixture.viewModel.isSending)
    }

    func testATooLongMessageGivesTheTextBack() async {
        let fixture = CoachFixture()
        await fixture.viewModel.load()
        await fixture.coach.setReply { _ in throw CoachServiceError.invalidMessage }
        fixture.viewModel.draft = "a long question"
        await fixture.viewModel.send()
        XCTAssertEqual(fixture.viewModel.draft, "a long question")
        XCTAssertTrue(fixture.viewModel.messages.isEmpty)
        XCTAssertFalse(fixture.viewModel.canRetry)
    }

    func testTheDailyLimitReadsCalmly() async {
        let fixture = CoachFixture()
        await fixture.viewModel.load()
        await fixture.coach.setReply { _ in throw CoachServiceError.limitReached }
        fixture.viewModel.draft = "hello"
        await fixture.viewModel.send()
        XCTAssertEqual(fixture.viewModel.errorMessage, CoachCopy.limitReached)
    }

    // MARK: - Tools: apply and Undo (US-CA03)

    /// Sends one message whose reply carries `action`, and returns the fixture and the stored reply.
    private func proposing(_ action: CoachProposal.Action, fixture given: CoachFixture? = nil) async throws -> (CoachFixture, CoachMessage, CoachProposal) {
        let fixture = given ?? CoachFixture()
        let proposal = CoachFixture.proposal(action)
        await fixture.coach.setReply { _ in ("Confirm below.", [proposal]) }
        await fixture.viewModel.load()
        fixture.viewModel.draft = "please"
        await fixture.viewModel.send()
        let message = try XCTUnwrap(fixture.viewModel.messages.last)
        return (fixture, message, try XCTUnwrap(message.proposals.first))
    }

    private func status(_ fixture: CoachFixture, _ proposal: CoachProposal) -> CoachProposal.Status? {
        fixture.viewModel.messages.flatMap(\.proposals).first { $0.id == proposal.id }?.status
    }

    func testLoggingAnOutsideActivityGoesThroughTheActivityStoreAndUndoes() async throws {
        let (fixture, message, proposal) = try await proposing(.outsideActivity(type: .run, minutes: 30, distanceMeters: 5000, day: .today))
        let before = try await fixture.outsideActivityService.activities(from: nil, to: nil)
        XCTAssertTrue(before.isEmpty, "nothing is written before the user confirms")

        await fixture.viewModel.apply(proposal, in: message)
        let logged = try await fixture.outsideActivityService.activities(from: nil, to: nil)
        XCTAssertEqual(logged.map(\.type), [.run])
        XCTAssertEqual(logged.first?.durationMinutes, 30)
        XCTAssertEqual(logged.first?.distanceMeters, 5000)
        XCTAssertEqual(logged.first?.date, CoachFixture.now)
        XCTAssertEqual(status(fixture, proposal), .applied)
        let outcomes = await fixture.coach.outcomes
        XCTAssertEqual(outcomes.map(\.status), [.applied], "the conversation remembers it was applied")

        await fixture.viewModel.undo(try XCTUnwrap(fixture.viewModel.messages.last?.proposals.first), in: message)
        let afterUndo = try await fixture.outsideActivityService.activities(from: nil, to: nil)
        XCTAssertTrue(afterUndo.isEmpty)
        XCTAssertEqual(status(fixture, proposal), .undone)
        let finalOutcomes = await fixture.coach.outcomes
        XCTAssertEqual(finalOutcomes.map(\.status), [.applied, .undone])
    }

    func testAnActivityFromYesterdayIsDatedYesterday() async throws {
        let (fixture, message, proposal) = try await proposing(.outsideActivity(type: .swim, minutes: 45, distanceMeters: nil, day: .yesterday))
        await fixture.viewModel.apply(proposal, in: message)
        let logged = try await fixture.outsideActivityService.activities(from: nil, to: nil)
        let date = try XCTUnwrap(logged.first?.date)
        XCTAssertTrue(Calendar.current.isDate(date, inSameDayAs: CoachFixture.now.addingTimeInterval(-86_400)))
    }

    func testRestingTodayAndTrainingAnywayAreTodaysChoicesAndUndo() async throws {
        let (fixture, message, rest) = try await proposing(.restChoice(.restToday))
        await fixture.viewModel.apply(rest, in: message)
        XCTAssertEqual(fixture.todayChoices.choices(on: CoachFixture.today).rest, .restToday)
        await fixture.viewModel.undo(try XCTUnwrap(fixture.viewModel.messages.last?.proposals.first), in: message)
        XCTAssertNil(fixture.todayChoices.choices(on: CoachFixture.today).rest)

        let (_, anywayMessage, anyway) = try await proposing(.restChoice(.trainAnyway), fixture: fixture)
        await fixture.viewModel.apply(anyway, in: anywayMessage)
        XCTAssertEqual(fixture.todayChoices.choices(on: CoachFixture.today).rest, .trainAnyway)
    }

    func testChangingTodaysLengthIsTodaysChoiceAndUndoes() async throws {
        let (fixture, message, proposal) = try await proposing(.todayLength(minutes: 10))
        await fixture.viewModel.apply(proposal, in: message)
        XCTAssertEqual(fixture.todayChoices.choices(on: CoachFixture.today).minutes, 10)
        await fixture.viewModel.undo(try XCTUnwrap(fixture.viewModel.messages.last?.proposals.first), in: message)
        XCTAssertNil(fixture.todayChoices.choices(on: CoachFixture.today).minutes)
    }

    func testSwappingAMovementIsTodaysChoiceAndUndoes() async throws {
        let (fixture, message, proposal) = try await proposing(.swapMovement(exerciseId: "push_incline", exerciseName: "Incline Push-Up"))
        await fixture.viewModel.apply(proposal, in: message)
        XCTAssertEqual(fixture.todayChoices.choices(on: CoachFixture.today).swappedOut, ["push_incline"])
        await fixture.viewModel.undo(try XCTUnwrap(fixture.viewModel.messages.last?.proposals.first), in: message)
        XCTAssertEqual(fixture.todayChoices.choices(on: CoachFixture.today).swappedOut, [])
    }

    func testSettingFocusAreasSavesTheProfileAndUndoesToThePreviousOnes() async throws {
        var user = MockPersistence.sampleUser
        user.profile.focusAreas = [.chest]
        let (fixture, message, proposal) = try await proposing(.focusAreas([.glutes, .abs]), fixture: CoachFixture(user: user))
        await fixture.viewModel.apply(proposal, in: message)
        let saved = try await fixture.userService.currentUser()?.profile.focusAreas
        XCTAssertEqual(saved, [.abs, .glutes])
        await fixture.viewModel.undo(try XCTUnwrap(fixture.viewModel.messages.last?.proposals.first), in: message)
        let restored = try await fixture.userService.currentUser()?.profile.focusAreas
        XCTAssertEqual(restored, [.chest])
    }

    func testAReminderAsksForPermissionAtFirstScheduleAndUndoes() async throws {
        let (fixture, message, proposal) = try await proposing(.reminder(hour: 7, minute: 30, weekdays: [2, 4, 6]))
        let asked = await fixture.scheduler.permissionRequests
        XCTAssertEqual(asked, 0, "no permission prompt before the user schedules one")

        await fixture.viewModel.apply(proposal, in: message)
        let requests = await fixture.scheduler.permissionRequests
        XCTAssertEqual(requests, 1)
        let pending = await fixture.scheduler.pending
        XCTAssertEqual(pending.values.map(\.weekday).sorted(), [2, 4, 6])
        XCTAssertTrue(pending.values.allSatisfy { $0.hour == 7 && $0.minute == 30 })
        let reminders = await fixture.reminders.reminders()
        XCTAssertEqual(reminders.count, 1)

        await fixture.viewModel.undo(try XCTUnwrap(fixture.viewModel.messages.last?.proposals.first), in: message)
        let afterUndo = await fixture.scheduler.pending
        XCTAssertTrue(afterUndo.isEmpty)
        let remaining = await fixture.reminders.reminders()
        XCTAssertTrue(remaining.isEmpty)
    }

    func testAReminderWithNotificationsOffSaysSoAndChangesNothing() async throws {
        let (fixture, message, proposal) = try await proposing(
            .reminder(hour: 7, minute: 30, weekdays: [2]),
            fixture: CoachFixture(notifications: .denied)
        )
        await fixture.viewModel.apply(proposal, in: message)
        XCTAssertEqual(fixture.viewModel.proposalErrors[proposal.id], CoachReminderCopy.permissionDenied)
        XCTAssertEqual(status(fixture, proposal), .proposed, "still waiting, so the user can try again")
        let reminders = await fixture.reminders.reminders()
        XCTAssertTrue(reminders.isEmpty)
    }

    func testDecliningWritesNothingAndIsRemembered() async throws {
        let (fixture, message, proposal) = try await proposing(.outsideActivity(type: .run, minutes: 30, distanceMeters: nil, day: .today))
        await fixture.viewModel.decline(proposal, in: message)
        XCTAssertEqual(status(fixture, proposal), .declined)
        let logged = try await fixture.outsideActivityService.activities(from: nil, to: nil)
        XCTAssertTrue(logged.isEmpty)
        let outcomes = await fixture.coach.outcomes
        XCTAssertEqual(outcomes.map(\.status), [.declined])
        XCTAssertFalse(fixture.viewModel.canUndo(try XCTUnwrap(fixture.viewModel.messages.last?.proposals.first)))
    }

    /// The closed action set: a de-load, a Return, the cold start, the pace, the phase and the injury
    /// flags have no case, so no proposal can express one (ADR-0005). The switch is exhaustive, so adding
    /// an action fails this test to compile until it is reviewed here.
    func testTheActionSetIsClosedAndHoldsNoSafetyOwnedMove() {
        func kind(_ action: CoachProposal.Action) -> String {
            switch action {
            case .outsideActivity: return "outsideActivity"
            case .restChoice: return "restChoice"
            case .todayLength: return "todayLength"
            case .swapMovement: return "swapMovement"
            case .focusAreas: return "focusAreas"
            case .reminder: return "reminder"
            case .customWorkout: return "customWorkout"
            }
        }
        let every: [CoachProposal.Action] = [
            .outsideActivity(type: .run, minutes: 1, distanceMeters: nil, day: .today), .restChoice(.restToday), .todayLength(minutes: 5),
            .swapMovement(exerciseId: "x", exerciseName: "X"), .focusAreas([]), .reminder(hour: 1, minute: 0, weekdays: [1]),
            .customWorkout(CoachFixture.draft),
        ]
        XCTAssertEqual(every.map(kind), ["outsideActivity", "restChoice", "todayLength", "swapMovement", "focusAreas", "reminder", "customWorkout"])
    }

    func testUnknownProposalKindsFromTheServerAreDroppedNotFatal() throws {
        let json = #"""
        {"id":"m1","role":"coach","text":"Here.","createdAt":1794000000000,"proposals":[
          {"id":"p1","kind":"todayLength","status":"proposed","minutes":10},
          {"id":"p2","kind":"startDeload","status":"proposed"},
          {"id":"p3","kind":"focusAreas","status":"applied","areas":["glutes","abs","tail"]},
          {"id":"p4","kind":"customWorkout","status":"proposed","workout":{"title":"Desk Reset","note":"","steps":[
            {"name":"Incline Push-Up","exerciseId":"push_incline","sets":3,"reps":10,"perSide":false,"restSeconds":30}]}}
        ]}
        """#
        let message = try JSONDecoder().decode(CoachMessage.self, from: Data(json.utf8))
        XCTAssertEqual(message.proposals.map(\.id), ["p1", "p3", "p4"])
        XCTAssertEqual(message.proposals[1].action, .focusAreas([.abs, .glutes]))
        XCTAssertEqual(message.proposals[1].status, .applied)
    }

    // MARK: - Custom Workouts (US-CA04/US-CA05, FR-11)

    func testACustomWorkoutCannotPlayOrBeSavedBeforeItIsAccepted() async throws {
        let (fixture, message, proposal) = try await proposing(.customWorkout(CoachFixture.draft))
        let maybeReviewable = await fixture.viewModel.reviewableWorkout(for: proposal, in: message)
        let reviewable = try XCTUnwrap(maybeReviewable)
        XCTAssertFalse(reviewable.isAccepted)
        let playback = await fixture.viewModel.playback(of: reviewable)
        XCTAssertNil(playback, "nothing plays until it is accepted")
        do {
            try await fixture.customWorkouts.save(reviewable)
            XCTFail("an unaccepted workout must not be saved")
        } catch {}
        let saved = try await fixture.customWorkouts.workouts()
        XCTAssertTrue(saved.isEmpty)
    }

    func testTheEditedWorkoutIsWhatIsAcceptedAndPlayed() async throws {
        let (fixture, message, proposal) = try await proposing(.customWorkout(CoachFixture.draft))
        let maybeEdited = await fixture.viewModel.reviewableWorkout(for: proposal, in: message)
        var edited = try XCTUnwrap(maybeEdited)
        XCTAssertEqual(edited.steps.map(\.exerciseId), ["push_incline", nil], "catalog steps resolve; others stay text only")
        edited.steps.reverse()
        edited.steps[1].reps = 12
        edited.steps[1].sets = 4

        let maybeAccepted = await fixture.viewModel.accept(edited, for: proposal, in: message)
        let accepted = try XCTUnwrap(maybeAccepted)
        XCTAssertTrue(accepted.isAccepted)
        XCTAssertEqual(status(fixture, proposal), .applied)
        let saved = try await fixture.customWorkouts.workouts()
        XCTAssertEqual(saved.first?.steps.map(\.name), ["Doorway Chest Opener", "Incline Push-Up"])
        XCTAssertEqual(saved.first?.proposalId, proposal.id)

        let maybePlayback = await fixture.viewModel.playback(of: accepted)
        let playback = try XCTUnwrap(maybePlayback)
        let stations = playback.playable.blocks.flatMap(\.exercises)
        XCTAssertEqual(stations.map(\.exercise.displayName), ["Doorway Chest Opener", "Incline Push-Up"])
        XCTAssertTrue(CustomWorkout.isTextOnly(exerciseId: stations[0].exercise.id))
        XCTAssertEqual(stations[1].exercise.id, "push_incline", "a catalog step plays as its catalog movement, with its art")
        XCTAssertEqual(stations[1].sets, 4)
        XCTAssertEqual(stations[1].reps, 12)
        XCTAssertNil(playback.playable.trainingDay, "a Custom Workout is never a Training Day")
        XCTAssertTrue(stations.allSatisfy { $0.role == nil }, "no station role, so nothing can read it as progression")

        await fixture.viewModel.undo(try XCTUnwrap(fixture.viewModel.messages.last?.proposals.first), in: message)
        let afterUndo = try await fixture.customWorkouts.workouts()
        XCTAssertTrue(afterUndo.isEmpty)
    }

    func testAPlayedCustomWorkoutCountsLikeAnOutsideActivityAndNeverLogsASession() async throws {
        let library = try await MockExerciseService().exercises()
        var workout = CustomWorkout(draft: CoachFixture.draft, messageId: "m", proposalId: "p", library: library, now: CoachFixture.now)
        workout.acceptedAt = CoachFixture.now
        let activities = InMemoryOutsideActivityService()
        let workouts = InMemoryCustomWorkoutService(workouts: [workout])
        let logs = MockWorkoutLogService()
        let recorder = CustomWorkoutCompletionRecorder(workout: workout, library: library, outsideActivityService: activities, customWorkouts: workouts)
        let log = WorkoutLog(
            id: UUID(), workoutId: UUID(), completedAt: CoachFixture.now, requestedMinutes: 8, durationMinutes: 8,
            shape: .blend, focusPillar: nil, perceivedDifficulty: nil, exercises: []
        )
        try await recorder.recordCompletedSession(log, user: MockPersistence.sampleUser, recentLogs: [])
        try await recorder.recordPerceivedDifficulty(.tooEasy, forLog: log)
        try await recorder.recordEarnedPhase()

        let recorded = try await activities.activities(from: nil, to: nil)
        XCTAssertEqual(recorded.count, 1)
        XCTAssertEqual(recorded.first?.customWorkoutId, workout.id)
        XCTAssertEqual(recorded.first?.customWorkoutTitle, "Desk Reset")
        XCTAssertEqual(recorded.first?.group, .push, "its catalog movements worked Push")
        XCTAssertEqual(recorded.first?.durationMinutes, 8)
        let played = try await workouts.workout(id: workout.id)
        XCTAssertEqual(played?.playedAt, [CoachFixture.now])
        let sessions = try await logs.workoutLogs(from: nil, to: nil)
        XCTAssertTrue(sessions.isEmpty, "a Custom Workout is never a session: no ladder, Earned Reps or Foundation can read it")
    }

    func testAnUnacceptedWorkoutCannotBeRecordedAsPlayed() async throws {
        let library = try await MockExerciseService().exercises()
        let workout = CustomWorkout(draft: CoachFixture.draft, messageId: nil, proposalId: nil, library: library, now: CoachFixture.now)
        let activities = InMemoryOutsideActivityService()
        let recorder = CustomWorkoutCompletionRecorder(workout: workout, library: library, outsideActivityService: activities, customWorkouts: InMemoryCustomWorkoutService())
        let log = WorkoutLog(id: UUID(), workoutId: UUID(), completedAt: CoachFixture.now, requestedMinutes: 8, durationMinutes: 8,
                             shape: .blend, focusPillar: nil, perceivedDifficulty: nil, exercises: [])
        do {
            try await recorder.recordCompletedSession(log, user: MockPersistence.sampleUser, recentLogs: [])
            XCTFail("FR-11: only an accepted Custom Workout is ever played")
        } catch {}
        let recorded = try await activities.activities(from: nil, to: nil)
        XCTAssertTrue(recorded.isEmpty)
    }

    // MARK: - FR-8: the group a Custom Workout gives a day off

    private func workout(_ steps: [(String?, Int)], library: [Exercise]) -> CustomWorkout {
        CustomWorkout(
            id: UUID(), title: "W", note: "",
            steps: steps.map { id, sets in
                CustomWorkoutStep(id: UUID(), name: id ?? "Free step", exerciseId: id, sets: sets, reps: 10, seconds: nil, perSide: false, restSeconds: 30)
            },
            messageId: nil, proposalId: nil, createdAt: CoachFixture.now, acceptedAt: CoachFixture.now
        )
    }

    func testTheGroupWithTheMostCatalogSetsGetsTheDayOff() async throws {
        let library = try await MockExerciseService().exercises()
        XCTAssertEqual(workout([("push_incline", 3), ("squat_bodyweight", 2)], library: library).trainedGroup(library: library), .push)
        XCTAssertEqual(workout([("pull_floor_row", 3), ("hinge_glute_bridge", 4)], library: library).trainedGroup(library: library), .legs)
        XCTAssertEqual(workout([("squat_bodyweight", 2), ("hinge_glute_bridge", 2), ("push_incline", 3)], library: library).trainedGroup(library: library), .legs,
                       "squat and hinge both count toward Legs")
    }

    func testATieCoreMobilityOrTextOnlyStepsNameNoGroup() async throws {
        let library = try await MockExerciseService().exercises()
        XCTAssertNil(workout([("push_incline", 3), ("pull_floor_row", 3)], library: library).trainedGroup(library: library), "an even split names no group")
        XCTAssertNil(workout([("core_dead_bug", 4), ("mobility_cat_cow", 2)], library: library).trainedGroup(library: library))
        XCTAssertNil(workout([(nil, 5)], library: library).trainedGroup(library: library), "text-only steps are never tracked")
    }

    func testAPlayedPushWorkoutGivesPushADayOffAndCompletesNothing() throws {
        let yesterday = CoachFixture.now.addingTimeInterval(-86_400)
        let played = OutsideActivity(type: .other, date: yesterday, durationMinutes: 20, customWorkoutId: UUID(), customWorkoutTitle: "W", customWorkoutGroup: .push)
        XCTAssertEqual(TrainingRotation.plan(logs: [], activities: [], asOf: CoachFixture.now), .train(.push))
        XCTAssertEqual(TrainingRotation.plan(logs: [], activities: [played], asOf: CoachFixture.now), .train(.pull),
                       "Push, worked by the Custom Workout, waits a day")
        let state = TrainingRotation.state(logs: [], activities: [played], asOf: CoachFixture.now)
        XCTAssertTrue(state.completed.isEmpty, "it never completes a group")
        let ungrouped = OutsideActivity(type: .other, date: yesterday, durationMinutes: 20, customWorkoutId: UUID(), customWorkoutGroup: nil)
        XCTAssertEqual(TrainingRotation.plan(logs: [], activities: [ungrouped], asOf: CoachFixture.now), .train(.push))
    }

    // MARK: - US-AC08: injury routing stays an offer

    func testAnInjuryMessageRaisesAnOfferAndWritesNothing() async throws {
        var user = MockPersistence.sampleUser
        user.profile.injuries = []
        let fixture = CoachFixture(user: user)
        await fixture.viewModel.load()
        fixture.viewModel.draft = "my knee hurts on squats"
        await fixture.viewModel.send()
        XCTAssertEqual(fixture.viewModel.injuryRoutingOffer?.area, .knees)
        let injuries = try await fixture.userService.currentUser()?.profile.injuries
        XCTAssertEqual(injuries, [])
        fixture.viewModel.declineInjuryRoutingOffer()
        XCTAssertNil(fixture.viewModel.injuryRoutingOffer)
    }

    func testAnAlreadyFlaggedAreaRaisesNoOffer() async {
        var user = MockPersistence.sampleUser
        user.profile.injuries = ["knees"]
        let fixture = CoachFixture(user: user)
        await fixture.viewModel.load()
        fixture.viewModel.draft = "my knee hurts on squats"
        await fixture.viewModel.send()
        XCTAssertNil(fixture.viewModel.injuryRoutingOffer)
    }
}
