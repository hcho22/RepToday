import XCTest
@testable import RepToday

/// US-AC07 unit coverage: the pieces that turn a coach request into a bounded, clamped, preference-only
/// `SessionPolicy` write - the closed proposal, the on-device intent mapper, the `SessionPolicy` overlay
/// seams, the honest coach note, and the `CoachSessionPolicyService` orchestration.
///
/// The two-writer safety *integration* (a deterministic de-load surviving a coach write, end-to-end through
/// the store and the engine) lives in `CoachPolicyWritePolicyTests`; this suite pins the units those proofs
/// rest on.
@MainActor
final class CoachPolicyWriteTests: XCTestCase {

    // MARK: - Fixtures

    private let asOf = Date(timeIntervalSinceReferenceDate: 700_000_000)

    private func user(id: String = "u1") -> User {
        User(
            id: id,
            displayName: "Test",
            createdAt: asOf,
            profile: UserProfile(
                age: 35, sex: .other, heightCm: 175, weightKg: 75,
                fitnessLevel: .intermediate, primaryGoal: .stayActive,
                sitsLong: false, injuries: [], typicalAvailableMinutes: 15
            ),
            phase: .discipline,
            subscription: Subscription(tier: .premium, provider: .apple, expiresAt: nil, trialEndsAt: nil),
            consistency: Consistency(
                weeklyGoal: 3, score: 50, workoutsThisWeek: 1,
                longestChain: 0, totalWorkoutsCompleted: 0, totalMinutesExercised: 0
            )
        )
    }

    private func service(seed: SessionPolicy? = nil) -> (CoachSessionPolicyService, InMemorySessionPolicyStore) {
        let store: InMemorySessionPolicyStore
        if let seed {
            store = InMemorySessionPolicyStore(policies: ["u1": seed])
        } else {
            store = InMemorySessionPolicyStore()
        }
        return (CoachSessionPolicyService(store: store), store)
    }

    // MARK: - CoachPolicyProposal shape

    func testEmptyProposalIsEmpty() {
        XCTAssertTrue(CoachPolicyProposal().isEmpty)
        XCTAssertFalse(CoachPolicyProposal(patternEmphasis: [.push: 1.5]).isEmpty)
        XCTAssertFalse(CoachPolicyProposal(easedProgressionRate: 0.7).isEmpty)
        XCTAssertFalse(CoachPolicyProposal(narrowedVarietyWindow: 2).isEmpty)
    }

    // MARK: - Variety-window rail + narrowing seam (mirrors the US-AC06 rate seam)

    func testClampedVarietyWindowPinsToRail() {
        XCTAssertEqual(SessionPolicy.clampedVarietyWindow(0), SessionPolicy.minVarietyWindow)
        XCTAssertEqual(SessionPolicy.clampedVarietyWindow(-5), SessionPolicy.minVarietyWindow)
        XCTAssertEqual(SessionPolicy.clampedVarietyWindow(99), SessionPolicy.maxVarietyWindow)
        XCTAssertEqual(SessionPolicy.clampedVarietyWindow(3), 3)
    }

    func testEasingVarietyWindowNarrowsOnlyAndStampsLLM() {
        var policy = SessionPolicy.default
        policy.varietyWindow = 4
        policy.updatedBy = .deterministic

        // Narrows toward a lower proposed window.
        let narrowed = policy.easingVarietyWindow(towardCoachProposed: 2)
        XCTAssertEqual(narrowed.varietyWindow, 2)
        XCTAssertEqual(narrowed.updatedBy, .llm)

        // A widen attempt (above the in-force value, and above the rail) can never raise it.
        for attempt in [5, 6, 99] {
            let widened = policy.easingVarietyWindow(towardCoachProposed: attempt)
            XCTAssertLessThanOrEqual(widened.varietyWindow, policy.varietyWindow,
                "attempt \(attempt): a coach window write must never widen beyond the in-force window")
            XCTAssertEqual(widened.varietyWindow, 4, "a widen attempt leaves the window unchanged")
        }
    }

