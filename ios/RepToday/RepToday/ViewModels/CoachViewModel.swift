import Foundation
import Observation

/// Backs the Coach tab (M4, US-CA01/US-CA03/US-CA04/US-CA06, ADR-0017): the premium agent that
/// remembers, acts through confirmed proposals, writes Custom Workouts, and sets reminders.
///
/// - **The server decides Premium.** Access comes from the account's entitlement on the server
///   (`PremiumEntitlementServiceProtocol`), which App Store Server Notifications keep current, and the
///   server checks it again on every turn. When StoreKit on this phone shows Premium but the account does
///   not yet, the phone links its signed transaction first (US-CA02); a free user sees the preview and the
///   paywall.
/// - **The conversation lives with the account.** It is loaded from the server and every turn returns
///   the stored messages, so it survives a reinstall and follows the user to another device.
/// - **Nothing happens without a tap.** A Coach reply may carry proposals; each is a card the user
///   applies, declines, and can undo (`CoachProposalApplier`), and a Custom Workout plays only after the
///   user has reviewed and accepted it (FR-11). Safety-owned engine moves cannot be proposed at all.
/// - **Nothing is sent before consent.** The data disclosure (US-AC04, US-CA07) gates the one send path.
/// - **It never blocks the core loop.** The core loop never calls the Coach; every failure here is a calm,
///   retryable state on this tab.
@Observable
@MainActor
final class CoachViewModel {

    /// What the Coach tab can show.
    enum Access: Equatable {
        /// Deciding.
        case loading
        /// This build has no account backend, so there is no Coach.
        case unavailable
        /// The account is not Premium: the preview and the paywall.
        case free
        /// StoreKit shows Premium on this phone and has a signed transaction, but the account does not
        /// hold it (yet): offer Restore.
        case unconfirmed(message: String)
        /// No connection: the Coach needs one.
        case offline
        /// The Coach is open.
        case premium
    }

    private(set) var access: Access = .loading
    /// A line on the free preview answering a Restore: on every load while StoreKit here shows Premium
    /// but holds no signed transaction to send the account, after a restore that left the account free,
    /// or, when the App Store could not be reached, that the restore did not happen.
    private(set) var restoreNote: String?
    private(set) var messages: [CoachMessage] = []
    private(set) var isLoadingHistory = false
    var draft = ""
    private(set) var isSending = false
    /// A calm, non-blocking failure line for the last send.
    private(set) var errorMessage: String?
    /// Whether the last failure can be retried with the same message.
    var canRetry: Bool { pendingRetry != nil && !isSending }

    /// The US-AC08 routing offer: a health signal in the user's message points them at their own injury
    /// control. It is an offer, never a change - the Coach cannot set or clear an injury flag.
    private(set) var injuryRoutingOffer: CoachInjuryRoutingProposal?

    /// Proposals being applied, undone or declined right now.
    private(set) var busyProposals: Set<String> = []
    /// A proposal that could not be applied, and why.
    private(set) var proposalErrors: [String: String] = [:]
    /// Accepted Custom Workouts by the proposal they came from, so a card can offer Play.
    private(set) var acceptedWorkouts: [String: CustomWorkout] = [:]
    /// The catalog, so Custom Workout cards resolve catalog steps to their Trainer art and target copy.
    private(set) var library: [Exercise] = []
    /// The user's Trainer, whose art catalog steps show; `nil` shows the movement glyph.
    private(set) var trainer: Trainer?

    /// Whether the user has acknowledged the current Coach data disclosure (US-AC04/US-CA07). The
    /// load-bearing send gate: checked in the one send path, not just used to enable a button.
    private(set) var isDataSharingAcknowledged = false
    var needsDataSharingConsent: Bool { access == .premium && !isDataSharingAcknowledged }
    func grantDataSharingConsent() { isDataSharingAcknowledged = true }

    var canSend: Bool {
        access == .premium && isDataSharingAcknowledged && !isSending && !trimmedDraft.isEmpty
    }

    /// The quick-action chips under the conversation (US-CA06): each sends a plain request the Coach
    /// answers with the matching proposal.
    struct QuickAction: Identifiable, Equatable {
        let title: String
        let message: String
        let systemImage: String
        var id: String { title }
    }

