import CoreData
import XCTest
@testable import RepToday

/// US-AU03 local-first sync, end to end over a real (in-memory) Core Data stack and a backend with
/// the account's rules (`FakeAccountServer`): every write lands in the outbox in the same save, uploads
/// are idempotent by record id, an interruption anywhere loses and duplicates nothing, pulled records
/// are never echoed back, and a session generates, plays and logs with no connection at all.
final class LocalFirstSyncTests: XCTestCase {

    // MARK: - The outbox

    func testEveryWriteIsQueuedInTheSameSaveAndCoalescedPerRecord() async throws {
        let stack = SyncTestStack()
        let user = SyncFixtures.user()
        let log = SyncFixtures.log(daysAgo: 1)
        let activity = SyncFixtures.activity(daysAgo: 2)

        try await stack.users.save(user)
        try await stack.users.save(user)
        try await stack.logs.save(log)
        try await stack.activities.save(activity)
        try await stack.policies.save(.default, for: user.id)

        let outbox = try await stack.outbox()
        XCTAssertEqual(outbox, [
            "outsideActivity:\(activity.id.uuidString)",
            "profile:\(user.id)",
            "sessionPolicy:\(user.id)",
            "workoutLog:\(log.id.uuidString)",
        ], "one entry per changed record, however many times it changed")
    }

    func testTheOutboxLivesInTheOnDeviceStore() throws {
        let model = try XCTUnwrap(PersistenceController.modelVersion(named: "RepToday 3"))
        XCTAssertTrue(try XCTUnwrap(model.entities(forConfigurationName: "Local")).contains { $0.name == "CDSyncChange" })
        XCTAssertFalse(try XCTUnwrap(model.entities(forConfigurationName: "Cloud")).contains { $0.name == "CDSyncChange" },
                       "the outbox must never mirror to iCloud while a migration still reads it")
    }

    func testAPhaseAdvanceAndADeletionAreQueuedToo() async throws {
        let stack = SyncTestStack()
        let user = SyncFixtures.user()
        try await stack.users.save(user)
        let log = SyncFixtures.log(daysAgo: 1)
        try await stack.logs.save(log)
        let server = FakeAccountServer()
        try await stack.engine(server).sync()

        try await stack.users.advancePhase(to: .strength, for: user.id)
        try await stack.logs.deleteLog(id: log.id)
        let outbox = try await stack.outbox()
        XCTAssertEqual(outbox, ["profile:\(user.id)", "workoutLog:\(log.id.uuidString)"])

        try await stack.engine(server).sync()
        let deleted = await server.row(.workoutLog, recordId: log.id.uuidString)
        XCTAssertEqual(deleted?.content, .deleted, "a deleted log reaches the account as a deletion")
        let profile = await server.row(.profile, recordId: user.id)
        guard case .profile(let payload, _)? = profile?.content else { return XCTFail("profile missing") }
        XCTAssertEqual(try SyncPayloadCoder.decode(User.self, from: payload).phase, .strength)
    }

    func testAccountDeletionWipesRecordNothingInTheOutbox() async throws {
        let stack = SyncTestStack()
        try await stack.store.clearOutbox()
        try await stack.logs.deleteAllLogs()
        try await stack.activities.deleteAll()
        try await stack.policies.deleteAll()
        try await stack.users.deleteCurrentUser()
        let outbox = try await stack.outbox()
        XCTAssertEqual(outbox, [], "account deletion removes server data itself; nothing is queued")
    }