    // MARK: - applyingCoachProposal overlay (clamp + direction safety)

    func testOverlayClampsEmphasisAndLeavesAbsentPatternsUntouched() {
        var current = SessionPolicy.default
        current.patternEmphasis[.squat] = 1.3 // an existing non-neutral emphasis on a pattern we don't touch

        let overlaid = current.applyingCoachProposal(
            CoachPolicyProposal(patternEmphasis: [.push: 99.0, .hinge: -4.0])
        )
        XCTAssertEqual(overlaid.patternEmphasis[.push], SessionPolicy.maxEmphasis, "out-of-range high emphasis is clamped")
        XCTAssertEqual(overlaid.patternEmphasis[.hinge], SessionPolicy.minEmphasis, "out-of-range low emphasis is clamped")
        XCTAssertEqual(overlaid.patternEmphasis[.squat], 1.3, "an unmentioned pattern keeps its current emphasis (overlay, not replace)")
    }

    func testOverlayEasesRateDownOnlyAndNarrowsWindowOnly() {
        var current = SessionPolicy.default
        current.progressionRate = 1.4
        current.varietyWindow = 4

        // Ask to raise pace and widen the window; both must be refused (ease/narrow only).
        let overlaid = current.applyingCoachProposal(
            CoachPolicyProposal(easedProgressionRate: 2.0, narrowedVarietyWindow: 6)
        )
        XCTAssertEqual(overlaid.progressionRate, 1.4, "a raise attempt never lifts pace above the in-force rate")
        XCTAssertEqual(overlaid.varietyWindow, 4, "a widen attempt never opens the window past the in-force value")

        // Ask to lower/narrow; both take effect (still clamped to the rails).
        let eased = current.applyingCoachProposal(
            CoachPolicyProposal(easedProgressionRate: 0.1, narrowedVarietyWindow: 0)
        )
        XCTAssertEqual(eased.progressionRate, SessionPolicy.minProgressionRate)
        XCTAssertEqual(eased.varietyWindow, SessionPolicy.minVarietyWindow)
    }

    func testCoachLeversDifferIgnoresProvenance() {
        var a = SessionPolicy.default
        var b = SessionPolicy.default
        b.updatedBy = .llm
        b.version = 9
        XCTAssertFalse(a.coachLeversDiffer(from: b), "only the three preference levers count, not version/provenance")
        b.patternEmphasis[.push] = 1.5
        XCTAssertTrue(a.coachLeversDiffer(from: b))
        a = SessionPolicy.default
        b = SessionPolicy.default
        b.varietyWindow = 2
        XCTAssertTrue(a.coachLeversDiffer(from: b))
    }

    // MARK: - PolicyNote.coachTemplated (honest, only names real moves)

    func testCoachNoteNamesRaisedPatternAndReturnsNilWhenNothingMoved() {
        var before = SessionPolicy.default
        var after = SessionPolicy.default
        after.patternEmphasis[.push] = 1.6

        let note = PolicyNote.coachTemplated(policyBefore: before, policyAfter: after)
        XCTAssertNotNil(note)
        XCTAssertEqual(note?.source, .template)
        XCTAssertTrue(note!.text.lowercased().contains("push"), "the note names the pattern that actually moved")
        XCTAssertTrue(note!.text.lowercased().contains("focus"), "an emphasized pattern reads as a focus")

        before = SessionPolicy.default
        after = SessionPolicy.default
        XCTAssertNil(PolicyNote.coachTemplated(policyBefore: before, policyAfter: after),
            "no move -> no note, so the write path can treat nil as 'nothing changed'")
    }

    func testCoachNoteNamesEasingButNeverAStepUp() {
        var before = SessionPolicy.default
        before.progressionRate = 1.4
        before.varietyWindow = 4
        var after = before
        after.progressionRate = 1.0
        after.varietyWindow = 2

        let note = PolicyNote.coachTemplated(policyBefore: before, policyAfter: after)!
        XCTAssertTrue(note.text.lowercased().contains("eased"), "an easing move is named")
        XCTAssertFalse(note.text.lowercased().contains("stepped up"), "a coach note never claims a step-up")
    }

