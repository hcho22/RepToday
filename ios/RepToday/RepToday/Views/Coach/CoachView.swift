import SwiftUI

/// The Coach tab (M4, US-CA06, decision 28): the fourth tab, full screen, with the persistent
/// conversation, quick-action chips, and inline cards for what the Coach proposes - actions to confirm
/// or decline (with Undo) and Custom Workouts to review, accept and play.
///
/// Free users see a preview and the paywall; the server decides Premium on every turn. When the build
/// has no account backend, or there is no connection, the tab says so calmly - the free core loop is
/// never affected. Every color, font and dimension comes from `Theme`.
struct CoachTabView: View {
    @Environment(\.services) private var services
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// Optional so hosted evidence surfaces can mount the tab without an `AppState`.
    @Environment(AppState.self) private var appState: AppState?

    @State private var viewModel: CoachViewModel
    @State private var showDisclosure = false
    @State private var declinedDisclosure = false
    @State private var showPaywall = false
    @State private var routedInjuryArea: InjuryOption?
    @State private var review: CustomWorkoutReview?
    @State private var playback: CustomWorkoutPlayback?
    @State private var deliveryTask: Task<Void, Never>?
    /// Whether the composer has the keyboard. Sending puts it away: a reply usually carries a card to
    /// confirm, and on a small phone the keyboard leaves little room to read it.
    @FocusState private var composerFocused: Bool

    init(services: ServiceContainer) {
        _viewModel = State(initialValue: CoachViewModel(services: services, planInputsChanged: {}))
    }