    /// The account recognises a replayed upload by comparing payloads, so equal records must encode
    /// to the same string. A policy's enum-keyed maps used to come out in hash order.
    func testEqualPoliciesEncodeTheSameAndOldEncodingsStillDecode() throws {
        var forward = SessionPolicy.default
        forward.patternEmphasis = [:]
        for pattern in MovementPattern.allCases { forward.patternEmphasis[pattern] = 1.0 }
        var backward = SessionPolicy.default
        backward.patternEmphasis = [:]
        for pattern in MovementPattern.allCases.reversed() { backward.patternEmphasis[pattern] = 1.0 }
        XCTAssertEqual(forward, backward)
        XCTAssertEqual(try SyncPayloadCoder.encode(forward), try SyncPayloadCoder.encode(backward))

        // A policy stored by an earlier build (the same flat array, in whatever order) still decodes.
        let stored = try PersistenceCoder.encoder.encode(forward)
        XCTAssertEqual(try PersistenceCoder.decoder.decode(SessionPolicy.self, from: stored), forward)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: stored) as? [String: Any])
        let pairs = try XCTUnwrap(json["patternEmphasis"] as? [Any])
        let shuffled = stride(from: 0, to: pairs.count, by: 2).reversed().flatMap { [pairs[$0], pairs[$0 + 1]] }
        json["patternEmphasis"] = shuffled
        let reordered = try JSONSerialization.data(withJSONObject: json)
        XCTAssertEqual(try PersistenceCoder.decoder.decode(SessionPolicy.self, from: reordered), forward)
    }

    // MARK: - Upload

    func testSyncUploadsEverythingAndEmptiesTheOutbox() async throws {
        let stack = SyncTestStack()
        let user = SyncFixtures.user()
        try await stack.users.save(user)
        try await stack.policies.save(.default, for: user.id)
        let logs = (1...3).map { SyncFixtures.log(daysAgo: $0) }
        for log in logs { try await stack.logs.save(log) }
        try await stack.activities.save(SyncFixtures.activity(daysAgo: 1))
        let server = FakeAccountServer()

        let report = try await stack.engine(server).sync()

        XCTAssertEqual(report.uploaded, 6)
        XCTAssertEqual(report.pending, 0)
        let outbox = try await stack.outbox()
        XCTAssertEqual(outbox, [])
        let serverLogs = await server.rows(of: .workoutLog)
        XCTAssertEqual(Set(serverLogs.map(\.recordId)), Set(logs.map(\.id.uuidString)))
        let profile = await server.row(.profile, recordId: user.id)
        guard case .profile(let payload, let focusAreas)? = profile?.content else { return XCTFail("profile missing") }
        XCTAssertEqual(try SyncPayloadCoder.decode(User.self, from: payload), user)
        XCTAssertEqual(focusAreas, user.profile.focusAreas.map(\.rawValue))
    }

    func testAnUploadInBatchesThatIsInterruptedResumesWithNothingLostOrDuplicated() async throws {
        let stack = SyncTestStack()
        let logs = (1...7).map { SyncFixtures.log(daysAgo: $0) }
        for log in logs { try await stack.logs.save(log) }
        let server = FakeAccountServer()
        await server.failPush(call: 2, with: .unreachable)

        do {
            try await stack.engine(server, pushBatchSize: 3).sync()
            XCTFail("the second batch was meant to fail")
        } catch {
            XCTAssertEqual(error as? SyncRemoteError, .unreachable)
        }
        let afterFailure = try await stack.outbox()
        XCTAssertEqual(afterFailure.count, 4, "the first batch settled; the rest stay queued")

        try await stack.engine(server, pushBatchSize: 3).sync()
        let afterResume = try await stack.outbox()
        XCTAssertEqual(afterResume, [])
        let serverLogs = await server.rows(of: .workoutLog)
        XCTAssertEqual(serverLogs.count, 7)
        XCTAssertEqual(Set(serverLogs.map(\.recordId)), Set(logs.map(\.id.uuidString)))
    }

    func testAReplayedUploadChangesNothingOnTheAccount() async throws {
        let stack = SyncTestStack()
        let log = SyncFixtures.log(daysAgo: 1)
        try await stack.logs.save(log)
        let server = FakeAccountServer()
        // The upload reached the account but the device never heard back: the entry is still queued.
        let pending = try await stack.store.pendingChanges(limit: 10)
        try await server.push(pending)
        let firstWrites = await server.appliedWrites

        try await stack.engine(server).sync()

        let writes = await server.appliedWrites
        XCTAssertEqual(firstWrites, 1)
        XCTAssertEqual(writes, 1, "the replay is recognised as unchanged and writes nothing")
        let rows = await server.rows(of: .workoutLog)
        XCTAssertEqual(rows.count, 1)
    }

    func testAnEditDuringAnUploadIsUploadedToo() async throws {
        let stack = SyncTestStack()
        var log = SyncFixtures.log(daysAgo: 1)
        try await stack.logs.save(log)
        let server = FakeAccountServer()
        let inFlight = try await stack.store.pendingChanges(limit: 10)

        // The user rates the session while the first upload is on the wire.
        log.perceivedDifficulty = .tooHard
        try await stack.logs.save(log)
        try await server.push(inFlight)
        try await stack.store.acknowledge(inFlight.map { SyncAcknowledgement(type: $0.type, recordId: $0.recordId, revision: $0.revision) })

        let outbox = try await stack.outbox()
        XCTAssertEqual(outbox, ["workoutLog:\(log.id.uuidString)"], "the newer edit is still queued")
        try await stack.engine(server).sync()
        let row = await server.row(.workoutLog, recordId: log.id.uuidString)
        guard case .workoutLog(let payload, _)? = row?.content else { return XCTFail("log missing") }
        XCTAssertEqual(try SyncPayloadCoder.decode(WorkoutLog.self, from: payload).perceivedDifficulty, .tooHard)
    }

    // MARK: - Pull

    func testAPullAppliesAnotherDevicesChangesWithoutQueueingThemBack() async throws {
        let stack = SyncTestStack()
        let server = FakeAccountServer()
        let remoteLog = SyncFixtures.log(daysAgo: 3)
        let remoteActivity = SyncFixtures.activity(daysAgo: 1)
        await server.seed(.workoutLog, recordId: remoteLog.id.uuidString, clientUpdatedAt: SyncFixtures.base,
                          content: .workoutLog(payload: try SyncFixtures.payload(remoteLog), completedAt: remoteLog.completedAt))
        await server.seed(.outsideActivity, recordId: remoteActivity.id.uuidString, clientUpdatedAt: SyncFixtures.base,
                          content: .outsideActivity(payload: try SyncFixtures.payload(remoteActivity), date: remoteActivity.date))

        let report = try await stack.engine(server).sync()

        XCTAssertEqual(report.applied, 2)
        let logs = try await stack.logs.workoutLogs(from: nil, to: nil)
        XCTAssertEqual(logs, [remoteLog])
        let activities = try await stack.activities.activities(from: nil, to: nil)
        XCTAssertEqual(activities, [remoteActivity])
        let outbox = try await stack.outbox()
        XCTAssertEqual(outbox, [], "a pulled record is never echoed back up")
        let pushed = await server.pushedChanges
        XCTAssertEqual(pushed, 0)
    }

    /// The pull after an upload returns the device's own records; they change nothing, so they write
    /// nothing and do not make Today reload.
    func testThisDevicesOwnUploadsComingBackChangeNothing() async throws {
        let stack = SyncTestStack()
        try await stack.users.save(SyncFixtures.user())
        try await stack.policies.save(.default, for: SyncFixtures.user().id)
        try await stack.logs.save(SyncFixtures.log(daysAgo: 1))
        try await stack.activities.save(SyncFixtures.activity(daysAgo: 1))
        let report = try await stack.engine(FakeAccountServer()).sync()
        XCTAssertEqual(report.uploaded, 4)
        XCTAssertEqual(report.applied, 0, "the echo of this device's own uploads is not a change")
    }

    func testAPulledDeletionRemovesTheRecord() async throws {
        let stack = SyncTestStack()
        let log = SyncFixtures.log(daysAgo: 1)
        try await stack.logs.save(log)
        let server = FakeAccountServer()
        try await stack.engine(server).sync()
        await server.seed(.workoutLog, recordId: log.id.uuidString, clientUpdatedAt: SyncFixtures.base.addingTimeInterval(3_600_000), content: .deleted)

        try await stack.engine(server).sync()
        let logs = try await stack.logs.workoutLogs(from: nil, to: nil)
        XCTAssertEqual(logs, [])
    }

    func testAWaitingLocalChangeWinsOverAnOlderPulledOneAndLosesToANewerOne() async throws {
        let stack = SyncTestStack()
        let server = FakeAccountServer()
        var log = SyncFixtures.log(daysAgo: 1)
        log.perceivedDifficulty = .justRight
        try await stack.logs.save(log)
        var older = log
        older.perceivedDifficulty = .tooEasy
        let localPending = try await stack.store.pendingChanges(limit: 1)
        let localTime = try XCTUnwrap(localPending.first?.changedAt)

        // Older than the waiting local change: the local one is kept and uploaded.
        try await stack.store.apply([RemoteSyncRecord(
            type: .workoutLog, recordId: log.id.uuidString, clientUpdatedAt: localTime.addingTimeInterval(-60),
            content: .workoutLog(payload: try SyncFixtures.payload(older), completedAt: older.completedAt)
        )])
        var stored = try await stack.logs.workoutLogs(from: nil, to: nil)
        XCTAssertEqual(stored.first?.perceivedDifficulty, .justRight)

        // Newer than it: the pulled one replaces it and the waiting entry is dropped.
        var newer = log
        newer.perceivedDifficulty = .tooHard
        try await stack.store.apply([RemoteSyncRecord(
            type: .workoutLog, recordId: log.id.uuidString, clientUpdatedAt: localTime.addingTimeInterval(60),
            content: .workoutLog(payload: try SyncFixtures.payload(newer), completedAt: newer.completedAt)
        )])
        stored = try await stack.logs.workoutLogs(from: nil, to: nil)
        XCTAssertEqual(stored.first?.perceivedDifficulty, .tooHard)
        let outbox = try await stack.outbox()
        XCTAssertEqual(outbox, [])
        _ = server
    }

    func testAPulledProfileKeepsTheDevicesUserIdAndNeverGivesBackAnEarnedPhase() async throws {
        let stack = SyncTestStack()
        let local = SyncFixtures.user(id: "this-phone-user", name: "Riley", phase: .strength)
        try await stack.users.save(local)
        try await stack.store.clearOutbox()
        var remote = SyncFixtures.user(id: "other-phone-user", name: "Riley M", phase: .discipline)
        remote.profile.focusAreas = []

        try await stack.store.apply([RemoteSyncRecord(
            type: .profile, recordId: remote.id, clientUpdatedAt: SyncFixtures.base.addingTimeInterval(86_400),
            content: .profile(payload: try SyncFixtures.payload(remote), focusAreas: ["abs", "chest"])
        )])

        let stored = try await stack.users.currentUser()
        XCTAssertEqual(stored?.id, "this-phone-user", "the device's user is never rekeyed")
        XCTAssertEqual(stored?.displayName, "Riley M")
        XCTAssertEqual(stored?.profile.focusAreas, [.chest, .abs], "the account's Focus Areas, in canonical order")
        XCTAssertEqual(stored?.phase, .strength, "an earned phase is never given back")
        let outbox = try await stack.outbox()
        XCTAssertEqual(outbox, ["profile:this-phone-user"], "the kept phase is sent back to the account")
    }

    func testThePullCursorMovesOnlyAfterAPageIsSaved() async throws {
        let stack = SyncTestStack()
        let server = FakeAccountServer()
        let logs = (1...5).map { SyncFixtures.log(daysAgo: $0) }
        for log in logs {
            await server.seed(.workoutLog, recordId: log.id.uuidString, clientUpdatedAt: SyncFixtures.base,
                              content: .workoutLog(payload: try SyncFixtures.payload(log), completedAt: log.completedAt))
        }
        await server.failPull(call: 2, with: .unreachable)
        let cursor = InMemorySyncCursorStore()

        do {
            try await stack.engine(server, cursor: cursor, pullPageSize: 2).sync()
            XCTFail("the second page was meant to fail")
        } catch {}
        XCTAssertEqual(cursor.cursor(), 2, "the first page was saved, then the cursor moved past it")
        let partial = try await stack.logs.workoutLogs(from: nil, to: nil)
        XCTAssertEqual(partial.count, 2)

        try await stack.engine(server, cursor: cursor, pullPageSize: 2).sync()
        let all = try await stack.logs.workoutLogs(from: nil, to: nil)
        XCTAssertEqual(Set(all.map(\.id)), Set(logs.map(\.id)))
        XCTAssertEqual(all.count, 5, "nothing pulled twice")
    }

    func testRestoringFromAnAccountBringsBackItsPlanAndHistory() async throws {
        let stack = SyncTestStack()
        let server = FakeAccountServer()
        let user = SyncFixtures.user(id: "restored-user")
        let log = SyncFixtures.log(daysAgo: 2)
        var policy = SessionPolicy.default
        policy.version = 4
        await server.seed(.profile, recordId: user.id, clientUpdatedAt: SyncFixtures.base,
                          content: .profile(payload: try SyncFixtures.payload(user), focusAreas: user.profile.focusAreas.map(\.rawValue)))
        await server.seed(.sessionPolicy, recordId: user.id, clientUpdatedAt: SyncFixtures.base,
                          content: .sessionPolicy(payload: try SyncFixtures.payload(policy)))
        await server.seed(.workoutLog, recordId: log.id.uuidString, clientUpdatedAt: SyncFixtures.base,
                          content: .workoutLog(payload: try SyncFixtures.payload(log), completedAt: log.completedAt))

        let types = try await stack.engine(server).restoreFromAccount()

        XCTAssertEqual(types, [.profile, .sessionPolicy, .workoutLog])
        let restoredUser = try await stack.users.currentUser()
        XCTAssertEqual(restoredUser, user)
        let restoredPolicy = try await stack.policies.policy(for: user.id)
        XCTAssertEqual(restoredPolicy, policy)
        let restoredLogs = try await stack.logs.workoutLogs(from: nil, to: nil)
        XCTAssertEqual(restoredLogs, [log])
        let outbox = try await stack.outbox()
        XCTAssertEqual(outbox, [])
    }

    /// The reported sequence: signing in to account X during onboarding restores its first page of
    /// logs, the connection drops on the next page, and the user signs in to account Y instead. Y's
    /// new plan must not carry any of X's history.
    func testAnInterruptedRestoreLeavesNothingForTheNextAccount() async throws {
        let stack = SyncTestStack()
        let first = FakeAccountServer()
        let firstUser = SyncFixtures.user(id: "first-user")
        for log in [SyncFixtures.log(daysAgo: 3), SyncFixtures.log(daysAgo: 2)] {
            await first.seed(.workoutLog, recordId: log.id.uuidString, clientUpdatedAt: SyncFixtures.base,
                             content: .workoutLog(payload: try SyncFixtures.payload(log), completedAt: log.completedAt))
        }
        await first.seed(.profile, recordId: firstUser.id, clientUpdatedAt: SyncFixtures.base,
                         content: .profile(payload: try SyncFixtures.payload(firstUser), focusAreas: []))
        await first.failPull(call: 2, with: .unreachable)
        let policies = DeterministicSessionPolicyService(store: stack.policies, exerciseService: try MockExerciseService(), userService: stack.users)
        let accountX = AccountIdentity(userId: "user_x", email: nil, method: .apple)
        let accountY = AccountIdentity(userId: "user_y", email: nil, method: .google)

        let signInToX = OnboardingViewModel(userService: stack.users, sessionPolicyService: policies, accountRestorer: stack.engine(first, pullPageSize: 1))
        do {
            _ = try await signInToX.completeSignIn(as: accountX)
            XCTFail("the restore was interrupted")
        } catch let error as OnboardingViewModel.CompletionError {
            XCTAssertEqual(error, .accountUnreachable)
        }
        let afterFailure = try await stack.logs.workoutLogs(from: nil, to: nil)
        XCTAssertEqual(afterFailure, [], "a failed restore leaves none of X's history behind")

        let signInToY = OnboardingViewModel(
            userService: stack.users,
            sessionPolicyService: policies,
            accountRestorer: stack.engine(FakeAccountServer()),
            userIdentifier: { "second-user" }
        )
        let completion = try await signInToY.completeSignIn(as: accountY)

        XCTAssertEqual(completion, .created)
        let user = try await stack.users.currentUser()
        XCTAssertEqual(user?.id, "second-user")
        let logs = try await stack.logs.workoutLogs(from: nil, to: nil)
        XCTAssertEqual(logs, [], "Y's plan starts with no history from X")
    }

    /// A restore starts from an empty store, so whatever an earlier attempt left (the app closed
    /// mid-restore) never mixes into the account being restored.
    func testARestoreReplacesWhateverAnEarlierAttemptLeft() async throws {
        let stack = SyncTestStack()
        try await stack.users.save(SyncFixtures.user(id: "left-behind"))
        try await stack.logs.save(SyncFixtures.log(daysAgo: 5))
        let server = FakeAccountServer()
        let user = SyncFixtures.user(id: "restored-user")
        await server.seed(.profile, recordId: user.id, clientUpdatedAt: SyncFixtures.base,
                          content: .profile(payload: try SyncFixtures.payload(user), focusAreas: []))

        let types = try await stack.engine(server).restoreFromAccount()

        XCTAssertEqual(types, [.profile])
        let restoredUser = try await stack.users.currentUser()
        XCTAssertEqual(restoredUser?.id, "restored-user")
        let logs = try await stack.logs.workoutLogs(from: nil, to: nil)
        XCTAssertEqual(logs, [])
        let outbox = try await stack.outbox()
        XCTAssertEqual(outbox, [])
    }

    // MARK: - Offline (FR-10)

    /// An airplane-mode session: the session is generated, played and logged with no connection, the
    /// log waits in the outbox, and it reaches the account the moment a connection returns.
    func testASessionGeneratesPlaysAndLogsOfflineThenSyncs() async throws {
        let stack = SyncTestStack()
        let user = SyncFixtures.user()
        try await stack.users.save(user)
        let server = FakeAccountServer()
        try await stack.engine(server).sync()
        await server.setOffline(true)

        let exercises = try MockExerciseService()
        let engine = OnDeviceWorkoutEngine(exerciseService: exercises, now: { SyncFixtures.base })
        let workout = try await engine.generateWorkout(requestedMinutes: 15, user: user, recentLogs: [], sessionPolicy: .default, variation: .none)
        XCTAssertFalse(workout.blocks.isEmpty, "the session generates with no connection")
        let completion = SessionCompletionService(
            workoutLogService: stack.logs,
            userService: stack.users,
            consistencyService: ConsistencyScoreService(),
            phaseService: PhaseEvaluatorService(exerciseService: exercises),
            policyStore: stack.policies
        )
        let log = WorkoutLog(
            id: UUID(), workoutId: workout.id, completedAt: SyncFixtures.base, requestedMinutes: 15, durationMinutes: 15,
            wasReturn: false, shape: workout.shape, focusPillar: nil, perceivedDifficulty: nil,
            exercises: workout.blocks.flatMap(\.exercises).map {
                LoggedExercise(id: UUID(), exerciseId: $0.exercise.id, pillar: $0.exercise.pillar,
                               movementPattern: $0.exercise.movementPattern,
                               completedSets: [CompletedSet(reps: 10, durationSeconds: nil)], skipped: false)
            }
        )
        try await completion.recordCompletedSession(log, user: user, recentLogs: [])
        let logged = try await stack.logs.workoutLogs(from: nil, to: nil)
        XCTAssertEqual(logged.map(\.id), [log.id], "the session logs with no connection")

        do {
            try await stack.engine(server).sync()
            XCTFail("offline sync should fail")
        } catch {
            XCTAssertEqual(error as? SyncRemoteError, .unreachable)
        }
        let waiting = try await stack.outbox()
        XCTAssertTrue(waiting.contains("workoutLog:\(log.id.uuidString)"), "the log waits on the phone")

        await server.setOffline(false)
        try await stack.engine(server).sync()
        let uploaded = await server.row(.workoutLog, recordId: log.id.uuidString)
        XCTAssertNotNil(uploaded, "the log reaches the account once online")
        let after = try await stack.outbox()
        XCTAssertEqual(after, [])
    }
}
