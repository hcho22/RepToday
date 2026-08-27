import XCTest
@testable import RepToday

/// US-AC07: **the coach tunes programming with two-writer safety.** The premium coach can turn an
/// eligible request into a bounded, clamped, preference-only `SessionPolicy` write tagged `.llm`, applied
/// on the next open through the same `SessionPolicyStore` the deterministic Programmer uses - and the
/// deterministic Programmer's safety moves stay sovereign: a coach write can never clobber a de-load.
///
/// This suite proves the merge rule (safety > preference, ADR-0005) *end-to-end through the two real
/// writers and the shared store*, and threads the resulting emphasis through Step 3's ordering
/// (`PatternFocus`) so the write demonstrably reaches the session. `CoachPolicyWriteTests` pins the
/// units (mapper, seams, note, service no-op/clamp); this is the PRD Validation Test.
///
/// Coverage mirrors the PRD acceptance criteria and Validation Test:
///   (a) a coach "focus my push" write **increases push emphasis, is named in the note**, and makes Step 3
///       lead with push where a neutral policy would not;
///   (b) a deterministic plateau **de-load survives a subsequent coach write** (both orders), because the
///       coach overlays only disjoint / only-downward levers onto the freshest in-force policy;
///   (c) **no out-of-range value is ever applied** - a hostile proposal is clamped to the rails.
@MainActor
final class CoachPolicyWritePolicyTests: XCTestCase {

    // MARK: - Fixtures

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private var asOf: Date {
        calendar.date(from: DateComponents(year: 2026, month: 6, day: 29, hour: 12))!
    }

    private func day(_ n: Int) -> Date { calendar.date(byAdding: .day, value: -n, to: asOf)! }

    private func user(id: String = "u1") -> User {
        User(
            id: id,
            displayName: "Test",
            createdAt: day(30),
            profile: UserProfile(
                age: 35, sex: .other, heightCm: 175, weightKg: 75,
                fitnessLevel: .intermediate, primaryGoal: .stayActive,
                sitsLong: false, injuries: [], typicalAvailableMinutes: 20
            ),
            phase: .discipline,
            subscription: Subscription(tier: .premium, provider: .apple, expiresAt: nil, trialEndsAt: nil),
            consistency: Consistency(
                weeklyGoal: 3, score: 60, workoutsThisWeek: 1,
                longestChain: 0, totalWorkoutsCompleted: 10, totalMinutesExercised: 200
            ),
            duration: User.Duration.seeded(minutes: 20)
        )
    }

    /// A disengaging history (completion falling from full to well short of requested) so the real
    /// deterministic Programmer diagnoses a disengagement and eases as a genuine safety back-off.
    private func disengagingLogs() -> [WorkoutLog] {
        [
            log(minutes: 20, of: 20, daysAgo: 3),
            log(minutes: 12, of: 20, daysAgo: 2),
            log(minutes: 5, of: 20, daysAgo: 1),
        ]
    }

    private func log(minutes: Int, of requested: Int, daysAgo: Int) -> WorkoutLog {
        WorkoutLog(
            id: UUID(), workoutId: UUID(), completedAt: day(daysAgo),
            requestedMinutes: requested, durationMinutes: minutes,
            shape: .singleFocus, focusPillar: .strength, perceivedDifficulty: nil, exercises: []
        )
    }

    private func deterministicService(store: InMemorySessionPolicyStore) -> DeterministicSessionPolicyService {
        // The full validated library; the disengagement de-load path reads completion ratios, not the
        // catalog, so any valid library serves - and this keeps the suite off a private test stub.
        DeterministicSessionPolicyService(
            store: store,
            exerciseService: try! MockExerciseService(),
            userService: MockUserService()
        )
    }

    // MARK: - (a) A coach "focus my push" write applies, is named, and reaches Step 3

