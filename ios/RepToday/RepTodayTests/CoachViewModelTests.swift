import XCTest
@testable import RepToday

/// Tests US-AC02: the talking coach view model. It drives the send flow over a stub `CoachProxyClient`
/// transport so every decision - the happy path, graceful failure mapping, retry, on-device
/// conversation memory across turns, the send-gating, and the unconfigured "unavailable" state - is
/// exercised without a live proxy, and proves transport failures are non-blocking and retryable,
/// while safety refusals are non-blocking and non-retryable (the "never blocks the core loop" property).
@MainActor
final class CoachViewModelTests: XCTestCase {

    // MARK: - Stub transport

    /// A controllable transport that records the outbound request and returns/throws on command.
    private final class StubTransport: CoachProxyTransport, @unchecked Sendable {
        enum Outcome {
            case success(reply: String, status: Int)
            case safetyRefusal
            case failure(Error)
        }
        var outcome: Outcome
        private(set) var callCount = 0
        private(set) var lastBody: Data?

        init(_ outcome: Outcome) { self.outcome = outcome }

        func post(
            to url: URL,
            jsonBody: Data,
            headers: [String: String],
            timeoutSeconds: Double
        ) async throws -> (data: Data, statusCode: Int) {
            callCount += 1
            lastBody = jsonBody
            switch outcome {
            case let .success(reply, status):
                return (Data(#"{"reply":"\#(reply)"}"#.utf8), status)
            case .safetyRefusal:
                return (Data(#"{"outcome":"safety_refusal"}"#.utf8), 200)
            case let .failure(error):
                throw error
            }
        }
    }

    private struct TransportBoom: Error {}

    private let endpoint = URL(string: "https://proxy.example.com/coach")!

    private func makeViewModel(
        transport: StubTransport,
        user: User? = nil,
        logs: [WorkoutLog] = [],
        consented: Bool = true
    ) -> CoachViewModel {
        let viewModel = CoachViewModel(
            client: CoachProxyClient(
                endpoint: endpoint,
                safetyIdentifier: testCoachSafetyIdentifier,
                transport: transport
            ),
            userService: MockUserService(user: user),
            workoutLogService: MockWorkoutLogService(logs: logs),
            exerciseService: try! MockExerciseService()
        )
        // The US-AC04 data disclosure gates the send path (a fresh coach starts un-consented). These
        // US-AC02 tests exercise the send flow, so consent is granted by default; the consent-gate
        // tests below opt out to prove no send happens before acknowledgement.
        if consented { viewModel.grantDataSharingConsent() }
        return viewModel
    }

    /// A view model with no configured client - the unavailable state.
    private func makeUnavailableViewModel() -> CoachViewModel {
        CoachViewModel(
            client: nil,
            userService: MockUserService(),
            workoutLogService: MockWorkoutLogService(),
            exerciseService: try! MockExerciseService()
        )
    }

    // MARK: - Happy path

    func testSendAppendsUserAndCoachTurnsAndClearsDraft() async {
        let transport = StubTransport(.success(reply: "Because squats were your stalest pattern.", status: 200))
        let viewModel = makeViewModel(transport: transport)

        viewModel.draft = "why squats today?"
        await viewModel.send()

        XCTAssertEqual(viewModel.messages.count, 2)
        XCTAssertEqual(viewModel.messages[0].author, .user)
        XCTAssertEqual(viewModel.messages[0].text, "why squats today?")
        XCTAssertEqual(viewModel.messages[1].author, .coach)
        XCTAssertEqual(viewModel.messages[1].text, "Because squats were your stalest pattern.")
        XCTAssertEqual(viewModel.draft, "", "the input clears once the question is sent")
        XCTAssertFalse(viewModel.isSending, "sending always resolves")
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.canRetry)
        XCTAssertEqual(transport.callCount, 1, "exactly one Coach model call per question")
    }

    func testSendTrimsWhitespaceFromTheQuestion() async {
        let transport = StubTransport(.success(reply: "ok", status: 200))
        let viewModel = makeViewModel(transport: transport)

        viewModel.draft = "   how do I do a pistol squat?  "
        await viewModel.send()

        XCTAssertEqual(viewModel.messages.first?.text, "how do I do a pistol squat?")
    }

    // MARK: - On-device conversation memory across turns

    func testConversationMemoryAccumulatesAcrossTurns() async {
        let transport = StubTransport(.success(reply: "first answer", status: 200))
        let viewModel = makeViewModel(transport: transport)

        viewModel.draft = "first question"
        await viewModel.send()

        transport.outcome = .success(reply: "second answer", status: 200)
        viewModel.draft = "second question"
        await viewModel.send()

        // The transcript is the coach's memory - it lives on-device here, since the transport is
        // stateless per request. Four turns, in order.
        XCTAssertEqual(viewModel.messages.map(\.text),
                       ["first question", "first answer", "second question", "second answer"])
        XCTAssertEqual(transport.callCount, 2)
    }

    // MARK: - Graceful failure (never blocks the core loop)

    func testTransportFailureBecomesRetryableErrorAndNeverHangs() async {
        let transport = StubTransport(.failure(TransportBoom()))
        let viewModel = makeViewModel(transport: transport)

        viewModel.draft = "why squats?"
        await viewModel.send()

        // The user's turn is shown; the coach's is not; a friendly, non-blocking error is set.
        XCTAssertEqual(viewModel.messages.count, 1)
        XCTAssertEqual(viewModel.messages.first?.author, .user)
        XCTAssertFalse(viewModel.isSending, "a failure must resolve isSending, never leave it stuck")
        XCTAssertEqual(viewModel.errorMessage, CoachViewModel.genericFailureMessage)
        XCTAssertTrue(viewModel.canRetry, "the failed question can be retried")
    }

    func testBadStatusMapsToTheGenericNonBlockingError() async {
        let transport = StubTransport(.success(reply: "ignored", status: 500))
        let viewModel = makeViewModel(transport: transport)

        viewModel.draft = "hi"
        await viewModel.send()

        XCTAssertEqual(viewModel.errorMessage, CoachViewModel.genericFailureMessage)
        XCTAssertEqual(viewModel.messages.count, 1)
        XCTAssertTrue(viewModel.canRetry)
    }

    func testSafetyRefusalShowsOwnedMessageWithoutRetry() async {
        let transport = StubTransport(.safetyRefusal)
        let viewModel = makeViewModel(transport: transport)

        viewModel.draft = "unsafe request"
        await viewModel.send()

        XCTAssertEqual(viewModel.messages.map(\.text), ["unsafe request"])
        XCTAssertEqual(viewModel.errorMessage, CoachViewModel.safetyRefusalMessage)
        XCTAssertFalse(viewModel.canRetry)
        XCTAssertFalse(viewModel.isSending)
    }

    func testRetryAfterFailureSendsTheSameQuestionWithoutDuplicatingIt() async {
        let transport = StubTransport(.failure(TransportBoom()))
        let viewModel = makeViewModel(transport: transport)

        viewModel.draft = "why squats?"
        await viewModel.send()
        XCTAssertTrue(viewModel.canRetry)

        // The network recovers; retry resends the same question.
        transport.outcome = .success(reply: "Because they were stalest.", status: 200)
        await viewModel.retryLastMessage()

        // The user's turn is not duplicated; the coach's answer lands; the error clears.
        XCTAssertEqual(viewModel.messages.map(\.author), [.user, .coach])
        XCTAssertEqual(viewModel.messages[0].text, "why squats?")
        XCTAssertEqual(viewModel.messages[1].text, "Because they were stalest.")
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.canRetry)
    }

    // MARK: - Over-length message (recoverable, not a dead-end)

    func testOverLongMessageIsRecoverableAndNotRetryable() async {
        let transport = StubTransport(.success(reply: "ignored", status: 200))
        let viewModel = makeViewModel(transport: transport)

        let tooLong = String(repeating: "a", count: CoachProxyClient.defaultMessageCharacterLimit + 1)
        viewModel.draft = tooLong
        await viewModel.send()

        // The over-long turn is rejected locally, before any network call.
        XCTAssertEqual(transport.callCount, 0, "an over-long message never reaches the transport")
        // The user's text is handed back so they can trim it - the friendly copy is actionable.
        XCTAssertEqual(viewModel.draft, tooLong, "the draft is restored so the user can shorten it")
        // No orphan bubble is left behind, and there is nothing to retry (resending would re-fail).
        XCTAssertTrue(viewModel.messages.isEmpty, "the rejected turn is not orphaned in the transcript")
        XCTAssertNotNil(viewModel.errorMessage, "a friendly, actionable error is shown")
        XCTAssertFalse(viewModel.canRetry, "retrying the identical over-long text would just re-fail")
        XCTAssertFalse(viewModel.isSending, "sending always resolves")
    }

    func testTrimmedOverLongMessageCanBeShortenedAndResent() async {
        let transport = StubTransport(.success(reply: "Here's why.", status: 200))
        let viewModel = makeViewModel(transport: transport)

        viewModel.draft = String(repeating: "a", count: CoachProxyClient.defaultMessageCharacterLimit + 1)
        await viewModel.send()
        XCTAssertFalse(viewModel.canRetry)

        // The user trims the draft and sends again - now it goes through cleanly.
        viewModel.draft = "why squats?"
        await viewModel.send()

        XCTAssertEqual(viewModel.messages.map(\.author), [.user, .coach])
        XCTAssertEqual(viewModel.messages[0].text, "why squats?")
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(transport.callCount, 1)
    }

    // MARK: - Send gating

    func testCanSendGating() async {
        let transport = StubTransport(.success(reply: "ok", status: 200))
        let viewModel = makeViewModel(transport: transport)

        XCTAssertFalse(viewModel.canSend, "empty draft is not sendable")
        viewModel.draft = "   "
        XCTAssertFalse(viewModel.canSend, "whitespace-only draft is not sendable")
        viewModel.draft = "real question"
        XCTAssertTrue(viewModel.canSend)
    }

    func testEmptyDraftSendIsANoOp() async {
        let transport = StubTransport(.success(reply: "ok", status: 200))
        let viewModel = makeViewModel(transport: transport)

        viewModel.draft = "   "
        await viewModel.send()

        XCTAssertTrue(viewModel.messages.isEmpty)
        XCTAssertEqual(transport.callCount, 0, "an empty send never reaches the transport")
    }

    // MARK: - Data-disclosure consent gate (US-AC04)

    /// The safety-critical guarantee: a coach that has not been consented to sends nothing, on any path
    /// - a direct send, a retry, or an available-and-non-empty draft. No message and no context summary
    /// reaches the transport before the user acknowledges the disclosure.
    func testNoSendReachesTheTransportBeforeConsent() async {
        let transport = StubTransport(.success(reply: "should never be delivered", status: 200))
        let viewModel = makeViewModel(transport: transport, consented: false)

        XCTAssertTrue(viewModel.needsDataSharingConsent, "a fresh available coach owes the disclosure")
        XCTAssertFalse(viewModel.canSend, "the send control is disabled until consent is given")

        viewModel.draft = "why squats today?"
        await viewModel.send()

        XCTAssertEqual(transport.callCount, 0, "no request leaves the device before consent")
        XCTAssertTrue(viewModel.messages.isEmpty, "nothing is appended before consent")
        XCTAssertNil(viewModel.errorMessage, "declining is a calm state, not an error")

        // Even a retry path cannot leak: there is nothing pending, and the guard holds regardless.
        await viewModel.retryLastMessage()
        XCTAssertEqual(transport.callCount, 0)
    }

    /// Once consent is granted the very same coach sends normally - consent opens the gate rather than
    /// permanently disabling the surface.
    func testConsentOpensTheSendGate() async {
        let transport = StubTransport(.success(reply: "Because they were your stalest pattern.", status: 200))
        let viewModel = makeViewModel(transport: transport, consented: false)

        viewModel.grantDataSharingConsent()

        XCTAssertFalse(viewModel.needsDataSharingConsent, "consent clears the owed disclosure")
        viewModel.draft = "why squats today?"
        XCTAssertTrue(viewModel.canSend, "the send control is enabled once consent is given")
        await viewModel.send()

        XCTAssertEqual(transport.callCount, 1, "exactly one Coach model call once consented")
        XCTAssertEqual(viewModel.messages.map(\.author), [.user, .coach])
    }

    /// An unavailable (unconfigured) coach never owes the disclosure - there is nothing to send, so it
    /// shows the calm "unavailable" state rather than a consent gate.
    func testUnavailableCoachNeedsNoConsent() {
        let viewModel = makeUnavailableViewModel()
        XCTAssertFalse(viewModel.needsDataSharingConsent, "an unconfigured coach has nothing to disclose")
    }

    // MARK: - Unavailable (unconfigured build)

    func testUnavailableWhenNoClientConfigured() async {
        let viewModel = makeUnavailableViewModel()

        XCTAssertFalse(viewModel.isAvailable)
        XCTAssertFalse(viewModel.canSend)

        viewModel.draft = "why squats?"
        await viewModel.send()

        XCTAssertTrue(viewModel.messages.isEmpty, "an unconfigured coach never sends")
        XCTAssertNil(viewModel.errorMessage, "unavailable is a calm state, not an error")
    }

    // MARK: - Context bundle (grounded in real history)

    func testSendCarriesTheDerivedContextBundleFromRealState() async throws {
        var user = MockPersistence.sampleUser
        user.phase = .discipline
        user.duration = .seeded(minutes: 25)
        let transport = StubTransport(.success(reply: "ok", status: 200))
        let viewModel = makeViewModel(transport: transport, user: user)

        viewModel.draft = "why this workout?"
        await viewModel.send()

        // The outbound body is `{ context: CoachContextBundle, message }`. Decode it and confirm the
        // context reflects the user's real state (phase, the learned Default Duration as requested
        // minutes) - the coach is grounded, not generic.
        let body = try XCTUnwrap(transport.lastBody)
        let decoded = try JSONDecoder().decode(SentRequest.self, from: body)
        XCTAssertEqual(decoded.message, "why this workout?")
        XCTAssertEqual(decoded.context.phase, "discipline")
        XCTAssertEqual(decoded.context.requestedMinutes, 25)
    }

    // MARK: - US-AC07: coach tuning wired into the send path

    /// A view model wired with a real `CoachSessionPolicyService` over an explicit store, so a tuning
    /// send's policy write is observable.
    private func makeTuningViewModel(
        transport: StubTransport,
        store: InMemorySessionPolicyStore,
        user: User
    ) -> CoachViewModel {
        let viewModel = CoachViewModel(
            client: CoachProxyClient(
                endpoint: endpoint,
                safetyIdentifier: testCoachSafetyIdentifier,
                transport: transport
            ),
            userService: MockUserService(user: user),
            workoutLogService: MockWorkoutLogService(),
            exerciseService: try! MockExerciseService(),
            policyService: CoachSessionPolicyService(store: store)
        )
        viewModel.grantDataSharingConsent()
        return viewModel
    }

    /// An eligible tuning message applies a bounded, preference-only policy write (visible in the shared
    /// store) and surfaces the honest coach note as a coach turn - the coach converts the request, not just
    /// talks about it.
    func testTuningRequestAppliesPolicyAndSurfacesNote() async throws {
        var user = MockPersistence.sampleUser
        user.id = "coach-tune-user"
        let store = InMemorySessionPolicyStore()
        let transport = StubTransport(.success(reply: "Push is your focus - here's why it helps.", status: 200))
        let viewModel = makeTuningViewModel(transport: transport, store: store, user: user)

        viewModel.draft = "Focus my push for a while."
        await viewModel.send()

        // The policy was written to the shared store: push emphasized, coach-sourced.
        let storedPolicy = try await store.policy(for: user.id)
        let policy = try XCTUnwrap(storedPolicy)
        XCTAssertEqual(policy.updatedBy, .llm)
        XCTAssertGreaterThan(policy.patternEmphasis[.push] ?? 0, SessionPolicy.neutralEmphasis)

        // The transcript carries the honest note as a coach turn (naming push), alongside the talk reply.
        let coachTexts = viewModel.messages.filter { $0.author == .coach }.map(\.text)
        XCTAssertTrue(coachTexts.contains { $0.lowercased().contains("push") && $0.lowercased().contains("focus") },
            "the honest tuning note is surfaced as a coach turn")
        XCTAssertTrue(coachTexts.contains("Push is your focus - here's why it helps."),
            "the coach still talks in addition to tuning")
    }

    /// A normal (non-tuning) question writes no policy - the coach only tunes on an explicit eligible
    /// request, never silently on a form or why question.
    func testNonTuningRequestWritesNoPolicy() async throws {
        let user = MockPersistence.sampleUser
        let store = InMemorySessionPolicyStore()
        let transport = StubTransport(.success(reply: "Because squats were your stalest pattern.", status: 200))
        let viewModel = makeTuningViewModel(transport: transport, store: store, user: user)

        viewModel.draft = "Why this workout today?"
        await viewModel.send()

        let stored = try await store.policy(for: user.id)
        XCTAssertNil(stored, "a non-tuning question never writes a policy")
        XCTAssertEqual(viewModel.messages.filter { $0.author == .coach }.count, 1, "only the talk reply, no note turn")
    }

    /// With no policy service wired (the default), a tuning message just talks - the tuning is a
    /// best-effort upgrade, never a dependency, and its absence never breaks the send.
    func testTuningWithoutPolicyServiceJustTalks() async {
        let transport = StubTransport(.success(reply: "Here's why push leads today.", status: 200))
        let viewModel = makeViewModel(transport: transport, user: MockPersistence.sampleUser)

        viewModel.draft = "Focus my push."
        await viewModel.send()

        XCTAssertEqual(viewModel.messages.filter { $0.author == .coach }.count, 1)
        XCTAssertNil(viewModel.errorMessage)
    }

    // MARK: - US-AC08: injury signals route, never filter

    /// A view model wired with a real policy store *and* an observable user service, so a health signal
    /// can be checked against both possible silent writes: the policy (US-AC07's path) and the profile's
    /// injury flags.
    private func makeInjuryViewModel(
        transport: StubTransport,
        userService: MockUserService,
        store: InMemorySessionPolicyStore = InMemorySessionPolicyStore()
    ) -> CoachViewModel {
        let viewModel = CoachViewModel(
            client: CoachProxyClient(
                endpoint: endpoint,
                safetyIdentifier: testCoachSafetyIdentifier,
                transport: transport
            ),
            userService: userService,
            workoutLogService: MockWorkoutLogService(),
            exerciseService: try! MockExerciseService(),
            policyService: CoachSessionPolicyService(store: store)
        )
        viewModel.grantDataSharingConsent()
        return viewModel
    }

    private func injuryUser(_ injuries: [String] = []) -> User {
        var user = MockPersistence.sampleUser
        user.id = "coach-injury-user"
        user.profile.injuries = injuries
        return user
    }

    /// The story's core guarantee: an injury message produces a **routing offer** and changes nothing -
    /// not the injury flags, not the policy.
    func testInjuryMessageOffersRoutingAndChangesNothing() async throws {
        let userService = MockUserService(user: injuryUser())
        let store = InMemorySessionPolicyStore()
        let transport = StubTransport(.success(reply: "Knees don't love deep flexion when they're sore.", status: 200))
        let viewModel = makeInjuryViewModel(transport: transport, userService: userService, store: store)

        viewModel.draft = "my knee hurts on squats"
        await viewModel.send()

        XCTAssertEqual(viewModel.injuryRoutingOffer?.area, .knees, "the coach offers to route, naming the area")
        let injuries = try await userService.currentUser()?.profile.injuries
        XCTAssertEqual(injuries, [], "the coach never sets an injury flag")
        let stored = try await store.policy(for: "coach-injury-user")
        XCTAssertNil(stored, "an injury signal is not a policy nudge either - nothing is written")
        XCTAssertEqual(viewModel.messages.filter { $0.author == .coach }.count, 1,
                       "the coach still answers; the offer is a control, not a fabricated turn")
    }

    /// Declining is exactly a no-op: the offer goes away and nothing was, or becomes, changed.
    func testDecliningTheOfferChangesNothing() async throws {
        let userService = MockUserService(user: injuryUser())
        let transport = StubTransport(.success(reply: "Here's some general guidance.", status: 200))
        let viewModel = makeInjuryViewModel(transport: transport, userService: userService)

        viewModel.draft = "my knee hurts on squats"
        await viewModel.send()
        XCTAssertNotNil(viewModel.injuryRoutingOffer)

        viewModel.declineInjuryRoutingOffer()

        XCTAssertNil(viewModel.injuryRoutingOffer, "declining dismisses the offer")
        let injuries = try await userService.currentUser()?.profile.injuries
        XCTAssertEqual(injuries, [], "declining leaves the profile exactly as it was")
    }

    /// Accepting *routes*: it hands the caller an area to navigate to and still writes nothing. The flag
    /// is set in the injury control, by the user, in `InjuryFlagsViewModelTests`.
    func testAcceptingTheOfferRoutesAndStillWritesNothing() async throws {
        let userService = MockUserService(user: injuryUser())
        let transport = StubTransport(.success(reply: "Here's some general guidance.", status: 200))
        let viewModel = makeInjuryViewModel(transport: transport, userService: userService)

        viewModel.draft = "my knee hurts on squats"
        await viewModel.send()

        let routed = viewModel.acceptInjuryRoutingOffer()

        XCTAssertEqual(routed, .knees, "accepting yields the destination of a route")
        XCTAssertNil(viewModel.injuryRoutingOffer, "the offer is consumed")
        let injuries = try await userService.currentUser()?.profile.injuries
        XCTAssertEqual(injuries, [], "accepting the *offer* is not the confirmation - it only navigates")
    }

    /// A form question that mentions a body part never raises the offer, so the surface stays quiet
    /// unless there is something real to flag.
    func testFormQuestionRaisesNoOffer() async {
        let userService = MockUserService(user: injuryUser())
        let transport = StubTransport(.success(reply: "Here's how to do a pistol squat.", status: 200))
        let viewModel = makeInjuryViewModel(transport: transport, userService: userService)

        viewModel.draft = "how do I do a pistol squat?"
        await viewModel.send()

        XCTAssertNil(viewModel.injuryRoutingOffer)
    }

    /// Offering to flag something already flagged would invite the user to confirm a non-change.
    func testAlreadyFlaggedAreaRaisesNoOffer() async {
        let userService = MockUserService(user: injuryUser([InjuryOption.knees.tag]))
        let transport = StubTransport(.success(reply: "Understood - go easy.", status: 200))
        let viewModel = makeInjuryViewModel(transport: transport, userService: userService)

        viewModel.draft = "my knee hurts on squats"
        await viewModel.send()

        XCTAssertNil(viewModel.injuryRoutingOffer, "the area is already protected; there is nothing to offer")
    }

    /// "Already flagged" is asked the *engine's* way. A stored `"Knee"` already contraindicates squats,
    /// so offering to flag it would invite the user to confirm a protection they already have.
    func testAnAreaProtectedUnderADifferentSpellingRaisesNoOffer() async {
        let userService = MockUserService(user: injuryUser(["Knee"]))
        let transport = StubTransport(.success(reply: "Understood - go easy.", status: 200))
        let viewModel = makeInjuryViewModel(transport: transport, userService: userService)

        viewModel.draft = "my knee hurts on squats"
        await viewModel.send()

        XCTAssertTrue(InjuryContraindication.contraindicatedPatterns(for: ["Knee"]).contains(.squat),
                      "precondition: the engine already protects this area")
        XCTAssertNil(viewModel.injuryRoutingOffer, "so the coach does not offer to flag it again")
    }

    /// A failed turn raises no offer - the same rule the tuning path follows, so a message that never
    /// got an answer never leaves a prompt behind.
    func testFailedSendRaisesNoOffer() async {
        let userService = MockUserService(user: injuryUser())
        let transport = StubTransport(.failure(TransportBoom()))
        let viewModel = makeInjuryViewModel(transport: transport, userService: userService)

        viewModel.draft = "my knee hurts on squats"
        await viewModel.send()

        XCTAssertNil(viewModel.injuryRoutingOffer)
        XCTAssertEqual(viewModel.errorMessage, CoachViewModel.genericFailureMessage)
    }

    /// A later question supersedes an un-answered offer rather than leaving it standing under a new
    /// answer. Dropping it changes nothing, since it never set anything.
    func testANewQuestionClearsAStandingOffer() async {
        let userService = MockUserService(user: injuryUser())
        let transport = StubTransport(.success(reply: "General guidance.", status: 200))
        let viewModel = makeInjuryViewModel(transport: transport, userService: userService)

        viewModel.draft = "my knee hurts on squats"
        await viewModel.send()
        XCTAssertNotNil(viewModel.injuryRoutingOffer)

        viewModel.draft = "why this workout today?"
        await viewModel.send()

        XCTAssertNil(viewModel.injuryRoutingOffer)
    }

    /// The minimal shape of what the client sends, for decoding the outbound body in the test above.
    private struct SentRequest: Decodable {
        struct Context: Decodable {
            let phase: String
            let requestedMinutes: Int
        }
        let context: Context
        let message: String
    }

    // MARK: - US-AN02: coach narrates the analytics and offers a bounded emphasis action

    /// A fixed calendar/vantage so the dated history classifies deterministically (matches
    /// `ProgressAnalyticsTests`).
    private var an02Calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 1
        return calendar
    }

