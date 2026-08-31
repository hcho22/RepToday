import Foundation
import Observation

/// Backs the premium AI coach chat surface (US-AC02, the *talking* coach). The user asks free-text
/// questions and the coach answers them, grounded in the user's real on-device history via the
/// audited, non-identifying `CoachContextBundle` (US-AC01) and the stateless `CoachProxyClient`
/// transport. It answers the target intents - "why this workout?", "how do I do <movement>?", "is
/// <movement> safe with <complaint>?", "I'm bored" - but it only ever *talks*: it never generates,
/// edits, or prescribes a workout (the deterministic on-device engine owns every session), which is
/// enforced in the proxy persona rather than reconstructed here.
///
/// Three properties make it safe to live beside the free core loop:
///
/// - **It never blocks the core loop.** The core loop (generate / play / log) never calls the coach,
///   and the coach never calls the core loop. Every send goes through the bounded, throwing
///   `CoachProxyClient`, so an `await` here always returns. Transport failures become a non-blocking,
///   retryable UI state; safety refusals become a stable non-retryable state.
/// - **Conversation memory is on-device, in the caller.** The transport is stateless per request; the
///   transcript (`messages`) lives here, on the device, and is what "multi-turn context" means for
///   this surface. Nothing about the conversation is persisted off-device.
/// - **It never sets a safety filter.** A health/injury signal raises a routing *offer* (US-AC08) that
///   points at the user's own injury control; the coach cannot set or clear an injury flag, and the
///   policy-write path it does have (US-AC07) cannot express one.
/// - **Inert when unconfigured.** When no coach proxy is configured for the build (`client == nil` -
///   which is every build today, since the proxy is deploy-ready but not deployed), the surface is
///   `isAvailable == false` and shows a clear "coach unavailable" state instead of failing.
///
/// It is `@Observable`, takes its services as protocols, and injects a clock/calendar so the derived
/// context is deterministic under test - the same conventions as the other v6 view models. It is
/// **not** premium-gated here: US-AC03 owns the entitlement gate and the upsell entry point.
@Observable
@MainActor
final class CoachViewModel {

    /// One turn in the on-device transcript. Identifiable so the chat list can render it stably.
    struct Message: Identifiable, Equatable {
        enum Author: Equatable {
            /// The user's question.
            case user
            /// The coach's answer.
            case coach
        }

        let id: UUID
        let author: Author
        let text: String

        init(id: UUID = UUID(), author: Author, text: String) {
            self.id = id
            self.author = author
            self.text = text
        }
    }

    /// The on-device conversation transcript, oldest first. This *is* the coach's multi-turn memory:
    /// the transport holds none, so what the user and coach have said lives here and nowhere else.
    private(set) var messages: [Message] = []

    /// The in-flight question, bound to the input field.
    var draft: String = ""

    /// True while a reply is being awaited. The input is disabled and a typing indicator shows; it
    /// always returns to `false`, success or failure, so the surface never gets stuck.
    private(set) var isSending = false

    /// A friendly, non-blocking error when a send fails. Transport errors are retryable via
    /// `retryLastMessage()`; a safety refusal is not. Cleared the moment a new send starts.
    private(set) var errorMessage: String?

    /// Whether the coach is configured for this build. `false` when no proxy origin is set
    /// (`client == nil`); the view shows a clear "coach unavailable" state and disables sending.
    var isAvailable: Bool { client != nil }

    /// Whether the user has acknowledged the coach data disclosure (US-AC04) and the coach may send.
    /// This is the **load-bearing send gate**: it is checked in the one send path (`deliver`), not just
    /// used to enable a button, so no coach request - and therefore no message and no training-context
    /// summary - can leave the device until the user has read the disclosure and tapped "I understand".
    /// It starts `false` (consent not yet given) and is flipped only by `grantDataSharingConsent()`.
    private(set) var isDataSharingAcknowledged = false

    /// Whether the pre-use disclosure still owes an acknowledgement before the coach can be used. Only
    /// meaningful for a configured coach: an unavailable build has nothing to send, so it needs no
    /// consent (it shows the calm "unavailable" state instead).
    var needsDataSharingConsent: Bool { isAvailable && !isDataSharingAcknowledged }

