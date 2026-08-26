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
///   `CoachProxyClient`, so an `await` here always returns and a failure becomes a non-blocking,
///   retryable UI state rather than a hang.
/// - **Conversation memory is on-device, in the caller.** The transport is stateless per request; the
///   transcript (`messages`) lives here, on the device, and is what "multi-turn context" means for
///   this surface. Nothing about the conversation is persisted off-device.
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

    /// A friendly, non-blocking error when a send fails (timeout, offline, non-2xx, empty reply). It
    /// is retryable via `retryLastMessage()` and is cleared the moment a new send starts. `nil` in the
    /// happy path.
    private(set) var errorMessage: String?

    /// Whether the coach is configured for this build. `false` when no proxy origin is set
    /// (`client == nil`); the view shows a clear "coach unavailable" state and disables sending.
    var isAvailable: Bool { client != nil }

    /// Whether the current draft can be sent right now: available, not already sending, and non-empty.
    var canSend: Bool { isAvailable && !isSending && !trimmedDraft.isEmpty }

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
    private let now: () -> Date
    private let calendar: Calendar

    /// The last user message whose send failed, kept so "Try again" resends exactly it without the
    /// user retyping. Cleared on a successful send.
    private var pendingRetryMessage: String?

    /// The derived context, built once from the user's real state and reused across the conversation
    /// (it is a snapshot of "where they are today", which does not change mid-chat). Rebuilt lazily.
    private var cachedContext: CoachContextBundle?

    init(
        client: CoachProxyClient?,
        userService: any UserServiceProtocol,
        workoutLogService: any WorkoutLogServiceProtocol,
        exerciseService: any ExerciseServiceProtocol,
        now: @escaping () -> Date = { Date() },
        calendar: Calendar = .current
    ) {
        self.client = client
        self.userService = userService
        self.workoutLogService = workoutLogService
        self.exerciseService = exerciseService
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
            now: now,
            calendar: calendar
        )
    }

    /// Send the current draft. Appends it to the transcript, clears the input, awaits the coach's
    /// reply through the bounded transport, and appends the reply - or, on any failure, surfaces a
    /// friendly retryable error without ever blocking. A no-op when there is nothing sendable.
    func send() async {
        let message = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isAvailable, !isSending, !message.isEmpty else { return }
        draft = ""
        await deliver(message)
    }

    /// Resend the last message whose send failed (the input was already cleared when it was first
    /// sent), so a transient network blip does not cost the user their question. A no-op when there is
    /// nothing to retry.
    func retryLastMessage() async {
        guard isAvailable, !isSending, let message = pendingRetryMessage else { return }
        await deliver(message)
    }

    /// The one send path, shared by `send()` and `retryLastMessage()`. It never throws to the caller:
    /// a `CoachProxyClient` failure becomes `errorMessage`, and `isSending` always returns to `false`.
    private func deliver(_ message: String) async {
        guard let client else { return }

        // Show the user's turn immediately (only the first time - a retry has already appended it),
        // and clear any prior error so the transcript reads cleanly.
        if messages.last?.text != message || messages.last?.author != .user {
            messages.append(Message(author: .user, text: message))
        }
        errorMessage = nil
        isSending = true
        defer { isSending = false }

        let context = await contextBundle()
        do {
            let reply = try await client.reply(to: message, context: context)
            messages.append(Message(author: .coach, text: reply))
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

    /// The derived, non-identifying context bundle for the conversation, built once from the user's
    /// real on-device state and cached. Best-effort throughout: a missing user or a failed library
    /// read yields a neutral default bundle so the coach can still give general form guidance rather
    /// than the send failing - it never blocks, and it never fabricates history.
    private func contextBundle() async -> CoachContextBundle {
        if let cachedContext { return cachedContext }

        let bundle: CoachContextBundle
        if let user = try? await userService.currentUser() {
            let logs = (try? await workoutLogService.workoutLogs(from: nil, to: nil)) ?? []
            let trend = ConsistencyTrend.trend(
                logs: logs,
                weeklyGoal: user.consistency.weeklyGoal,
                asOf: now(),
                calendar: calendar
            )
            let chainPositions: [ChainPositionSummary]
            if let library = try? await exerciseService.exercises() {
                chainPositions = ProgressAnalytics.from(
                    logs: logs,
                    library: library,
                    phase: user.phase,
                    asOf: now(),
                    calendar: calendar
                ).chainPositions
            } else {
                chainPositions = []
            }
            bundle = CoachContextBundle.make(
                phase: user.phase,
                // The user's learned Default Duration (US-F04) stands in for "the minutes they'd
                // request" on this standalone surface, so "why this workout at this length?" is
                // answerable without the coach being tied to a live session.
                requestedMinutes: user.duration.defaultMinutes,
                chainPositions: chainPositions,
                consistencyTrend: trend,
                recentLogs: logs
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
        return bundle
    }

    /// The friendly, retryable copy for each `CoachError`. All transport-ish failures collapse to one
    /// non-blocking message; an over-long message is the one the user can fix themselves.
    private static func friendlyMessage(for error: CoachProxyClient.CoachError) -> String {
        switch error {
        case .messageTooLong:
            return "That question is a little long - try shortening it and asking again."
        case .emptyMessage, .notHTTP, .badStatus, .emptyReply:
            return genericFailureMessage
        }
    }

    /// The one non-blocking failure line, identity-framed and never alarming: the coach is a nicety,
    /// not a dependency, so a failure reads as "not right now" rather than "something is broken".
    static let genericFailureMessage = "The coach couldn't answer just now. Your workout isn't affected - tap to try again."
}