    static let quickActions: [QuickAction] = [
        QuickAction(title: "Write me a workout", message: "Write me a workout for today.", systemImage: "list.bullet.rectangle"),
        QuickAction(title: "I worked out outside", message: "I did a workout outside Rep Today today.", systemImage: "figure.run"),
        QuickAction(title: "Shorter session", message: "I only have 10 minutes today.", systemImage: "timer"),
        QuickAction(title: "Rest today", message: "I'd like to rest today.", systemImage: "bed.double"),
        QuickAction(title: "Remind me", message: "Remind me to train on weekdays at 7:30 AM.", systemImage: "bell"),
        QuickAction(title: "How am I doing?", message: "How am I doing?", systemImage: "chart.line.uptrend.xyaxis"),
    ]

    private var trimmedDraft: String { draft.trimmingCharacters(in: .whitespacesAndNewlines) }

    private let coach: (any CoachServiceProtocol)?
    private let entitlements: (any PremiumEntitlementServiceProtocol)?
    private let subscriptionService: any SubscriptionServiceProtocol
    private let premiumAuthority: PremiumSessionAuthority
    private let applier: CoachProposalApplier
    private let today: CoachTodayReader
    private let customWorkouts: any CustomWorkoutServiceProtocol
    private let userService: any UserServiceProtocol
    private let exerciseService: any ExerciseServiceProtocol
    private let now: () -> Date

    /// The message whose send failed, kept so "Try again" resends it with the same id (the server then
    /// answers a retry of an already-stored turn without asking the model again).
    private var pendingRetry: (id: UUID, text: String)?
    /// Undo handles by proposal id.
    private var undos: [String: CoachProposalApplier.Undo] = [:]

    /// A proposal outcome this phone acted on that the server has not stored yet.
    private struct UnrecordedOutcome {
        let id = UUID()
        let messageId: String
        let proposalId: String
        let status: CoachProposal.Status
    }

    /// Outcomes still owed to the server, in the order they happened. They are resent until stored, and
    /// shown over a reloaded history so a proposal already acted on is never offered again.
    private var unrecordedOutcomes: [UnrecordedOutcome] = []

    init(
        coach: (any CoachServiceProtocol)?,
        entitlements: (any PremiumEntitlementServiceProtocol)?,
        subscriptionService: any SubscriptionServiceProtocol,
        premiumAuthority: PremiumSessionAuthority,
        applier: CoachProposalApplier,
        today: CoachTodayReader,
        customWorkouts: any CustomWorkoutServiceProtocol,
        userService: any UserServiceProtocol,
        exerciseService: any ExerciseServiceProtocol,
        now: @escaping () -> Date = { Date() }
    ) {
        self.coach = coach
        self.entitlements = entitlements
        self.subscriptionService = subscriptionService
        self.premiumAuthority = premiumAuthority
        self.applier = applier
        self.today = today
        self.customWorkouts = customWorkouts
        self.userService = userService
        self.exerciseService = exerciseService
        self.now = now
    }

    /// Production wiring off the container. `planInputsChanged` tells Today to rebuild after an action.
    convenience init(services: ServiceContainer, planInputsChanged: @escaping @Sendable @MainActor () -> Void) {
        self.init(
            coach: services.coachService,
            entitlements: services.premiumEntitlements,
            subscriptionService: services.subscriptionService,
            premiumAuthority: services.premiumSessionAuthority,
            applier: CoachProposalApplier(
                userService: services.userService,
                outsideActivityService: services.outsideActivityService,
                todayChoices: services.todayChoices,
                reminders: services.reminders,
                customWorkouts: services.customWorkoutService,
                planInputsChanged: planInputsChanged
            ),
            today: CoachTodayReader(services: services),
            customWorkouts: services.customWorkoutService,
            userService: services.userService,
            exerciseService: services.exerciseService
        )
    }

    // MARK: - Access and history

    /// Decides what the tab shows and, for a Premium account, loads the conversation.
    func load() async {
        await load(freeNote: nil)
    }