    func testValidationFocusPushIncreasesEmphasisAndIsNamedAndLeads() async throws {
        let store = InMemorySessionPolicyStore()
        let coach = CoachSessionPolicyService(store: store)
        let proposal = try XCTUnwrap(CoachIntentMapper.proposal(for: "Focus my push for a while, please."))

        let writtenPolicy = try await coach.applyProposal(proposal, for: user(), asOf: asOf)
        let written = try XCTUnwrap(writtenPolicy)

        // Emphasis increased and provenance is coach-sourced.
        XCTAssertEqual(written.updatedBy, .llm)
        XCTAssertGreaterThan(written.patternEmphasis[.push] ?? 0, SessionPolicy.neutralEmphasis)

        // The note names the real change, in the coach's voice.
        let note = try XCTUnwrap(written.note)
        XCTAssertEqual(note.source, .template)
        XCTAssertTrue(note.text.lowercased().contains("push"), "the note names the pattern that moved")

        // And it reaches Step 3: over a near-tie history (push slightly fresher than squat) a neutral
        // policy leads with squat, but the coach's push emphasis flips the lead to push.
        let candidates: [MovementPattern] = [.push, .squat]
        let history = [
            leadLog(.squat, daysAgo: 4), // squat last done 4 days ago
            leadLog(.push, daysAgo: 3),  // push more recent (fresher) -> squat leads at neutral
        ]
        let neutralLead = PatternFocus.rank(
            candidatePatterns: candidates, recentLogs: history, asOf: asOf, calendar: calendar
        ).first
        let emphasizedLead = PatternFocus.rank(
            candidatePatterns: candidates, recentLogs: history, asOf: asOf, calendar: calendar,
            emphasis: written.patternEmphasis
        ).first
        XCTAssertEqual(neutralLead, .squat, "at neutral emphasis the staler squat leads")
        XCTAssertEqual(emphasizedLead, .push, "the coach's push emphasis flips the Step 3 lead to push")
    }

    // MARK: - (b) A deterministic de-load survives a subsequent coach write

    /// The heart of US-AC07: a real deterministic disengagement de-load lands, then a coach "focus push"
    /// write follows on the same store - and the de-load's eased pace and narrowed window are untouched
    /// (the coach only overlays the disjoint emphasis lever), while the emphasis is applied.
    func testDeterministicDeLoadSurvivesASubsequentCoachEmphasisWrite() async throws {
        let store = InMemorySessionPolicyStore()

        // Writer 1 (safety): the deterministic Programmer diagnoses disengagement and eases.
        let deLoad = try await deterministicService(store: store).reprogram(
            user: user(), recentLogs: disengagingLogs(),
            trigger: ReprogramTrigger(kind: .disengagement, detectedAt: asOf)
        )
        XCTAssertEqual(deLoad.updatedBy, .deterministic)
        XCTAssertLessThan(deLoad.progressionRate, SessionPolicy.default.progressionRate)
        XCTAssertLessThan(deLoad.varietyWindow, SessionPolicy.default.varietyWindow)

        // Writer 2 (preference): a coach emphasis write, re-reading the de-loaded in-force policy.
        let proposal = try XCTUnwrap(CoachIntentMapper.proposal(for: "Focus my push."))
        let afterCoachPolicy = try await CoachSessionPolicyService(store: store).applyProposal(proposal, for: user(), asOf: asOf)
        let afterCoach = try XCTUnwrap(afterCoachPolicy)

        // The safety back-off is preserved exactly - the coach touched neither lever.
        XCTAssertEqual(afterCoach.progressionRate, deLoad.progressionRate, "the de-load's eased pace survives")
        XCTAssertEqual(afterCoach.varietyWindow, deLoad.varietyWindow, "the de-load's narrowed window survives")
        // And the preference landed.
        XCTAssertGreaterThan(afterCoach.patternEmphasis[.push] ?? 0, SessionPolicy.neutralEmphasis)
        XCTAssertEqual(afterCoach.updatedBy, .llm)
        // The persisted in-force policy is the coach's overlay on the de-load, versioned forward.
        let stored = try await store.policy(for: "u1")
        XCTAssertEqual(stored, afterCoach)
        XCTAssertEqual(stored?.version, deLoad.version + 1)
    }