    func testCoachNoteNamesLoweredPattern() {
        var before = SessionPolicy.default
        var after = SessionPolicy.default
        after.patternEmphasis[.squat] = 0.6
        let note = PolicyNote.coachTemplated(policyBefore: before, policyAfter: after)!
        XCTAssertTrue(note.text.lowercased().contains("less squat"), "a de-emphasized pattern reads as 'less'")
    }

    // MARK: - CoachIntentMapper (message -> proposal)

    func testMapperFocusRaisesNamedPattern() {
        let proposal = CoachIntentMapper.proposal(for: "Can you focus my push for a while?")
        XCTAssertNotNil(proposal)
        XCTAssertGreaterThan(proposal!.patternEmphasis[.push] ?? 0, SessionPolicy.neutralEmphasis)
        XCTAssertNil(proposal!.easedProgressionRate)
    }

    func testMapperBoredLowersNamedPattern() {
        let proposal = CoachIntentMapper.proposal(for: "I'm bored of squats.")!
        XCTAssertLessThan(proposal.patternEmphasis[.squat] ?? 2, SessionPolicy.neutralEmphasis)
    }

    func testMapperEaseAndNarrow() {
        XCTAssertEqual(CoachIntentMapper.proposal(for: "take it easier please")?.easedProgressionRate,
                       SessionPolicy.minProgressionRate)
        XCTAssertEqual(CoachIntentMapper.proposal(for: "keep me on moves I know")?.narrowedVarietyWindow,
                       SessionPolicy.minVarietyWindow)
    }

    func testMapperIsConservativeOnNonTuningQuestions() {
        // Mentions a pattern but is a form question, not a tuning request.
        XCTAssertNil(CoachIntentMapper.proposal(for: "How do I do a pistol squat?"))
        // Mentions difficulty but is not an ease request.
        XCTAssertNil(CoachIntentMapper.proposal(for: "Why is this push-up so hard?"))
        XCTAssertNil(CoachIntentMapper.proposal(for: "Why this workout today?"))
    }

    func testMapperMatchesPatternsOnWordBoundariesNotSubstrings() {
        // "score" contains "core", "absolutely" contains "abs", "impression" contains "press" - none
        // should read as a pattern mention, so a "more"/"less" cue alongside them tunes nothing.
        XCTAssertNil(CoachIntentMapper.proposal(for: "I scored more reps than ever today."))
        XCTAssertNil(CoachIntentMapper.proposal(for: "I absolutely want more of this."))
        XCTAssertNil(CoachIntentMapper.proposal(for: "That workout made less of an impression."))
    }

    func testMapperMatchesEverydayPlurals() {
        // Whole-word matching still allows common inflections.
        XCTAssertLessThan(CoachIntentMapper.proposal(for: "I'm bored of squats.")?.patternEmphasis[.squat] ?? 2,
                          SessionPolicy.neutralEmphasis)
        XCTAssertGreaterThan(CoachIntentMapper.proposal(for: "focus more on pressing")?.patternEmphasis[.push] ?? 0,
                             SessionPolicy.neutralEmphasis)
    }

    func testMapperScopesDirectionPerNamedPattern() throws {
        // A mixed request honors each pattern's own nearest cue, not one global more-wins direction.
        let proposal = try XCTUnwrap(CoachIntentMapper.proposal(for: "more push but less core"))
        XCTAssertGreaterThan(proposal.patternEmphasis[.push] ?? 0, SessionPolicy.neutralEmphasis)
        XCTAssertLessThan(proposal.patternEmphasis[.core] ?? 2, SessionPolicy.neutralEmphasis)
    }