    /// Test/preview entry with a pre-built view model.
    init(viewModel: CoachViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Colors.background.ignoresSafeArea()
                content
                if showDisclosure {
                    CoachDataDisclosureView(onAcknowledge: acknowledgeDisclosure, onDecline: declineDisclosure)
                        .transition(.opacity)
                        .zIndex(1)
                }
            }
            .navigationTitle(CoachCopy.title)
            .navigationBarTitleDisplayMode(.inline)
        }
        .task { await viewModel.load() }
        .onChange(of: viewModel.access) { _, _ in resolveDisclosure() }
        .onAppear(perform: resolveDisclosure)
        .sheet(isPresented: $showPaywall) {
            PaywallView(
                subscriptionService: services.subscriptionService,
                premiumSessionAuthority: services.premiumSessionAuthority,
                analyticsService: services.analyticsService,
                entryPoint: .coachUpsell,
                entitlements: services.premiumEntitlements
            ) { _ in
                Task { await viewModel.load() }
            }
        }
        .sheet(item: $routedInjuryArea) { area in
            NavigationStack {
                InjuryFlagsView(services: services, preselect: area, dismissesOnSave: true)
            }
        }
        .sheet(item: $review) { review in
            CustomWorkoutEditorView(
                workout: review.workout,
                library: viewModel.library,
                trainer: viewModel.trainer
            ) { edited, play in
                Task {
                    if let accepted = await viewModel.accept(edited, for: review.proposal, in: review.message), play {
                        playback = await viewModel.playback(of: accepted)
                    }
                }
            }
        }
        .fullScreenCover(item: $playback) { playback in
            ActiveSessionView(
                workout: playback.playable,
                user: playback.user,
                completionService: CustomWorkoutCompletionRecorder(
                    workout: playback.workout,
                    library: playback.library,
                    outsideActivityService: services.outsideActivityService,
                    customWorkouts: services.customWorkoutService
                ),
                userService: services.userService
            ) { completed in
                if completed { appState?.markPlanInputsChanged() }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.access {
        case .loading:
            ProgressView()
                .accessibilityLabel("Loading the coach")
        case .unavailable:
            CoachNotice(symbol: "bubble.left.and.exclamationmark.bubble.right", text: CoachCopy.unavailable)
        case .offline:
            CoachNotice(symbol: "wifi.slash", text: CoachCopy.offline, actionTitle: CoachCopy.retry) {
                Task { await viewModel.load() }
            }
        case .free:
            CoachPreviewView(
                note: viewModel.restoreNote,
                onUnlock: { showPaywall = true },
                onRestore: { Task { await viewModel.restorePurchases() } }
            )
        case let .unconfirmed(message):
            CoachNotice(symbol: "creditcard.trianglebadge.exclamationmark", text: message, actionTitle: CoachCopy.restore) {
                Task { await viewModel.restorePurchases() }
            }
        case .premium:
            if declinedDisclosure && !viewModel.isDataSharingAcknowledged {
                CoachNotice(symbol: "hand.raised", text: CoachDataDisclosureCopy.declined, actionTitle: CoachDataDisclosureCopy.review) {
                    declinedDisclosure = false
                    present(disclosure: true)
                }
            } else {
                conversation
            }
        }
    }

    // MARK: - Disclosure (US-AC04, US-CA07)

    private func resolveDisclosure() {
        guard viewModel.access == .premium else { return }
        if appState?.hasAcknowledgedCoachDataSharing == true {
            viewModel.grantDataSharingConsent()
        } else if appState != nil, !viewModel.isDataSharingAcknowledged, !declinedDisclosure {
            present(disclosure: true)
        }
    }

    private func present(disclosure: Bool) {
        if reduceMotion {
            showDisclosure = disclosure
        } else {
            withAnimation(.easeOut(duration: 0.25)) { showDisclosure = disclosure }
        }
    }

    private func acknowledgeDisclosure() {
        viewModel.grantDataSharingConsent()
        appState?.markCoachDataSharingAcknowledged()
        present(disclosure: false)
    }

    private func declineDisclosure() {
        declinedDisclosure = true
        present(disclosure: false)
    }

    // MARK: - Conversation

    private var conversation: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    // A plain stack, not a lazy one: the conversation is bounded (the server returns at
                    // most 200 messages), every turn stays in VoiceOver's reach, and a lazy stack scrolled
                    // to its end while the keyboard resizes it re-placed its rows without end, hanging the
                    // main thread.
                    VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                        if viewModel.messages.isEmpty && !viewModel.isLoadingHistory {
                            emptyState
                        }
                        ForEach(viewModel.messages) { message in
                            CoachMessageBubble(message: message)
                                .id(message.id)
                            ForEach(message.proposals) { proposal in
                                proposalCard(proposal, in: message)
                            }
                        }
                        if viewModel.isSending {
                            typingIndicator
                        }
                        if let offer = viewModel.injuryRoutingOffer {
                            CoachInjuryOfferView(
                                area: offer.area,
                                onAccept: { routedInjuryArea = viewModel.acceptInjuryRoutingOffer() },
                                onDecline: viewModel.declineInjuryRoutingOffer
                            )
                        }
                        // The end of the conversation: a reply's proposal cards and the injury offer sit
                        // below its bubble, so scrolling targets this rather than the last message.
                        Color.clear
                            .frame(height: 1)
                            .accessibilityHidden(true)
                            .id(Self.bottomID)
                    }
                    .padding(Theme.Spacing.md)
                }
                .scrollDismissesKeyboard(.interactively)
                // Opening the tab on an existing conversation shows its newest turn.
                .onAppear { scrollToBottom(proxy, animated: false) }
                .onChange(of: viewModel.messages.count) { _, _ in scrollToBottom(proxy) }
                .onChange(of: viewModel.isSending) { _, _ in scrollToBottom(proxy) }
                .onChange(of: viewModel.injuryRoutingOffer != nil) { _, _ in scrollToBottom(proxy) }
                // The keyboard shrinks the conversation from below; keep the newest turn in view.
                .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidShowNotification)) { _ in
                    scrollToBottom(proxy)
                }
            }
            if let error = viewModel.errorMessage {
                errorBanner(error)
            }
            quickActions
            inputBar
        }
    }

    @ViewBuilder
    private func proposalCard(_ proposal: CoachProposal, in message: CoachMessage) -> some View {
        switch proposal.action {
        case let .customWorkout(draft):
            CustomWorkoutCard(
                draft: draft,
                accepted: viewModel.acceptedWorkouts[proposal.id],
                status: proposal.status,
                library: viewModel.library,
                trainer: viewModel.trainer,
                isBusy: viewModel.busyProposals.contains(proposal.id),
                canUndo: viewModel.canUndo(proposal),
                error: viewModel.proposalErrors[proposal.id],
                onReview: { _ in
                    Task {
                        if let workout = await viewModel.reviewableWorkout(for: proposal, in: message) {
                            review = CustomWorkoutReview(workout: workout, proposal: proposal, message: message)
                        }
                    }
                },
                onDecline: { Task { await viewModel.decline(proposal, in: message) } },
                onPlay: { workout in Task { playback = await viewModel.playback(of: workout) } },
                onUndo: { Task { await viewModel.undo(proposal, in: message); appState?.markPlanInputsChanged() } }
            )
        default:
            CoachProposalCard(
                proposal: proposal,
                isBusy: viewModel.busyProposals.contains(proposal.id),
                canUndo: viewModel.canUndo(proposal),
                error: viewModel.proposalErrors[proposal.id],
                onConfirm: { Task { await viewModel.apply(proposal, in: message); appState?.markPlanInputsChanged() } },
                onDecline: { Task { await viewModel.decline(proposal, in: message) } },
                onUndo: { Task { await viewModel.undo(proposal, in: message); appState?.markPlanInputsChanged() } }
            )
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(CoachCopy.emptyTitle)
                .font(Theme.Typography.title)
                .foregroundStyle(Theme.Colors.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text(CoachCopy.emptyBody)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, Theme.Spacing.sm)
    }

    private var typingIndicator: some View {
        HStack(spacing: Theme.Spacing.sm) {
            ProgressView()
            Text("Coach is thinking...")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Coach is thinking")
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.Colors.danger)
                .accessibilityHidden(true)
            Text(message)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if viewModel.canRetry {
                Button(CoachCopy.retry) { begin { await viewModel.retry() } }
                    .font(Theme.Typography.caption.weight(.semibold))
                    .foregroundStyle(Theme.Colors.accent)
                    .frame(minHeight: Theme.Spacing.minTouchTarget)
                    .accessibilityHint("Sends your last message to the coach again")
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.surface)
        .accessibilityElement(children: .combine)
    }

    /// The quick-action chips: one tap sends a plain request the Coach answers with a proposal.
    private var quickActions: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.sm) {
                ForEach(CoachViewModel.quickActions) { action in
                    Button {
                        begin { await viewModel.sendQuickAction(action) }
                    } label: {
                        Label(action.title, systemImage: action.systemImage)
                            .font(Theme.Typography.caption.weight(.semibold))
                            .foregroundStyle(Theme.Colors.textPrimary)
                            .padding(.horizontal, Theme.Spacing.md)
                            .frame(minHeight: Theme.Spacing.minTouchTarget)
                            .background(Theme.Colors.surface, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.isSending || !viewModel.isDataSharingAcknowledged)
                    .accessibilityHint("Asks the coach: \(action.message)")
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.top, Theme.Spacing.sm)
        }
    }

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: Theme.Spacing.sm) {
            // At the accessibility sizes the full prompt no longer fits the field's one line.
            TextField(dynamicTypeSize.isAccessibilitySize ? "Message" : "Message the coach", text: $viewModel.draft, axis: .vertical)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textPrimary)
                .lineLimit(1...5)
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.sm)
                .frame(minHeight: Theme.Spacing.minTouchTarget)
                .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Spacing.cardCornerRadius))
                .disabled(viewModel.isSending)
                .focused($composerFocused)
                .accessibilityLabel("Message to the coach")
            Button {
                composerFocused = false
                begin { await viewModel.send() }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(viewModel.canSend ? Theme.Colors.accent : Theme.Colors.textSecondary)
                    .frame(width: Theme.Spacing.minTouchTarget, height: Theme.Spacing.minTouchTarget)
            }
            .disabled(!viewModel.canSend)
            .accessibilityLabel("Send")
            .accessibilityHint("Sends your message to the coach")
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.background)
    }

    private func begin(_ work: @escaping @MainActor () async -> Void) {
        guard deliveryTask == nil else { return }
        deliveryTask = Task {
            await work()
            deliveryTask = nil
        }
    }

    private static let bottomID = "coach.bottom"

    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool = true) {
        if reduceMotion || !animated {
            proxy.scrollTo(Self.bottomID, anchor: .bottom)
        } else {
            withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(Self.bottomID, anchor: .bottom) }
        }
    }
}