    private var an02AsOf: Date {
        an02Calendar.date(from: DateComponents(year: 2026, month: 7, day: 8, hour: 12))!
    }

    private func an02Log(_ exerciseId: String, _ pattern: MovementPattern, weeksAgo: Int) -> WorkoutLog {
        WorkoutLog(
            id: UUID(),
            workoutId: UUID(),
            completedAt: an02Calendar.date(byAdding: .day, value: -weeksAgo * 7, to: an02AsOf)!,
            requestedMinutes: 15,
            durationMinutes: 15,
            wasReturn: false,
            shape: .singleFocus,
            focusPillar: nil,
            perceivedDifficulty: nil,
            exercises: [
                LoggedExercise(
                    id: UUID(),
                    exerciseId: exerciseId,
                    pillar: .strength,
                    movementPattern: pattern,
                    completedSets: [CompletedSet(reps: 10, durationSeconds: nil)],
                    skipped: false
                )
            ]
        )
    }

    /// The validation test. A premium user whose push has climbed while hinge stalled asks "how am I
    /// doing?" - the coach raises a bounded emphasis offer toward the stalled hinge (naming push as the
    /// climb), and *accepting* applies a clamped, coach-sourced (`.llm`) policy write that emphasizes
    /// hinge, with the honest note surfaced as a coach turn. The offered action routes through the
    /// US-AC07 path, never a workout edit.
    func testProgressInquiryOffersEmphasisTowardTheStalledPatternAndAcceptWrites() async throws {
        var user = MockPersistence.sampleUser
        user.id = "coach-an02-user"
        let store = InMemorySessionPolicyStore()
        // push climbing: three tiers, current reached this week. hinge flat: stuck at its frontier 4 weeks.
        let logs = [
            an02Log("push_wall", .push, weeksAgo: 5),
            an02Log("push_incline", .push, weeksAgo: 4),
            an02Log("push_knee", .push, weeksAgo: 0),
            an02Log("hinge_glute_bridge", .hinge, weeksAgo: 5),
            an02Log("hinge_single_leg_bridge", .hinge, weeksAgo: 4),
        ]
        let transport = StubTransport(.success(reply: "Your push is climbing and hinge has stalled - here's the picture.", status: 200))
        let viewModel = CoachViewModel(
            client: CoachProxyClient(
                endpoint: endpoint,
                safetyIdentifier: testCoachSafetyIdentifier,
                transport: transport
            ),
            userService: MockUserService(user: user),
            workoutLogService: MockWorkoutLogService(logs: logs),
            exerciseService: try! MockExerciseService(),
            policyService: CoachSessionPolicyService(store: store),
            now: { self.an02AsOf },
            calendar: an02Calendar
        )
        viewModel.grantDataSharingConsent()

        viewModel.draft = "How am I doing?"
        await viewModel.send()

        // The coach offers to lean toward the stalled hinge, naming the climbing push - a concrete
        // insight, not a generic summary.
        let offer = try XCTUnwrap(viewModel.analyticsOffer, "a stalled journey raises an emphasis offer")
        XCTAssertEqual(offer.stalledPattern, .hinge)
        XCTAssertEqual(offer.climbingPattern, .push)
        // Nothing is written until the user accepts.
        let beforeAccept = try await store.policy(for: user.id)
        XCTAssertNil(beforeAccept, "the offer alone writes nothing")

        await viewModel.acceptAnalyticsOffer()

        // Accepting applies a bounded, coach-sourced policy write emphasizing hinge...
        let storedPolicy = try await store.policy(for: user.id)
        let policy = try XCTUnwrap(storedPolicy)
        XCTAssertEqual(policy.updatedBy, .llm)
        XCTAssertGreaterThan(policy.patternEmphasis[.hinge] ?? 0, SessionPolicy.neutralEmphasis)
        XCTAssertLessThanOrEqual(policy.patternEmphasis[.hinge] ?? 0, SessionPolicy.maxEmphasis, "clamped to the rail")
        // ...and surfaces the honest note (naming hinge) as a coach turn.
        let coachTexts = viewModel.messages.filter { $0.author == .coach }.map(\.text)
        XCTAssertTrue(coachTexts.contains { $0.lowercased().contains("hinge") },
                      "the honest note naming hinge is surfaced as a coach turn")
        XCTAssertNil(viewModel.analyticsOffer, "accepting consumes the offer")
    }