    /// Even a coach *easing* write after a de-load can only ever ease further, never undo it: a coach
    /// "take it easier / keep it familiar" request re-reads the already-eased policy and its clamps cap at
    /// the in-force (de-loaded) values, so pace and window only ever go down, never back up.
    func testCoachEasingAfterDeLoadOnlyGoesFurtherDownNeverUndoes() async throws {
        let store = InMemorySessionPolicyStore()
        let deLoad = try await deterministicService(store: store).reprogram(
            user: user(), recentLogs: disengagingLogs(),
            trigger: ReprogramTrigger(kind: .disengagement, detectedAt: asOf)
        )

        // A coach write that tries to RAISE both (hand-built hostile proposal, above the in-force values).
        let raise = CoachPolicyProposal(easedProgressionRate: 2.0, narrowedVarietyWindow: 6)
        let afterRaise = try await CoachSessionPolicyService(store: store).applyProposal(raise, for: user(), asOf: asOf)
        XCTAssertNil(afterRaise, "a pure raise/widen attempt moves nothing on an already-eased policy - nothing is written")
        let afterRaiseStored = try await store.policy(for: "u1")
        XCTAssertEqual(afterRaiseStored, deLoad, "the de-load is left exactly as-is")

        // A coach ease-further write does apply, and only downward.
        let easeFurther = CoachPolicyProposal(easedProgressionRate: SessionPolicy.minProgressionRate)
        if let afterEase = try await CoachSessionPolicyService(store: store).applyProposal(easeFurther, for: user(), asOf: asOf) {
            XCTAssertLessThanOrEqual(afterEase.progressionRate, deLoad.progressionRate,
                "a coach ease can only lower pace further, never raise it")
        }
    }

    /// The reverse order also holds: a coach emphasis write, then a deterministic de-load. The de-load is
    /// last-writer for its own levers (safety is sovereign), and the coach's disjoint emphasis survives it.
    func testCoachWriteThenDeterministicDeLoadBothSurvive() async throws {
        let store = InMemorySessionPolicyStore()

        let proposal = try XCTUnwrap(CoachIntentMapper.proposal(for: "Focus my push."))
        let afterCoachPolicy = try await CoachSessionPolicyService(store: store).applyProposal(proposal, for: user(), asOf: asOf)
        let afterCoach = try XCTUnwrap(afterCoachPolicy)

        let deLoad = try await deterministicService(store: store).reprogram(
            user: user(), recentLogs: disengagingLogs(),
            trigger: ReprogramTrigger(kind: .disengagement, detectedAt: asOf)
        )
        // The de-load eased pace/window (sovereign) AND preserved the coach's emphasis (disjoint).
        XCTAssertLessThan(deLoad.progressionRate, SessionPolicy.default.progressionRate)
        XCTAssertEqual(deLoad.patternEmphasis[.push], afterCoach.patternEmphasis[.push],
            "a deterministic de-load never disturbs the coach's disjoint emphasis lever")
    }

    // MARK: - (c) No out-of-range value is ever applied

    func testNoOutOfRangeValueEverApplied() async throws {
        let store = InMemorySessionPolicyStore()
        // A hostile proposal: emphasis far past the rail, a negative rate, a huge window.
        let hostile = CoachPolicyProposal(
            patternEmphasis: [.push: 1000.0, .squat: -50.0],
            easedProgressionRate: -9.0,
            narrowedVarietyWindow: 999
        )
        let writtenPolicy = try await CoachSessionPolicyService(store: store).applyProposal(hostile, for: user(), asOf: asOf)
        let written = try XCTUnwrap(writtenPolicy)
        XCTAssertEqual(written.patternEmphasis[.push], SessionPolicy.maxEmphasis)
        XCTAssertEqual(written.patternEmphasis[.squat], SessionPolicy.minEmphasis)
        XCTAssertGreaterThanOrEqual(written.progressionRate, SessionPolicy.minProgressionRate)
        XCTAssertLessThanOrEqual(written.progressionRate, SessionPolicy.maxProgressionRate)
        XCTAssertGreaterThanOrEqual(written.varietyWindow, SessionPolicy.minVarietyWindow)
        XCTAssertLessThanOrEqual(written.varietyWindow, SessionPolicy.maxVarietyWindow)
    }

    // MARK: - Helpers

    private func leadLog(_ pattern: MovementPattern, daysAgo: Int) -> WorkoutLog {
        WorkoutLog(
            id: UUID(), workoutId: UUID(), completedAt: day(daysAgo),
            requestedMinutes: 20, durationMinutes: 20, shape: .singleFocus,
            focusPillar: .strength, perceivedDifficulty: nil,
            exercises: [
                LoggedExercise(
                    id: UUID(), exerciseId: pattern.rawValue, pillar: .strength,
                    movementPattern: pattern,
                    completedSets: [CompletedSet(reps: 10, durationSeconds: nil)], skipped: false
                )
            ]
        )
    }
}