/// A Custom Workout the user opened for review: the editable copy and the proposal it came from.
struct CustomWorkoutReview: Identifiable {
    let workout: CustomWorkout
    let proposal: CoachProposal
    let message: CoachMessage
    var id: String { proposal.id }
}

// MARK: - Bubble

/// One turn: the user's messages trail on the accent fill, the Coach's lead on the surface, and each
/// names its speaker to VoiceOver.
struct CoachMessageBubble: View {
    let message: CoachMessage

    private var isUser: Bool { message.role == .user }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: Theme.Spacing.xl) }
            Text(message.text)
                .font(Theme.Typography.body)
                .foregroundStyle(isUser ? Theme.Colors.onAccent : Theme.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.sm)
                .background(
                    isUser ? Theme.Colors.accentFill : Theme.Colors.surface,
                    in: RoundedRectangle(cornerRadius: Theme.Spacing.cardCornerRadius)
                )
                .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
            if !isUser { Spacer(minLength: Theme.Spacing.xl) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isUser ? "You said: \(message.text)" : "Coach said: \(message.text)")
    }
}

// MARK: - Notices and preview

/// A calm full-tab notice with an optional action.
struct CoachNotice: View {
    let symbol: String
    let text: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: symbol)
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(Theme.Colors.textSecondary)
                .accessibilityHidden(true)
            Text(text)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textPrimary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(Theme.Typography.button)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: Theme.Spacing.buttonHeight)
                }
                .accentFilledButtonStyle()
                .clipShape(RoundedRectangle(cornerRadius: Theme.Spacing.cardCornerRadius))
            }
        }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// What a free user sees on the Coach tab (decision 28): a preview of the Coach at work and the