    /// A non-inquiry question never raises the analytics offer, so the surface stays quiet unless the
    /// user actually asks how they are doing.
    func testNonInquiryRaisesNoAnalyticsOffer() async {
        var user = MockPersistence.sampleUser
        user.id = "coach-an02-quiet"
        let store = InMemorySessionPolicyStore()
        let logs = [
            an02Log("hinge_glute_bridge", .hinge, weeksAgo: 5),
            an02Log("hinge_single_leg_bridge", .hinge, weeksAgo: 4),
        ]
        let transport = StubTransport(.success(reply: "Here's how to do a good morning.", status: 200))
        let viewModel = CoachViewModel(
            client: CoachProxyClient(
                endpoint: endpoint,
                safetyIdentifier: testCoachSafetyIdentifier,
                transport: transport
            ),
            userService: MockUserService(user: user),
            workoutLogService: MockWorkoutLogService(logs: logs),
            exerciseService: try! MockExerciseService(),
            policyService: CoachSessionPolicyService(store: store),
            now: { self.an02AsOf },
            calendar: an02Calendar
        )
        viewModel.grantDataSharingConsent()

        viewModel.draft = "how do I do a good morning?"
        await viewModel.send()

        XCTAssertNil(viewModel.analyticsOffer)
    }

    /// Declining the analytics offer is exactly a no-op: the card goes away and nothing is written.
    func testDecliningAnalyticsOfferChangesNothing() async throws {
        var user = MockPersistence.sampleUser
        user.id = "coach-an02-decline"
        let store = InMemorySessionPolicyStore()
        let logs = [
            an02Log("hinge_glute_bridge", .hinge, weeksAgo: 5),
            an02Log("hinge_single_leg_bridge", .hinge, weeksAgo: 4),
        ]
        let transport = StubTransport(.success(reply: "Here's the picture.", status: 200))
        let viewModel = CoachViewModel(
            client: CoachProxyClient(
                endpoint: endpoint,
                safetyIdentifier: testCoachSafetyIdentifier,
                transport: transport
            ),
            userService: MockUserService(user: user),
            workoutLogService: MockWorkoutLogService(logs: logs),
            exerciseService: try! MockExerciseService(),
            policyService: CoachSessionPolicyService(store: store),
            now: { self.an02AsOf },
            calendar: an02Calendar
        )
        viewModel.grantDataSharingConsent()

        viewModel.draft = "how am I doing?"
        await viewModel.send()
        XCTAssertNotNil(viewModel.analyticsOffer)

        viewModel.declineAnalyticsOffer()

        XCTAssertNil(viewModel.analyticsOffer)
        let stored = try await store.policy(for: user.id)
        XCTAssertNil(stored, "declining writes nothing")
    }
}