    /// `freeNote` is what the preview says when the account turns out free.
    private func load(freeNote: String?) async {
        // Set with the answer, so a re-check keeps the current note on screen until the answer arrives.
        var note: String?
        defer { restoreNote = note }
        guard let coach, let entitlements else {
            access = .unavailable
            return
        }
        // Only the first load shows the spinner (`access` starts at `.loading`): returning to the tab
        // re-checks with the known state still on screen until the answer arrives.
        do {
            var status = try await entitlements.status()
            if !status.premium, await hasLocalPremium() {
                // StoreKit says Premium on this phone: link its signed transaction to the account.
                let transactions = await subscriptionService.premiumTransactionJWS()
                guard !transactions.isEmpty else {
                    // Nothing signed to send, so a link can never succeed and offering Restore again
                    // would only lead back here. Say plainly that nothing was found.
                    access = .free
                    note = CoachCopy.noSubscriptionFound
                    return
                }
                do {
                    status = try await entitlements.link(transactions: transactions)
                } catch PremiumEntitlementError.linkedToOtherAccount {
                    access = .unconfirmed(message: CoachCopy.linkedToOtherAccount)
                    return
                } catch {
                    access = .unconfirmed(message: CoachCopy.unconfirmed)
                    return
                }
                if !status.premium {
                    access = .unconfirmed(message: CoachCopy.unconfirmed)
                    return
                }
            }
            guard status.premium else {
                access = .free
                note = freeNote
                return
            }
            access = .premium
        } catch PremiumEntitlementError.offline {
            access = .offline
            return
        } catch {
            access = messages.isEmpty ? .offline : access
            return
        }
        await loadHistory(coach)
    }

    /// Restore Purchases, from the preview or the "not confirmed" state: StoreKit sync, then link, then
    /// re-check. A restore that leaves the account free says nothing was found (`restoreNote`); one
    /// that never reached the App Store says so instead.
    func restorePurchases() async {
        access = .loading
        let restored = (try? await subscriptionService.restorePurchaseGrant()) != nil
        await load(freeNote: restored ? CoachCopy.noSubscriptionFound : CoachCopy.couldNotRestore)
    }

    private func hasLocalPremium() async -> Bool {
        let token = premiumAuthority.beginRead()
        if let grant = try? await subscriptionService.currentSubscriptionGrant() {
            premiumAuthority.acceptSnapshot(grant, token: token)
        } else {
            premiumAuthority.acceptReadFailure(token: token)
        }
        return premiumAuthority.subscription.tier == .premium
    }

    private func loadHistory(_ coach: any CoachServiceProtocol) async {
        isLoadingHistory = messages.isEmpty
        defer { isLoadingHistory = false }
        if library.isEmpty, let exercises = try? await exerciseService.exercises() {
            library = exercises
        }
        if let user = try? await userService.currentUser() {
            trainer = Trainer.effective(for: user.profile)
        }
        await sendUnrecordedOutcomes()
        if let history = try? await coach.history() {
            messages = history
            for outcome in unrecordedOutcomes {
                setStatus(outcome.status, for: outcome.proposalId, in: outcome.messageId)
            }
        }
        if let workouts = try? await customWorkouts.workouts() {
            acceptedWorkouts = Dictionary(
                workouts.compactMap { workout in workout.proposalId.map { ($0, workout) } },
                uniquingKeysWith: { first, _ in first }
            )
        }
    }

    // MARK: - Sending

    func send() async {
        let text = trimmedDraft
        guard canSend else { return }
        draft = ""
        await deliver(id: UUID(), text: text)
    }

    func sendQuickAction(_ action: QuickAction) async {
        guard access == .premium, isDataSharingAcknowledged, !isSending else { return }
        await deliver(id: UUID(), text: action.message)
    }

    func retry() async {
        guard let pendingRetry, !isSending, isDataSharingAcknowledged else { return }
        await deliver(id: pendingRetry.id, text: pendingRetry.text)
    }

    /// The one send path. Never throws: a failure becomes `errorMessage`, and `isSending` always returns
    /// to `false`.
    private func deliver(id: UUID, text: String) async {
        guard let coach, access == .premium, isDataSharingAcknowledged else { return }
        let pendingId = "pending-\(id.uuidString.lowercased())"
        if pendingRetry?.id != id {
            messages.append(CoachMessage(id: pendingId, role: .user, text: text, createdAt: now(), proposals: []))
        }
        errorMessage = nil
        injuryRoutingOffer = nil
        isSending = true
        defer { isSending = false }
        let snapshot = await today.snapshot()
        do {
            let turn = try await coach.send(clientMessageId: id, message: text, today: snapshot)
            messages.removeAll { $0.id == pendingId }
            messages.append(contentsOf: [turn.user, turn.coach])
            pendingRetry = nil
            await offerInjuryRoutingIfSignalled(text)
        } catch let error as CoachServiceError {
            handle(error, id: id, text: text, pendingId: pendingId)
        } catch {
            handle(.unavailable, id: id, text: text, pendingId: pendingId)
        }
    }

