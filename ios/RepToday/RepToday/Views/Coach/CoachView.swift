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
            // The tab draws its own header (the Coach mark and title) on every state, as on every other
            // tab, so the bar itself stays hidden.
            .toolbar(.hidden, for: .navigationBar)
            .statusBarBacking()
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
            titledNotice {
                ProgressView()
                    .tint(Theme.Colors.textSecondary)
                    .accessibilityLabel("Loading the coach")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        case .unavailable:
            titledNotice { CoachNotice(text: CoachCopy.unavailable) }
        case .offline:
            titledNotice {
                CoachNotice(text: CoachCopy.offline, actionTitle: CoachCopy.retry) {
                    Task { await viewModel.load() }
                }
            }
        case .free:
            CoachPreviewView(
                note: viewModel.restoreNote,
                onUnlock: { showPaywall = true },
                onRestore: { Task { await viewModel.restorePurchases() } }
            )
        case let .unconfirmed(message):
            titledNotice {
                CoachNotice(text: message, actionTitle: CoachCopy.restore) {
                    Task { await viewModel.restorePurchases() }
                }
            }
        case .premium:
            if declinedDisclosure && !viewModel.isDataSharingAcknowledged {
                titledNotice {
                    CoachNotice(icon: .shield, text: CoachDataDisclosureCopy.declined, actionTitle: CoachDataDisclosureCopy.review) {
                        declinedDisclosure = false
                        present(disclosure: true)
                    }
                }
            } else {
                conversation
            }
        }
    }

    /// A full-tab state under the Coach header, filling the screen and scrolling only when large text
    /// makes it taller than the phone.
    private func titledNotice<Notice: View>(@ViewBuilder _ notice: () -> Notice) -> some View {
        let notice = notice()
        return GeometryReader { viewport in
            ScrollView {
                VStack(spacing: 0) {
                    CoachHeader()
                        .padding(.horizontal, Theme.Spacing.screenMargin)
                        .padding(.top, Theme.Spacing.xs)
                    notice
                }
                .frame(minHeight: viewport.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
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
                    VStack(alignment: .leading, spacing: 10) {
                        CoachHeader()
                            .padding(.bottom, Theme.Spacing.xs)
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
                        // At accessibility sizes a chip can be wider than the screen, so the chips wrap
                        // here, at the end of the conversation, instead of a pinned sideways row.
                        if dynamicTypeSize.isAccessibilitySize {
                            quickActionChips(wrapping: true)
                                .padding(.top, Theme.Spacing.sm)
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
                    .padding(.horizontal, Theme.Spacing.screenMargin)
                    .padding(.top, Theme.Spacing.xs)
                    .padding(.bottom, Theme.Spacing.mlg)
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
            if !dynamicTypeSize.isAccessibilitySize {
                quickActions
            }
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
                .tint(Theme.Colors.textSecondary)
            Text("Coach is thinking...")
                .font(Theme.Typography.footnote)
                .foregroundStyle(Theme.Colors.textSecondary)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Coach is thinking")
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Text(message)
                .font(Theme.Typography.footnote)
                .foregroundStyle(Theme.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if viewModel.canRetry {
                Button(CoachCopy.retry) { begin { await viewModel.retry() } }
                    .font(Theme.Typography.footnote.weight(.bold))
                    .foregroundStyle(Theme.Colors.accent)
                    .frame(minHeight: Theme.Spacing.minTouchTarget)
                    .accessibilityHint("Sends your last message to the coach again")
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.surface1, in: RoundedRectangle(cornerRadius: Theme.Spacing.inputCornerRadius))
        .padding(.horizontal, Theme.Spacing.screenMargin)
        .padding(.top, Theme.Spacing.sm)
        .accessibilityElement(children: .combine)
    }

    /// The quick-action chips in a pinned sideways row: one tap sends a plain request the Coach answers
    /// with a proposal.
    private var quickActions: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.sm) {
                quickActionChips(wrapping: false)
            }
            .padding(.horizontal, Theme.Spacing.screenMargin)
            .padding(.top, 10)
        }
    }

    /// The chips themselves: one line each in the sideways row, or wrapped (each chip's own title too,
    /// when it is wider than the screen) at accessibility sizes.
    @ViewBuilder
    private func quickActionChips(wrapping: Bool) -> some View {
        let chips = ForEach(CoachViewModel.quickActions) { action in
            Button {
                begin { await viewModel.sendQuickAction(action) }
            } label: {
                Text(action.title)
                    .fixedSize(horizontal: !wrapping, vertical: false)
                    .keepsWordsWhole(action.title)
            }
            .buttonStyle(ChipButtonStyle(isSelected: false))
            .disabled(viewModel.isSending || !viewModel.isDataSharingAcknowledged)
            .accessibilityHint("Asks the coach: \(action.message)")
        }
        if wrapping {
            WrappingRow { chips }
        } else {
            chips
        }
    }

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: Theme.Spacing.sm) {
            // At the accessibility sizes the full prompt no longer fits the field's one line.
            TextField(
                "",
                text: $viewModel.draft,
                prompt: Text(dynamicTypeSize.isAccessibilitySize ? "Message" : "Message the coach")
                    .foregroundStyle(Theme.Colors.textTertiary),
                axis: .vertical
            )
                .font(Theme.Typography.body.weight(.medium))
                .foregroundStyle(Theme.Colors.textPrimary)
                .tint(Theme.Colors.sun)
                .lineLimit(1...5)
                .padding(.horizontal, Theme.Spacing.mlg)
                .padding(.vertical, 14)
                .frame(minHeight: Self.composerHeight)
                .background(Theme.Colors.surface2, in: RoundedRectangle(cornerRadius: Self.composerHeight / 2))
                .disabled(viewModel.isSending)
                .focused($composerFocused)
                .accessibilityLabel("Message to the coach")
            Button {
                composerFocused = false
                begin { await viewModel.send() }
            } label: {
                IconView(icon: .send, size: 24)
                    .foregroundStyle(viewModel.canSend ? Theme.Colors.onAccent : Theme.Colors.textTertiary)
                    .frame(width: Self.composerHeight, height: Self.composerHeight)
                    .background(viewModel.canSend ? Theme.Colors.sun : Theme.Colors.surface2, in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.canSend)
            .accessibilityLabel("Send")
            .accessibilityHint("Sends your message to the coach")
        }
        .padding(.horizontal, Theme.Spacing.screenMargin)
        .padding(.top, Theme.Spacing.sm)
        .padding(.bottom, Theme.Spacing.sm)
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

    /// The composer's field and Send button: 52 pt.
    private static let composerHeight: CGFloat = 52

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

// MARK: - Header

/// The Coach tab's own header: the Coach mark beside its title.
struct CoachHeader: View {
    @ScaledMetric(relativeTo: .title) private var markSize: CGFloat = 30

    var body: some View {
        HStack(spacing: 10) {
            DayMarkView(mark: .bubble, color: Theme.Colors.sun, size: markSize)
            Text(CoachCopy.title)
                .cappedDisplayFont(size: 28, relativeTo: .title1)
                .foregroundStyle(Theme.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.top, 2)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Bubble

/// One turn: the user's messages trail on white, the Coach's lead on `surface2`, each with its tail
/// corner tucked in, and each names its speaker to VoiceOver.
struct CoachMessageBubble: View {
    let message: CoachMessage

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var isUser: Bool { message.role == .user }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: dynamicTypeSize.isAccessibilitySize ? Theme.Spacing.md : Theme.Spacing.xxl) }
            Text(message.text)
                .font(isUser ? Theme.Typography.body.weight(.medium) : Theme.Typography.body)
                .foregroundStyle(isUser ? Theme.Colors.black : Theme.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.smd)
                .background(isUser ? Theme.Colors.text1 : Theme.Colors.surface2, in: bubbleShape)
                .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
            if !isUser { Spacer(minLength: dynamicTypeSize.isAccessibilitySize ? Theme.Spacing.md : Theme.Spacing.xl) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isUser ? "You said: \(message.text)" : "Coach said: \(message.text)")
    }

    private var bubbleShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: 22,
            bottomLeadingRadius: isUser ? 22 : 6,
            bottomTrailingRadius: isUser ? 6 : 22,
            topTrailingRadius: 22
        )
    }
}

// MARK: - Notices and preview

/// A calm full-tab notice with an optional action: the Coach mark in outline (or `icon`), the words, and
/// the action as the primary button.
struct CoachNotice: View {
    var icon: AppIcon?
    let text: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            Group {
                if let icon {
                    IconView(icon: icon, size: 44)
                        .foregroundStyle(Theme.Colors.textSecondary)
                } else {
                    DayMarkView(mark: .bubble, filled: false, color: Theme.Colors.textSecondary, size: 44)
                }
            }
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
                        .capsuleLabelInset(actionTitle)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: Theme.Spacing.buttonHeight)
                }
                .accentFilledButtonStyle()
                .padding(.top, Theme.Spacing.sm)
            }
        }
        .padding(.horizontal, Theme.Spacing.screenMargin)
        .padding(.vertical, Theme.Spacing.lg)
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
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    CoachHeader()
                    // Under the header, so the answer to a Restore is on screen whatever the phone's size.
                    if let note {
                        Text(note)
                            .font(Theme.Typography.callout)
                            .foregroundStyle(Theme.Colors.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(Theme.Spacing.md)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.Colors.surface1, in: RoundedRectangle(cornerRadius: Theme.Spacing.inputCornerRadius))
                            .accessibilityElement(children: .combine)
                            .onAppear { AccessibilityNotification.Announcement(note).post() }
                    }
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        Text("Premium".uppercased())
                            .overlineStyle()
                            .foregroundStyle(Theme.Colors.sun)
                            .accessibilityHidden(true)
                        Text(CoachCopy.previewTitle)
                            .cappedDisplayFont(size: 38)
                            .foregroundStyle(Theme.Colors.textPrimary)
                            .keepsWordsWhole(CoachCopy.previewTitle)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                        Text(CoachCopy.previewBody)
                            .font(Theme.Typography.callout)
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 6)

                    VStack(spacing: 10) {
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
                    .padding(14)
                    .background(Theme.Colors.stageBase, in: RoundedRectangle(cornerRadius: Theme.Spacing.stageCornerRadius))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Spacing.stageCornerRadius)
                            .strokeBorder(Theme.Colors.line, lineWidth: 1)
                    )
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Example: you tell the coach about a run, and it offers to log it for you.")
                }
                .padding(.horizontal, Theme.Spacing.screenMargin)
                .padding(.top, Theme.Spacing.xs)
                .padding(.bottom, Theme.Spacing.mlg)
            }

            VStack(spacing: 10) {
                Button(action: onUnlock) {
                    Text(CoachCopy.unlock)
                        .font(Theme.Typography.button)
                        .capsuleLabelInset(CoachCopy.unlock)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: Theme.Spacing.buttonHeight)
                }
                .accentFilledButtonStyle()
                .accessibilityHint("Shows the Premium plans")

                Button(action: onRestore) {
                    Text(CoachCopy.restore)
                        .font(Theme.Typography.callout.weight(.bold))
                        .capsuleLabelInset(CoachCopy.restore)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: Theme.Spacing.minTouchTarget)
                }
                .ghostButtonStyle()
            }
            .padding(.horizontal, Theme.Spacing.screenMargin)
            .padding(.top, 10)
            .padding(.bottom, Theme.Spacing.sm)
        }
    }
}