    func testMapperMultiWordLessPhrasesDoNotDeemphasizeANearbyPattern() {
        // The bare "less " emphasis cue is a substring of "less variety" / "less intense"; a request to
        // reduce variety or intensity must not silently de-emphasize a pattern it merely names nearby.
        let variety = CoachIntentMapper.proposal(for: "keep push but less variety")
        XCTAssertNil(variety?.patternEmphasis[.push], "'less variety' never lowers a nearby-named pattern")
        XCTAssertEqual(variety?.narrowedVarietyWindow, SessionPolicy.minVarietyWindow,
                       "the request is read as its real intent: narrow the variety window")

        let intense = CoachIntentMapper.proposal(for: "keep push but less intense")
        XCTAssertNil(intense?.patternEmphasis[.push], "'less intense' never lowers a nearby-named pattern")
        XCTAssertEqual(intense?.easedProgressionRate, SessionPolicy.minProgressionRate,
                       "the request is read as its real intent: ease pace")

        // A genuine bare "less <pattern>" still de-emphasizes, so the phrase consumption is not overbroad.
        XCTAssertLessThan(CoachIntentMapper.proposal(for: "less push please")?.patternEmphasis[.push] ?? 2,
                          SessionPolicy.neutralEmphasis)
    }

    func testServiceNeutralEmphasisKeyIsAPhantomWriteAndPersistsNothing() async throws {
        // A proposal that only adds a neutral (1.0) emphasis key for a pattern the in-force policy did not
        // carry moves no lever the user would notice: the raw dictionary gains a key (so `coachLeversDiffer`
        // is true), but the honest note is nil, so the service must write nothing rather than bump the
        // version on a phantom change.
        var seed = SessionPolicy.default
        seed.patternEmphasis = [.squat: 1.2] // push deliberately absent
        seed.version = 7
        let (service, store) = service(seed: seed)

        let written = try await service.applyProposal(
            CoachPolicyProposal(patternEmphasis: [.push: SessionPolicy.neutralEmphasis]),
            for: user(), asOf: asOf
        )
        XCTAssertNil(written, "a neutral no-op emphasis key produces no note, so nothing is written")
        let stored = try await store.policy(for: "u1")
        XCTAssertEqual(stored?.version, 7, "no phantom version bump was persisted")
    }

    // MARK: - CoachSessionPolicyService orchestration

    func testServiceAppliesEmphasisWriteWithProvenanceAndNote() async throws {
        let (service, store) = service()
        let written = try await service.applyProposal(
            CoachPolicyProposal(patternEmphasis: [.push: 1.6]), for: user(), asOf: asOf
        )
        let policy = try XCTUnwrap(written)
        XCTAssertEqual(policy.updatedBy, .llm)
        XCTAssertEqual(policy.version, SessionPolicy.default.version + 1)
        XCTAssertEqual(policy.updatedAt, asOf, "stamps the injected clock, never the wall clock")
        XCTAssertEqual(policy.patternEmphasis[.push], 1.6)
        XCTAssertNotNil(policy.note)
        // Persisted through the shared store.
        let stored = try await store.policy(for: "u1")
        XCTAssertEqual(stored, policy)
    }

    func testServiceNoOpProposalWritesNothing() async throws {
        // Seed a policy already at the value the proposal asks for -> nothing moves.
        var seed = SessionPolicy.default
        seed.patternEmphasis[.push] = SessionPolicy.maxEmphasis
        seed.version = 7
        let (service, store) = service(seed: seed)

        // Propose an out-of-range value that clamps to exactly the in-force value.
        let written = try await service.applyProposal(
            CoachPolicyProposal(patternEmphasis: [.push: 99.0]), for: user(), asOf: asOf
        )
        XCTAssertNil(written, "a clamped no-op writes nothing")
        let stored = try await store.policy(for: "u1")
        XCTAssertEqual(stored?.version, 7, "the in-force policy is untouched")
    }

    func testServiceRaiseAttemptIsClampedNeverApplied() async throws {
        var seed = SessionPolicy.default
        seed.progressionRate = 1.2
        seed.updatedBy = .deterministic
        let (service, _) = service(seed: seed)

        let written = try await service.applyProposal(
            CoachPolicyProposal(easedProgressionRate: 2.0), for: user(), asOf: asOf
        )
        XCTAssertNil(written, "a pure raise attempt moves no lever, so it writes nothing (never raises pace)")
    }
}