    /// Record the user's explicit acknowledgement of the coach data disclosure (US-AC04), opening the
    /// send gate for this session. The *persistence* of the one-shot (so the disclosure is not shown
    /// again next launch) is the caller's job - `CoachView` writes `AppState` - which keeps this view
    /// model free of `AppState` and hostable in evidence surfaces. Idempotent.
    func grantDataSharingConsent() { isDataSharingAcknowledged = true }

    /// The pending injury routing offer (US-AC08), set when a sent message read as a health signal for
    /// an area the user has not already flagged. It is an **offer**, not a change: the coach never sets
    /// or clears an injury filter, and this value carries no way to - it names the area the surface
    /// should route to if the user accepts. `nil` whenever there is nothing to offer.
    private(set) var injuryRoutingOffer: CoachInjuryRoutingProposal?

    /// The user accepted the offer: clear it and hand the caller the area to route to. The write does
    /// not happen here and cannot - the returned area is the *destination* of a route to the user's own
    /// injury control, where they still have to confirm.
    @discardableResult
    func acceptInjuryRoutingOffer() -> InjuryOption? {
        let area = injuryRoutingOffer?.area
        injuryRoutingOffer = nil
        return area
    }

    /// The user declined the offer: dismiss it and change nothing. No profile write, no policy write,
    /// no transcript turn - declining is exactly a no-op plus the card going away.
    func declineInjuryRoutingOffer() {
        injuryRoutingOffer = nil
    }

    /// The pending analytics-driven action offer (US-AN02), set when a "how am I doing?" progress
    /// inquiry landed on a strength journey that shows a real stall. It is an **offer**, not a change:
    /// accepting applies a bounded, preference-only `patternEmphasis` nudge through the *same* US-AC07
    /// write path (never a workout edit); it can express nothing else. `nil` whenever there is nothing
    /// to offer.
    private(set) var analyticsOffer: CoachAnalyticsInsightOffer?

    /// The user accepted the analytics offer: clear it and apply the bounded, clamped, preference-only
    /// nudge that emphasizes the stalled pattern - through `CoachPolicyServiceProtocol`, exactly like
    /// the US-AC07 tuning path - surfacing the honest coach note as a coach turn. A no-op (beyond
    /// dismissing the card) when there is no policy service, no current user, or the clamped write
    /// moves nothing. It only ever touches the one preference lever, so it never blocks the core loop
    /// and never touches a safety filter.
    func acceptAnalyticsOffer() async {
        guard let offer = analyticsOffer else { return }
        analyticsOffer = nil
        guard let policyService,
              let user = try? await userService.currentUser() else { return }
        guard let written = try? await policyService.applyProposal(offer.proposal, for: user, asOf: now()),
              let note = written.note else { return }
        messages.append(Message(author: .coach, text: note.text))
    }

    /// The user declined the analytics offer: dismiss it and change nothing. Like declining the injury
    /// offer, it is exactly a no-op plus the card going away - nothing was ever written.
    func declineAnalyticsOffer() {
        analyticsOffer = nil
    }

    /// Whether the current draft can be sent right now: available, consent given, not already sending,
    /// and non-empty.
    var canSend: Bool { isAvailable && isDataSharingAcknowledged && !isSending && !trimmedDraft.isEmpty }

    /// Whether there is a failed message to retry.
    var canRetry: Bool { isAvailable && !isSending && pendingRetryMessage != nil }

    /// A few identity-framed starter prompts shown on the empty state, one per target intent, so the
    /// user sees what the coach can actually help with rather than a blank box.
    static let suggestedPrompts: [String] = [
        "Why this workout today?",
        "How do I do a pistol squat?",
        "Is planking safe with a sore wrist?",
        "I'm bored - why does it feel repetitive?",
    ]

    private var trimmedDraft: String { draft.trimmingCharacters(in: .whitespacesAndNewlines) }

    private let client: CoachProxyClient?
    private let userService: any UserServiceProtocol
    private let workoutLogService: any WorkoutLogServiceProtocol
    private let exerciseService: any ExerciseServiceProtocol
    /// The sovereign on-device coach policy-write path (US-AC07). When present and a sent message maps to
    /// an eligible tuning request, the coach applies a bounded, clamped, preference-only `SessionPolicy`
    /// nudge and surfaces the honest note as a coach turn. `nil` leaves the coach purely talking (US-AC02).
    private let policyService: (any CoachPolicyServiceProtocol)?
    private let now: () -> Date
    private let calendar: Calendar