    private func handle(_ error: CoachServiceError, id: UUID, text: String, pendingId: String) {
        switch error {
        case .notPremium:
            messages.removeAll { $0.id == pendingId }
            pendingRetry = nil
            access = .free
        case .invalidMessage:
            messages.removeAll { $0.id == pendingId }
            if trimmedDraft.isEmpty { draft = text }
            errorMessage = CoachCopy.messageTooLong
            pendingRetry = nil
        case .limitReached:
            messages.removeAll { $0.id == pendingId }
            if trimmedDraft.isEmpty { draft = text }
            errorMessage = CoachCopy.limitReached
            pendingRetry = nil
        case .signedOut, .accountDeleting:
            messages.removeAll { $0.id == pendingId }
            if trimmedDraft.isEmpty { draft = text }
            errorMessage = CoachCopy.signedOut
            pendingRetry = nil
        case .offline, .unavailable, .outcomeRefused:
            errorMessage = CoachCopy.couldNotAnswer
            pendingRetry = (id, text)
        }
    }

    // MARK: - US-AC08 injury routing

    private func offerInjuryRoutingIfSignalled(_ message: String) async {
        guard let routing = CoachInjurySignalMapper.routing(for: message) else { return }
        if let user = try? await userService.currentUser(), routing.area.isFlagged(in: user.profile.injuries) {
            return
        }
        injuryRoutingOffer = routing
    }

    @discardableResult
    func acceptInjuryRoutingOffer() -> InjuryOption? {
        let area = injuryRoutingOffer?.area
        injuryRoutingOffer = nil
        return area
    }

    func declineInjuryRoutingOffer() {
        injuryRoutingOffer = nil
    }

    // MARK: - Proposals

    /// Applies an action proposal the user confirmed, through the same paths their own taps take.
    func apply(_ proposal: CoachProposal, in message: CoachMessage) async {
        guard proposal.status == .proposed, !busyProposals.contains(proposal.id) else { return }
        busyProposals.insert(proposal.id)
        proposalErrors[proposal.id] = nil
        defer { busyProposals.remove(proposal.id) }
        do {
            undos[proposal.id] = try await applier.apply(proposal.action)
            setStatus(.applied, for: proposal.id, in: message.id)
            await record(.applied, for: proposal.id, in: message.id)
        } catch CoachProposalApplier.ApplyError.notificationsOff {
            proposalErrors[proposal.id] = CoachReminderCopy.permissionDenied
        } catch {
            proposalErrors[proposal.id] = CoachCopy.couldNotApply
        }
    }

    func decline(_ proposal: CoachProposal, in message: CoachMessage) async {
        guard proposal.status == .proposed, !busyProposals.contains(proposal.id) else { return }
        setStatus(.declined, for: proposal.id, in: message.id)
        await record(.declined, for: proposal.id, in: message.id)
    }

    /// Whether this session can undo a proposal it applied.
    func canUndo(_ proposal: CoachProposal) -> Bool {
        proposal.status == .applied && undos[proposal.id] != nil
    }

    func undo(_ proposal: CoachProposal, in message: CoachMessage) async {
        guard let undo = undos[proposal.id], !busyProposals.contains(proposal.id) else { return }
        busyProposals.insert(proposal.id)
        defer { busyProposals.remove(proposal.id) }
        do {
            try await applier.undo(undo)
            undos[proposal.id] = nil
            if case .customWorkout = proposal.action { acceptedWorkouts[proposal.id] = nil }
            setStatus(.undone, for: proposal.id, in: message.id)
            await record(.undone, for: proposal.id, in: message.id)
        } catch {
            proposalErrors[proposal.id] = CoachCopy.couldNotUndo
        }
    }

    // MARK: - Custom Workouts

    /// The reviewable workout for a Custom Workout proposal (US-CA05): editable, not yet saved.
    func reviewableWorkout(for proposal: CoachProposal, in message: CoachMessage) async -> CustomWorkout? {
        guard case let .customWorkout(draft) = proposal.action else { return nil }
        let library = (try? await exerciseService.exercises()) ?? []
        return CustomWorkout(draft: draft, messageId: message.id, proposalId: proposal.id, library: library, now: now())
    }