/// paywall's entry, framed as what Premium adds - never as something taken away.
struct CoachPreviewView: View {
    /// The answer to a Restore: nothing this phone can link (on every visit while StoreKit here shows
    /// Premium with no signed transaction, or after a restore found nothing), or that it could not run.
    var note: String?
    let onUnlock: () -> Void
    let onRestore: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                // At the top, so the answer to a Restore is on screen whatever the phone's size.
                if let note {
                    HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
                        Image(systemName: "info.circle")
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .accessibilityHidden(true)
                        Text(note)
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.Colors.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .padding(Theme.Spacing.md)
                    .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Spacing.cardCornerRadius))
                    .accessibilityElement(children: .combine)
                    .onAppear { AccessibilityNotification.Announcement(note).post() }
                }
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Text(CoachCopy.previewTitle)
                        .font(Theme.Typography.title)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    Text(CoachCopy.previewBody)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(spacing: Theme.Spacing.md) {
                    CoachMessageBubble(message: CoachMessage(id: "preview-1", role: .user, text: "I ran 5k this morning.", createdAt: .distantPast, proposals: []))
                    CoachMessageBubble(message: CoachMessage(
                        id: "preview-2",
                        role: .coach,
                        text: "Nice work. Your legs get tomorrow off - I've put the run below for you to log.",
                        createdAt: .distantPast,
                        proposals: []
                    ))
                    CoachProposalCard(
                        proposal: CoachProposal(id: "preview", status: .proposed, action: .outsideActivity(type: .run, minutes: 30, distanceMeters: 5000, day: .today)),
                        isBusy: false,
                        canUndo: false,
                        error: nil,
                        onConfirm: {},
                        onDecline: {},
                        onUndo: {}
                    )
                    .disabled(true)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Example: you tell the coach about a run, and it offers to log it for you.")

                VStack(spacing: Theme.Spacing.sm) {
                    Button(action: onUnlock) {
                        Text(CoachCopy.unlock)
                            .font(Theme.Typography.button)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: Theme.Spacing.buttonHeight)
                    }
                    .accentFilledButtonStyle()
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Spacing.cardCornerRadius))
                    .accessibilityHint("Shows the Premium plans")

                    Button(action: onRestore) {
                        Text(CoachCopy.restore)
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.Colors.accent)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: Theme.Spacing.minTouchTarget)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(Theme.Spacing.lg)
        }
    }
}