    /// The last user message whose send failed, kept so "Try again" resends exactly it without the
    /// user retyping. Cleared on a successful send.
    private var pendingRetryMessage: String?

    /// The derived context, built once from the user's real state and reused across the conversation
    /// (it is a snapshot of "where they are today", which does not change mid-chat). Rebuilt lazily.
    private var cachedContext: CoachContextBundle?

    /// The typed strength-journey trends behind `cachedContext.strengthJourney` (US-AN02), cached
    /// alongside it so the analytics offer reads the *same* classification the bundle sent - never a
    /// second derivation that could disagree. Set whenever `cachedContext` is.
    private var cachedStrengthTrends: [StrengthPatternTrend]?

    init(
        client: CoachProxyClient?,
        userService: any UserServiceProtocol,
        workoutLogService: any WorkoutLogServiceProtocol,
        exerciseService: any ExerciseServiceProtocol,
        policyService: (any CoachPolicyServiceProtocol)? = nil,
        now: @escaping () -> Date = { Date() },
        calendar: Calendar = .current
    ) {
        self.client = client
        self.userService = userService
        self.workoutLogService = workoutLogService
        self.exerciseService = exerciseService
        self.policyService = policyService
        self.now = now
        self.calendar = calendar
    }

    /// Convenience initializer wiring the services this needs straight off the container, so the one
    /// call site (`CoachView`) does not have to name them individually.
    convenience init(services: ServiceContainer, now: @escaping () -> Date = { Date() }, calendar: Calendar = .current) {
        self.init(
            client: services.coachClient,
            userService: services.userService,
            workoutLogService: services.workoutLogService,
            exerciseService: services.exerciseService,
            policyService: services.coachPolicyService,
            now: now,
            calendar: calendar
        )
    }

    /// Send the current draft. Appends it to the transcript, clears the input, awaits the coach's
    /// reply through the bounded transport, and appends the reply - or surfaces the matching bounded
    /// failure state without ever blocking. A no-op when there is nothing sendable.
    func send() async {
        let message = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        // US-AC04: never send before the user has acknowledged the data disclosure. Gated here *and*
        // in `deliver` so no path - a tapped Send, a suggested prompt, or a retry - can leak content
        // before consent.
        guard isAvailable, isDataSharingAcknowledged, !isSending, !message.isEmpty else { return }
        draft = ""
        await deliver(message)
    }

    /// Resend the last message whose send failed (the input was already cleared when it was first
    /// sent), so a transient network blip does not cost the user their question. A no-op when there is
    /// nothing to retry.
    func retryLastMessage() async {
        guard isAvailable, isDataSharingAcknowledged, !isSending, let message = pendingRetryMessage else { return }
        await deliver(message)
    }