    /// Accepts the reviewed workout: only now is it saved, and only now can it play.
    @discardableResult
    func accept(_ workout: CustomWorkout, for proposal: CoachProposal, in message: CoachMessage) async -> CustomWorkout? {
        guard proposal.status == .proposed, !busyProposals.contains(proposal.id) else { return nil }
        busyProposals.insert(proposal.id)
        defer { busyProposals.remove(proposal.id) }
        do {
            let (accepted, undo) = try await applier.acceptCustomWorkout(workout)
            undos[proposal.id] = undo
            acceptedWorkouts[proposal.id] = accepted
            setStatus(.applied, for: proposal.id, in: message.id)
            await record(.applied, for: proposal.id, in: message.id)
            return accepted
        } catch {
            proposalErrors[proposal.id] = CoachCopy.couldNotApply
            return nil
        }
    }

    /// What the player needs to play an accepted workout (FR-11: only an accepted one).
    func playback(of workout: CustomWorkout) async -> CustomWorkoutPlayback? {
        guard workout.isAccepted else { return nil }
        let library = (try? await exerciseService.exercises()) ?? []
        guard let user = try? await userService.currentUser() else { return nil }
        return CustomWorkoutPlayback(workout: workout, playable: workout.playableWorkout(library: library, now: now()), library: library, user: user)
    }

    /// Records a proposal's outcome with the server, keeping it on the phone until the server stores it.
    private func record(_ status: CoachProposal.Status, for proposalId: String, in messageId: String) async {
        unrecordedOutcomes.append(UnrecordedOutcome(messageId: messageId, proposalId: proposalId, status: status))
        await sendUnrecordedOutcomes()
    }

    /// Sends every owed outcome in order. A proposal whose outcome fails for now keeps its later ones for
    /// next time; one the server refuses for good is dropped, so the server's status stands.
    private func sendUnrecordedOutcomes() async {
        guard let coach else { return }
        var failed: Set<String> = []
        for outcome in unrecordedOutcomes where !failed.contains(outcome.proposalId) {
            do {
                try await coach.recordOutcome(messageId: outcome.messageId, proposalId: outcome.proposalId, status: outcome.status)
                unrecordedOutcomes.removeAll { $0.id == outcome.id }
            } catch CoachServiceError.outcomeRefused {
                failed.insert(outcome.proposalId)
                unrecordedOutcomes.removeAll { $0.proposalId == outcome.proposalId }
            } catch {
                failed.insert(outcome.proposalId)
            }
        }
    }

    private func setStatus(_ status: CoachProposal.Status, for proposalId: String, in messageId: String) {
        guard let index = messages.firstIndex(where: { $0.id == messageId }),
              let proposalIndex = messages[index].proposals.firstIndex(where: { $0.id == proposalId }) else { return }
        messages[index].proposals[proposalIndex].status = status
    }
}

/// An accepted Custom Workout, ready for the hands-free player.
struct CustomWorkoutPlayback: Identifiable {
    let workout: CustomWorkout
    let playable: Workout
    let library: [Exercise]
    let user: User
    var id: UUID { playable.id }
}

/// The Coach's copy, one source for the tab, its cards and the tests that pin it. Identity-framed and
/// calm: the Coach is a nicety, never a dependency, so a failure reads as "not right now".
enum CoachCopy {
    static let title = "Coach"
    static let emptyTitle = "Your coach"
    static let emptyBody = "Ask about today's session or a movement, tell it about a run, or ask for a workout. "
        + "Anything it suggests waits for you to confirm."
    static let couldNotAnswer = "The coach couldn't answer just now. Your workout isn't affected - tap to try again."
    static let messageTooLong = "That message is a little long - try shortening it and sending again."
    static let limitReached = "You've talked with the coach a lot today. It'll be ready again tomorrow."
    static let signedOut = "Sign in to your Rep Today account to use the coach."
    static let couldNotApply = "That didn't go through. Nothing changed - try again."
    static let couldNotUndo = "That couldn't be undone just now. Try again."
    static let unconfirmed = "Your Premium subscription isn't on your Rep Today account yet. Restore purchases to link it."
    static let noSubscriptionFound = "No active Premium subscription was found for this Apple ID."
    static let couldNotRestore = "We couldn't restore right now. Please try again."
    static let linkedToOtherAccount = "This Apple ID's Premium subscription belongs to another Rep Today account, so the coach stays with that account."
    static let offline = "The coach needs a connection. Your sessions work offline as always."
    static let unavailable = "The coach isn't available in this build. Your workouts are unaffected."
    static let previewTitle = "A coach that knows your training"
    static let previewBody = "Premium's coach remembers your sessions, logs a run for you, adjusts today, writes workouts for a hotel room, "
        + "and reminds you when you want it to - always waiting for your OK."
    static let unlock = "See Premium plans"
    static let restore = "Restore purchases"
    static let retry = "Try again"
}