    /// The one send path, shared by `send()` and `retryLastMessage()`. It never throws to the caller:
    /// a `CoachProxyClient` failure becomes `errorMessage`, and `isSending` always returns to `false`.
    private func deliver(_ message: String) async {
        guard let client else { return }
        // US-AC04, the load-bearing guarantee: the send path itself refuses to run until the user has
        // acknowledged the disclosure. This is not merely a disabled button - it is the last line that
        // makes "declining sends nothing" true even if a caller reached here another way.
        guard isDataSharingAcknowledged else { return }

        // Show the user's turn immediately (only the first time - a retry has already appended it),
        // and clear any prior error so the transcript reads cleanly.
        if messages.last?.text != message || messages.last?.author != .user {
            messages.append(Message(author: .user, text: message))
        }
        errorMessage = nil
        // A new question supersedes any un-answered offer: an offer belongs to the turn that raised
        // it, and letting one linger under a later answer would read as a standing prompt. Dropping
        // either changes nothing (neither ever set anything to begin with).
        injuryRoutingOffer = nil
        analyticsOffer = nil
        isSending = true
        defer { isSending = false }

        let context = await contextBundle()
        do {
            let reply = try await client.reply(to: message, context: context)
            // US-AC07: an eligible tuning request ("focus my push", "take it easier") applies a bounded,
            // clamped, preference-only policy nudge on-device and surfaces the honest note as its own coach
            // turn. It runs only on the successful-reply path, so a message the transport rejected (too
            // long) or that failed in flight never tunes the program and never orphans a turn in the
            // transcript; it never touches a safety filter and never blocks.
            await applyTuningIfRequested(message)
            // US-AC08: a health/injury signal produces a *routing offer*, never a filter change. Like
            // the tuning above it runs only on the successful-reply path, and unlike it, it writes
            // nothing at all - the flag can only be set by the user in the injury control this offer
            // routes to.
            await offerInjuryRoutingIfSignalled(message)
            // US-AN02: a "how am I doing?" progress inquiry, on a journey that shows a real stall,
            // ends the turn with a bounded emphasis *offer*. Like the two above it runs only on the
            // successful-reply path and writes nothing until the user accepts - and accepting routes
            // through the US-AC07 policy path, so it can never be a workout edit.
            await offerAnalyticsInsightIfRequested(message)
            messages.append(Message(author: .coach, text: reply))
            pendingRetryMessage = nil
        } catch let error as CoachProxyClient.CoachError where error.isSafetyRefusal {
            errorMessage = Self.friendlyMessage(for: error)
            pendingRetryMessage = nil
        } catch let error as CoachProxyClient.CoachError where error.isMessageTooLong {
            // The one failure the user can fix themselves: give them their text back so they can
            // trim it, drop the rejected turn rather than orphaning it in the transcript, and do not
            // offer retry - resending the identical over-long text just re-hits the same local guard.
            if messages.last?.author == .user, messages.last?.text == message {
                messages.removeLast()
            }
            if draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                draft = message
            }
            errorMessage = Self.friendlyMessage(for: error)
            pendingRetryMessage = nil
        } catch let error as CoachProxyClient.CoachError {
            errorMessage = Self.friendlyMessage(for: error)
            pendingRetryMessage = message
        } catch {
            // Any transport-level failure (offline, DNS, TLS, timeout) - the client throws these
            // through, and they are all recovered identically: a non-blocking, retryable state.
            errorMessage = Self.genericFailureMessage
            pendingRetryMessage = message
        }
    }

    /// Apply a coach policy nudge (US-AC07) when `message` maps to an eligible tuning request. Entirely
    /// best-effort and non-blocking: it no-ops when there is no policy service, no recognized intent, no
    /// current user, or the write moves nothing (a clamped no-op). On a real write it appends the honest,
    /// coach-authored note as a coach turn so the user sees exactly what changed - never a claim of a change
    /// that did not happen (the note is `nil` unless a lever actually moved, and only a non-`nil` written
    /// policy reaches here). It can only ever move the three preference levers, so it never blocks the core
    /// loop and never touches a safety filter.
    private func applyTuningIfRequested(_ message: String) async {
        guard let policyService,
              let proposal = CoachIntentMapper.proposal(for: message),
              let user = try? await userService.currentUser() else { return }
        guard let written = try? await policyService.applyProposal(proposal, for: user, asOf: now()),
              let note = written.note else { return }
        messages.append(Message(author: .coach, text: note.text))
    }

    /// Raise the injury routing offer (US-AC08) when `message` reads as a health signal about an area
    /// the user has not already flagged.
    ///
    /// This is the *entire* injury path on the coach side, and it is deliberately write-free: it reads
    /// the profile to avoid offering something already done, and then sets `injuryRoutingOffer`. It
    /// calls no policy service (safety filters are inexpressible on that path by construction, US-AC07)
    /// and never touches `UserProfile.injuries` - the flag is set only by the user, in the injury
    /// control the offer routes to. Best-effort and non-blocking throughout: a missing profile or an
    /// unrecognized message simply means no offer.
    private func offerInjuryRoutingIfSignalled(_ message: String) async {
        guard let routing = CoachInjurySignalMapper.routing(for: message) else { return }
        // Offering to flag something already flagged would be noise, and would invite the user to
        // "confirm" a change that is not a change. The "already flagged" question is asked the
        // engine's way (normalized tags), so an area the filter already protects reads as protected.
        if let user = try? await userService.currentUser(),
           routing.area.isFlagged(in: user.profile.injuries) {
            return
        }
        injuryRoutingOffer = routing
    }

    /// Raise the analytics-driven action offer (US-AN02) when `message` is a progress inquiry and the
    /// user's strength journey shows a real stall.
    ///
    /// The stall read is the *same* `CoachStrengthJourneyReader` classification the context bundle
    /// carries (cached when the bundle was built at the top of this send), so the offer and the
    /// narration cannot disagree. It only offers when there is a policy service to apply the nudge
    /// through - offering an action the surface cannot take would be noise - and the offer's accept
    /// routes through that same bounded US-AC07 path, so it can never be a workout edit. Best-effort
    /// and non-blocking: no policy service, no progress inquiry, or no stall simply means no offer.
    private func offerAnalyticsInsightIfRequested(_ message: String) async {
        guard policyService != nil,
              CoachAnalyticsInsight.isProgressInquiry(message) else { return }
        // The trends were cached when `contextBundle()` ran earlier in this send; recompute defensively
        // if a cache miss ever leaves them nil (e.g. a neutral default bundle).
        let trends = cachedStrengthTrends ?? []
        guard let offer = CoachAnalyticsInsight.offer(from: trends) else { return }
        analyticsOffer = offer
    }

    /// The derived, non-identifying context bundle for the conversation, built once from the user's
    /// real on-device state and cached. Best-effort throughout: a missing user or a failed library
    /// read yields a neutral default bundle so the coach can still give general form guidance rather
    /// than the send failing - it never blocks, and it never fabricates history.
    private func contextBundle() async -> CoachContextBundle {
        if let cachedContext { return cachedContext }

        let bundle: CoachContextBundle
        var trends: [StrengthPatternTrend] = []
        if let user = try? await userService.currentUser() {
            let logs = (try? await workoutLogService.workoutLogs(from: nil, to: nil)) ?? []
            let trend = ConsistencyTrend.trend(
                logs: logs,
                weeklyGoal: user.consistency.weeklyGoal,
                asOf: now(),
                calendar: calendar
            )
            let chainPositions: [ChainPositionSummary]
            let strengthJourney: StrengthJourney
            if let library = try? await exerciseService.exercises() {
                // One analytics pass gives both the chain positions and the strength journey the coach
                // narrates, so both read the *same* frontier the Progress tab shows.
                let analytics = ProgressAnalytics.from(
                    logs: logs,
                    library: library,
                    phase: user.phase,
                    asOf: now(),
                    calendar: calendar
                )
                chainPositions = analytics.chainPositions
                strengthJourney = analytics.deep.strengthJourney
            } else {
                chainPositions = []
                strengthJourney = StrengthJourney(chains: [])
            }
            trends = CoachStrengthJourneyReader.trends(from: strengthJourney, asOf: now(), calendar: calendar)
            bundle = CoachContextBundle.make(
                phase: user.phase,
                // The user's learned Default Duration (US-F04) stands in for "the minutes they'd
                // request" on this standalone surface, so "why this workout at this length?" is
                // answerable without the coach being tied to a live session.
                requestedMinutes: user.duration.defaultMinutes,
                chainPositions: chainPositions,
                consistencyTrend: trend,
                recentLogs: logs,
                strengthJourney: strengthJourney,
                asOf: now(),
                calendar: calendar
            )
        } else {
            // No profile (should not happen on this surface): a neutral, non-identifying default so the
            // coach can still answer general form/variety questions without fabricating history.
            bundle = CoachContextBundle.make(
                phase: .discipline,
                requestedMinutes: 15,
                chainPositions: [],
                consistencyTrend: [],
                recentLogs: []
            )
        }
        cachedContext = bundle
        cachedStrengthTrends = trends
        return bundle
    }

    /// The friendly copy for each `CoachError`. Transport failures collapse to one retryable message;
    /// user-correctable and safety outcomes stay non-retryable.
    private static func friendlyMessage(for error: CoachProxyClient.CoachError) -> String {
        switch error {
        case .messageTooLong:
            return "That question is a little long - try shortening it and asking again."
        case .safetyRefusal:
            return safetyRefusalMessage
        case .emptyMessage, .invalidSafetyIdentifier, .notHTTP, .badStatus, .emptyReply:
            return genericFailureMessage
        }
    }

    /// The one non-blocking failure line, identity-framed and never alarming: the coach is a nicety,
    /// not a dependency, so a failure reads as "not right now" rather than "something is broken".
    static let genericFailureMessage = "The coach couldn't answer just now. Your workout isn't affected - tap to try again."

    static let safetyRefusalMessage = "The coach can't help with that request. Try asking about your training, form, or consistency."
}
