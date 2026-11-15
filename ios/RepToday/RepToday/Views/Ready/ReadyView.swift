import SwiftUI

/// The minimal Ready Screen the app opens to after onboarding (US-I01).
///
/// It renders the complete session the deterministic engine generated at the user's Default
/// Duration - blocks and their prescribed exercises - with one dominant "Start" action, so there is
/// never a picker to clear before moving. There is no XP, no levels, and no badges; every token
/// comes from `Theme`.
///
/// US-J01 adds the non-blocking duration chip: a one-tap row offering 5/10/15/20/30/45/60 that
/// regenerates the session in place while Start stays present and enabled. US-J02 surfaces the three
/// read-only ways the personalization is *felt* - the Variety Language line ("what today is"), the
/// forgiving Consistency Score ("how I'm doing", always identity-framed), and the policy note ("what
/// the app changed") - all rendered from the existing policy with no spinner ever blocking Start,
/// while an on-open Re-program runs in the background. The Start action opens the player in US-K01.
/// A secondary **Different workout** control rebuilds the session at the same length with other moves,
/// in place like a chip, as often as the user likes before they start.
struct ReadyView: View {
    /// Optional so the hosted evidence surfaces that mount `ReadyView` without an `AppState` still
    /// render (production, reached from the tab tree, always has one). It is read for exactly one
    /// thing: the US-AC08 injury-flag revision, so confirming a safety filter regenerates the session
    /// already on this screen instead of waiting for a relaunch.
    @Environment(AppState.self) private var appState: AppState?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var viewModel: ReadyViewModel
    /// The Outside Activity sheet on screen (US-HO04): a new entry, or an edit of a logged one.
    @State private var activitySheet: ActivitySheet?
    /// What the active-session player is presented for (US-K01/US-K04): a fresh session started from
    /// Start, or an abandoned session resumed from the Ready Screen. The `.fullScreenCover` presents
    /// the player for it and clears it on dismiss.
    @State private var presentedPlayer: PlayerPresentation?
    /// Whether the one-time classics note (ADR-0007) is on screen. Raised once, on the first Ready
    /// Screen an eligible install reaches; the note itself persists that it was shown.
    @State private var showClassicsNote = false

    /// Held so the active-session player can be handed the engine seam for the in-session swap
    /// (US-K03) and the store it persists to (US-K04); the user and recent logs it also needs come
    /// from the loaded `viewModel`.
    private let services: ServiceContainer

    /// `now` is the view model's clock (it anchors the recent-log lookback window), injectable so a hosted
    /// evidence surface pinned to a fixture date does not lose its history as the wall clock moves on.
    init(services: ServiceContainer, now: @escaping () -> Date = { Date() }) {
        self.services = services
        _viewModel = State(
            initialValue: ReadyViewModel(
                userService: services.userService,
                sessionPolicyService: services.sessionPolicyService,
                workoutEngine: services.workoutEngine,
                workoutLogService: services.workoutLogService,
                outsideActivityService: services.outsideActivityService,
                healthKitService: services.healthKitService,
                consistencyService: services.consistencyService,
                activeSessionStore: services.activeSessionStore,
                todayChoicesStore: services.todayChoices,
                analytics: services.analyticsService,
                now: now
            )
        )
    }

    /// What the Outside Activity sheet is for (US-HO04).
    private enum ActivitySheet: Identifiable {
        case new
        case edit(OutsideActivity)

        var id: String {
            switch self {
            case .new: return "new"
            case .edit(let activity): return activity.id.uuidString
            }
        }
    }

    /// What the player is presented for: a fresh start or a resumed abandoned session (US-K04).
    private enum PlayerPresentation: Identifiable {
        case fresh(Workout)
        case resume(ActiveSessionState)

        var id: UUID {
            switch self {
            case .fresh(let workout): return workout.id
            case .resume(let state): return state.workout.id
            }
        }
    }

    var body: some View {
        ZStack {
            Theme.Colors.background.ignoresSafeArea()

            if let workout = viewModel.workout {
                sessionScroll(workout)
            } else if viewModel.showsRestDay {
                restDayScroll
            } else if viewModel.isLoading {
                ProgressView().tint(Theme.Colors.accent)
            } else {
                emptyState
            }
        }
        .statusBarBacking()
        // Re-runs on appear, whenever the user confirms an injury-flag change (US-AC08), and whenever they
        // save new Focus Areas (US-HO02), so the session on screen is rebuilt against what they just set
        // rather than what was in force when the tab was last opened.
        .task(id: "\(appState?.injuryFlagsRevision ?? 0)-\(appState?.planInputsRevision ?? 0)") {
            await viewModel.load()
            await refreshHealthSuggestions()
        }
        // A workout recorded on a watch while the app sat in the background is offered on return.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await refreshHealthSuggestions() } }
        }
        .sheet(item: $activitySheet) { sheet in
            activitySheetView(sheet)
        }
        .fullScreenCover(item: $presentedPlayer) { presentation in
            switch presentation {
            case .fresh(let workout):
                ActiveSessionView(
                    workout: workout,
                    workoutEngine: services.workoutEngine,
                    user: viewModel.user,
                    recentLogs: viewModel.recentLogs,
                    sessionPolicy: viewModel.policy,
                    store: viewModel.sessionStore,
                    userId: viewModel.user?.id,
                    completionService: services.sessionCompletionService,
                    analytics: services.analyticsService,
                    userService: services.userService,
                    onFinish: { completed in Task { await viewModel.handlePlayerDismiss(completed: completed) } }
                )
            case .resume(let state):
                ActiveSessionView(
                    resuming: state,
                    workoutEngine: services.workoutEngine,
                    user: viewModel.user,
                    recentLogs: viewModel.recentLogs,
                    sessionPolicy: viewModel.policy,
                    store: viewModel.sessionStore,
                    userId: viewModel.user?.id,
                    completionService: services.sessionCompletionService,
                    analytics: services.analyticsService,
                    userService: services.userService,
                    onFinish: { completed in Task { await viewModel.handlePlayerDismiss(completed: completed) } }
                )
            }
        }
    }

    // MARK: - Session

    /// The tone today takes: its Training Day's color for the headline, chips, the training block and
    /// Start (DESIGN "Color": the session takes the color of its Training Day).
    private var tone: DayTone { DayTone(viewModel.trainingDay) }

    private func sessionScroll(_ workout: Workout) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    header

                    if showClassicsNote {
                        ClassicsUpdateNote(
                            onShow: { appState?.markClassicsUpdateNoteSeen() },
                            onDismiss: { showClassicsNote = false }
                        )
                    }

                    if let state = viewModel.resumableSession {
                        ResumeSessionCard(
                            state: state,
                            onResume: {
                                viewModel.sessionWillStart()
                                presentedPlayer = .resume(state)
                            },
                            onDiscard: { Task { await viewModel.discardResumableSession() } }
                        )
                    }

                    healthSuggestions

                    if let note = viewModel.policyNote {
                        PolicyNoteCard(note: note)
                    }

                    durationChips

                    DifferentWorkoutButton(minutes: viewModel.requestedMinutes) {
                        Task { await viewModel.showDifferentWorkout() }
                    }

                    // The score card sits under the controls that shape today's session
                    // (`screens/T10-Today.html`).
                    if let consistency = viewModel.consistency {
                        ConsistencyCard(consistency: consistency)
                    }

                    ForEach(workout.blocks) { block in
                        BlockCard(block: block, tone: tone)
                    }

                    outsideActivityCard
                }
                .padding(.horizontal, Theme.Spacing.screenMargin)
                .padding(.top, Theme.Spacing.sm)
                .padding(.bottom, Theme.Spacing.mlg)
            }
            .onAppear(perform: presentClassicsNoteIfNeeded)

            startBar
        }
    }

    /// Raises the one-time classics note for an install that predates the change, once its session is on
    /// screen. Only the note's own appearance consumes `AppState`'s persisted one-shot flag, so a screen
    /// that never reaches the note (or an advanced / Strength-Phase user) leaves it untouched.
    private func presentClassicsNoteIfNeeded() {
        guard !showClassicsNote,
              let appState,
              appState.shouldShowClassicsUpdateNote,
              viewModel.isClassicsUpdateNoteEligible else { return }
        showClassicsNote = true
    }

    private var header: some View {
        TodayHeader(
            greeting: greeting,
            mark: DayMark(viewModel.trainingDay),
            tone: tone
        ) {
            // The headline: the day in its color over its honest length (Display L), read as one line,
            // its two lines set at Display L's 57 pt leading rather than the font's looser own.
            VStack(alignment: .leading, spacing: headlineLineGap) {
                Text(viewModel.trainingDay?.displayName ?? WelcomeCopy.fallbackTitle)
                    .foregroundStyle(tone.color)
                Text(CountWording.phrase(viewModel.plannedMinutes, singular: "minute", plural: "minutes"))
                    .foregroundStyle(Theme.Colors.text1)
            }
            .cappedDisplayFont(size: 56)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
            .accessibilityAddTraits(.isStaticText)

            if viewModel.plannedMinutes < viewModel.requestedMinutes {
                // The honest time (decision 17): even the top of the user's rep range and the longest rests
                // cannot fill the request yet, so the session says how long it really runs.
                Text("Runs \(viewModel.plannedMinutes) of your \(viewModel.requestedMinutes) minutes. It fills out as your reps grow.")
                    .font(Theme.Typography.footnote)
                    .foregroundStyle(Theme.Colors.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(subtitle)
                .font(Theme.Typography.lead)
                .foregroundStyle(Theme.Colors.text2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The gap that sets the headline's two lines at Display L's line height (57 for 56 pt) instead of
    /// the font's own, taller one.
    private var headlineLineGap: CGFloat {
        let size = Theme.Typography.cappedDisplaySize(56, relativeTo: .largeTitle, dynamicTypeSize: dynamicTypeSize)
        let natural = UIFont(name: Theme.Typography.FontName.display, size: size)?.lineHeight ?? size
        return size * 57 / 56 - natural
    }

    /// "Push Day: 30 min" - today's Training Day and its honest length, as VoiceOver reads the headline.
    private var title: String {
        guard let day = viewModel.trainingDay else { return "Today: \(viewModel.plannedMinutes) min" }
        return "\(day.displayName): \(viewModel.plannedMinutes) min"
    }

    // MARK: - Rest Day (US-TD05)

    private var restDayScroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                TodayHeader(greeting: greeting, mark: .rest, tone: .rest) {
                    Text(WelcomeCopy.restTitle(for: viewModel.effectivePlan.restReason ?? .cycleComplete))
                        .cappedDisplayFont(size: 56)
                        .foregroundStyle(Theme.Colors.rest)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                }

                if let state = viewModel.resumableSession {
                    ResumeSessionCard(
                        state: state,
                        onResume: {
                            viewModel.sessionWillStart()
                            presentedPlayer = .resume(state)
                        },
                        onDiscard: { Task { await viewModel.discardResumableSession() } }
                    )
                }

                healthSuggestions

                RestDayCard(
                    next: viewModel.effectivePlan.trainingDay,
                    reason: viewModel.effectivePlan.restReason ?? .cycleComplete,
                    onRecovery: {
                        Task {
                            guard let recovery = await viewModel.recoveryWorkout() else { return }
                            viewModel.sessionWillStart()
                            presentedPlayer = .fresh(recovery)
                        }
                    },
                    onTrainAnyway: { Task { await viewModel.trainAnyway() } }
                )

                if let consistency = viewModel.consistency {
                    ConsistencyCard(consistency: consistency)
                }

                outsideActivityCard
            }
            .padding(.horizontal, Theme.Spacing.screenMargin)
            .padding(.top, Theme.Spacing.sm)
            .padding(.bottom, Theme.Spacing.mlg)
        }
    }

    // MARK: - Outside Activity (US-HO04, US-HO05)

    /// The Apple Health workouts offered as "Add it / Ignore", newest first.
    @ViewBuilder
    private var healthSuggestions: some View {
        ForEach(viewModel.healthSuggestions) { candidate in
            HealthSuggestionCard(
                candidate: candidate,
                onAdd: { Task { await viewModel.addHealthSuggestion(candidate) } },
                onIgnore: {
                    appState?.dismissHealthWorkout(candidate.id)
                    viewModel.ignoreHealthSuggestion(candidate)
                }
            )
        }
    }

    private var outsideActivityCard: some View {
        OutsideActivityCard(
            activities: viewModel.recentActivities,
            onLog: { activitySheet = .new },
            onEdit: { activitySheet = .edit($0) }
        )
    }

    private func activitySheetView(_ sheet: ActivitySheet) -> some View {
        let existing: OutsideActivity?
        switch sheet {
        case .new: existing = nil
        case .edit(let activity): existing = activity
        }
        return OutsideActivitySheet(
            existing: existing,
            offersHealthOptIn: appState.map { !$0.healthWorkoutSuggestionsEnabled } ?? false,
            errorMessage: viewModel.activityErrorMessage,
            onSave: { await viewModel.saveActivity($0) },
            onDelete: { activity in
                let deleted = await viewModel.deleteActivity(id: activity.id)
                // A deleted Health workout stays gone: it was the user's call, not a suggestion to repeat.
                if deleted, let healthId = activity.healthWorkoutId { appState?.dismissHealthWorkout(healthId) }
                return deleted
            },
            onEnableHealthSuggestions: enableHealthSuggestions
        )
    }

    /// The Apple Health opt-in (US-HO05): record the choice, ask for read access to workouts, then look.
    private func enableHealthSuggestions() {
        appState?.healthWorkoutSuggestionsEnabled = true
        Task {
            try? await services.healthKitService.requestWorkoutReadAuthorization()
            await refreshHealthSuggestions()
        }
    }

    private func refreshHealthSuggestions() async {
        await viewModel.refreshHealthSuggestions(
            enabled: appState?.healthWorkoutSuggestionsEnabled ?? false,
            dismissed: appState?.dismissedHealthWorkoutIds ?? []
        )
    }

    private var greeting: String {
        let name = viewModel.user?.displayName ?? ""
        return name.isEmpty ? "Ready when you are." : "Ready when you are, \(name)."
    }

    /// The header subtitle *is* the Variety Language line when there is one - the honest "what today
    /// is" contrast the engine produced (US-G03). It falls back to a neutral line for a degenerate
    /// warm-up-only session that has no lead pillar to name.
    /// What today's Training Day works; the pillar contrast line the Variety Language writes has nothing
    /// left to contrast once every session is a strength Training Day.
    private var subtitle: String {
        viewModel.trainingDay?.focusLine ?? viewModel.varietyNote?.text ?? "A complete session, ready to go."
    }

    // MARK: - Duration chips

    /// A non-blocking, one-tap duration selector. Tapping a chip regenerates the session in place on
    /// the sub-100ms engine; the current session and Start stay put while it swaps, so the screen
    /// never gates entry behind a duration question. The row scrolls sideways, edge to edge; at the
    /// accessibility text sizes the chips wrap onto more lines instead (DESIGN "Dynamic Type").
    @ViewBuilder
    private var durationChips: some View {
        if dynamicTypeSize.isAccessibilitySize {
            FlowLayout { chips }
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.sm) { chips }
                    .padding(.horizontal, Theme.Spacing.screenMargin)
            }
            .padding(.horizontal, -Theme.Spacing.screenMargin)
        }
    }

    private var chips: some View {
        ForEach(viewModel.durationChips, id: \.self) { minutes in
            DurationChip(
                minutes: minutes,
                isSelected: minutes == viewModel.selectedMinutes,
                tone: tone
            ) {
                Task { await viewModel.selectDuration(minutes) }
            }
        }
    }

    /// The pinned, visually dominant Start action, in the day's color. It is always present and enabled -
    /// the Ready Screen never gates Start behind an unanswered question. Tapping it opens the
    /// active-session player (US-K01) for the already-generated session.
    private var startBar: some View {
        Button(action: {
            guard let workout = viewModel.workout else { return }
            // Starting fresh while a paused session is still resumable overwrites it in the store, so
            // that paused session is being given up - emit its abandonment before the fresh player's
            // first persist replaces it (US-T10). A no-op when nothing is resumable.
            Task { await viewModel.abandonResumableSessionForOverwrite() }
            viewModel.sessionWillStart()
            presentedPlayer = .fresh(workout)
        }) {
            HStack(spacing: Theme.Spacing.sm) {
                ScaledIcon(icon: .play, size: 22, relativeTo: .headline)
                Text("Start")
                    .font(Theme.Typography.startButton)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: Theme.Spacing.startButtonHeight)
            // Pinned above the tab bar, the label stops growing at accessibility2 so the session list
            // keeps most of a small screen to scroll beneath it (`screens/Z2-Today-AX.html`).
            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        }
        .primaryButtonStyle(tone.color)
        .padding(.horizontal, Theme.Spacing.screenMargin)
        .padding(.top, 10)
        .padding(.bottom, Theme.Spacing.sm)
        .background(Theme.Colors.background)
    }

    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.md) {
            DayMarkView(mark: .sun, color: Theme.Colors.sun, size: 56)
            Text(viewModel.errorMessage ?? "No session yet.")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.text2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button { Task { await viewModel.load() } } label: {
                Text("Try again")
                    .font(Theme.Typography.button)
                    .padding(.horizontal, Theme.Spacing.sm)
                    .frame(minHeight: Theme.Spacing.minTouchTarget)
            }
            .secondaryButtonStyle()
        }
        .padding(Theme.Spacing.screenMargin)
    }
}

// MARK: - Header

/// Today's header: the greeting, the headline the caller supplies, and the day's mark at the top right.
/// The mark is drawn over the header's corner rather than beside it, so the minutes line and the line
/// under it keep the full width; only the greeting leaves room for it. At the accessibility text sizes
/// the mark steps aside entirely, leaving the headline the whole column.
private struct TodayHeader<Headline: View>: View {
    let greeting: String
    let mark: DayMark
    let tone: DayTone
    @ViewBuilder let headline: () -> Headline

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private static var markSize: CGFloat { 60 }

    var body: some View {
        let showsMark = !dynamicTypeSize.isAccessibilitySize
        VStack(alignment: .leading, spacing: 6) {
            Text(greeting)
                .font(Theme.Typography.greeting)
                .foregroundStyle(Theme.Colors.text2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.trailing, showsMark ? Self.markSize + Theme.Spacing.smd : 0)
            headline()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .topTrailing) {
            if showsMark {
                DayMarkView(mark: mark, color: tone.color, size: Self.markSize)
                    .padding(.top, 6)
            }
        }
        .padding(.top, 6)
    }
}

// MARK: - Duration chip

/// A single duration chip in the Ready Screen's one-tap selector. The selected chip fills with the day's
/// color and carries a black label; the touch target meets the 44pt minimum.
private struct DurationChip: View {
    let minutes: Int
    let isSelected: Bool
    let tone: DayTone
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("\(minutes) min")
        }
        .buttonStyle(ChipButtonStyle(isSelected: isSelected, tone: tone.color))
        .accessibilityLabel("\(minutes) minute session")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

// MARK: - Different workout

/// The secondary control that rebuilds today's session at the same length with other moves. An outline
/// button rather than a filled one, so Start stays the one dominant action; it regenerates in place
/// with no spinner and no animation, and its label wraps under large Dynamic Type sizes.
struct DifferentWorkoutButton: View {
    let minutes: Int
    let action: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Button(action: action) {
            // At the accessibility text sizes the icon moves above the label, so the label gets the full
            // width and breaks between words rather than inside them.
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(spacing: Theme.Spacing.xs))
                : AnyLayout(HStackLayout(spacing: Theme.Spacing.sm))
            layout {
                ScaledIcon(icon: .refresh, size: 22, relativeTo: .headline)
                Text("Different workout")
                    .font(Theme.Typography.button)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, Theme.Spacing.sm)
            .frame(maxWidth: .infinity, minHeight: 48)
        }
        .outlineButtonStyle()
        .accessibilityLabel("Different workout")
        .accessibilityHint("Builds another \(minutes) minute workout with other moves.")
    }
}

// MARK: - Classics note (ADR-0007)

/// The one-time note that sessions now focus on the classics, shown on the Ready Screen - the screen
/// whose session changed - to an install that predates the change and whose user is held to staple
/// movements (a beginner or intermediate user in the Discipline Phase). Dismissed with "Got it".
/// Identity-framed: it says what sessions focus on and when more opens up, never that anything was lost.
/// The copy is the captain's, verbatim (`ClassicsUpdateNoteCopy`). Appearing is what persists that it was
/// shown, so a force-quit while it is up does not lose it silently and it never reappears once seen.
struct ClassicsUpdateNote: View {
    /// Called when the note first appears, to persist the one-shot flag.
    let onShow: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.smd) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(ClassicsUpdateNoteCopy.headline)
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.text1)
                    .fixedSize(horizontal: false, vertical: true)
                Text(ClassicsUpdateNoteCopy.detail)
                    .font(Theme.Typography.callout)
                    .foregroundStyle(Theme.Colors.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(ClassicsUpdateNoteCopy.full)

            Button(action: onDismiss) {
                Text("Got it")
                    .font(Theme.Typography.button)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 48)
            }
            .secondaryButtonStyle()
            .accessibilityHint("Dismisses this note")
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.sunTint, in: RoundedRectangle(cornerRadius: Theme.Spacing.cardCornerRadius))
        .accessibilityElement(children: .contain)
        .onAppear(perform: onShow)
    }
}

/// The classics note's copy, one source for the card and the tests that pin it verbatim.
enum ClassicsUpdateNoteCopy {
    static let headline = "Your sessions now focus on the classics."
    static let detail = "More movements unlock when you earn the Strength Phase."
    static var full: String { "\(headline) \(detail)" }
}

// MARK: - Rest Day card

/// Today on a Rest Day (US-TD05, ADR-0012) or a day off an Outside Activity gave: the card says why,
/// offers the optional mobility-only **Recovery** flow, and lets the user **Train anyway**, which starts
/// the next group and forfeits the rest. Rest is framed as part of training, never as a gap.
///
/// Drawn as two cards (`screens/T11-Rest-Day.html`): why today is rest, then Recovery - a `rest` fill,
/// the color of Recovery - over Train anyway.
struct RestDayCard: View {
    let next: TrainingDay
    /// Why today holds no Training Day: the Cycle is done, its Rest Day came early, or an Outside
    /// Activity worked the groups left (decision 21).
    var reason: RestReason = .cycleComplete
    let onRecovery: () -> Void
    let onTrainAnyway: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: Theme.Spacing.smd) {
                Text(WelcomeCopy.restReason(reason, next: next))
                    .font(Theme.Typography.cardTitle)
                    .foregroundStyle(Theme.Colors.text1)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Rest is part of the program - it's where strength is built. Take today off, or loosen up with a five-minute stretch.")
                    .font(Theme.Typography.callout)
                    .foregroundStyle(Theme.Colors.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface()
            .accessibilityElement(children: .combine)

            VStack(spacing: 10) {
                Button(action: onRecovery) {
                    HStack(spacing: Theme.Spacing.sm) {
                        ScaledIcon(icon: .play, size: 22, relativeTo: .headline)
                        Text("Recovery")
                            .font(Theme.Typography.button)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: Theme.Spacing.buttonHeight)
                }
                .primaryButtonStyle(Theme.Colors.rest)
                .accessibilityLabel("Recovery")
                .accessibilityHint("Starts a five-minute stretch. Today stays a \(WelcomeCopy.restTitle(for: reason)).")

                Button(action: onTrainAnyway) {
                    Text("Train anyway")
                        .font(Theme.Typography.button)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 52)
                }
                .secondaryButtonStyle()
                .accessibilityHint("Builds your \(next.displayName) instead of resting today.")

                Text("Builds your \(next.displayName) instead of resting today.")
                    .font(Theme.Typography.footnote)
                    .foregroundStyle(Theme.Colors.text2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
                    .accessibilityHidden(true)
            }
            .padding(Theme.Spacing.md)
            .background(
                EllipticalGradient(
                    stops: [.init(color: Theme.Colors.restTint, location: 0), .init(color: Theme.Colors.surface1, location: 0.7)],
                    center: UnitPoint(x: 0.2, y: 0),
                    startRadiusFraction: 0,
                    endRadiusFraction: 1
                ),
                in: RoundedRectangle(cornerRadius: Theme.Spacing.cardCornerRadius)
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Resume session card

/// The Resume-or-Discard surface for an abandoned session (US-K04): when the user backgrounded out of
/// - or a relaunch interrupted - a session before finishing, it is offered back here rather than
/// silently lost. Resume reopens the player at the exact position; Discard lets the session go. Copy
/// is identity-framed and never guilt-framed. Every control meets the 44pt minimum touch target. The
/// card wears the paused session's Training Day color: its outline, its progress bar and Resume.
private struct ResumeSessionCard: View {
    let state: ActiveSessionState
    let onResume: () -> Void
    let onDiscard: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var tone: DayTone { DayTone(state.workout.trainingDay) }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.smd) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Pick up where you left off")
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.Colors.text1)
                    .fixedSize(horizontal: false, vertical: true)
                Text(positionText)
                    .font(Theme.Typography.callout)
                    .foregroundStyle(Theme.Colors.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // How far into the session the player will reopen; the words above already say it.
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.Colors.surface3)
                    Capsule().fill(tone.color).frame(width: proxy.size.width * progress)
                }
            }
            .frame(height: 8)
            .accessibilityHidden(true)

            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(spacing: 10))
                : AnyLayout(HStackLayout(spacing: 10))
            layout {
                Button(action: onResume) {
                    HStack(spacing: Theme.Spacing.sm) {
                        ScaledIcon(icon: .play, size: 22, relativeTo: .headline)
                        Text("Resume")
                            .font(Theme.Typography.button)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: Theme.Spacing.buttonHeight)
                }
                .primaryButtonStyle(tone.color)
                .accessibilityLabel("Resume session")

                Button(action: onDiscard) {
                    Text("Discard")
                        .font(Theme.Typography.button)
                        .padding(.horizontal, Theme.Spacing.sm)
                        .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : nil)
                        .frame(minHeight: Theme.Spacing.buttonHeight)
                }
                .secondaryButtonStyle()
                .accessibilityLabel("Discard session")
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Spacing.cardCornerRadius)
                .strokeBorder(tone.color, lineWidth: 2)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Session in progress. \(positionText)")
    }

    /// The share of the session's exercises already behind the user.
    private var progress: CGFloat {
        let total = state.slots.count
        guard total > 0 else { return 0 }
        return CGFloat(min(max(state.currentStepIndex, 0), total)) / CGFloat(total)
    }

    /// "You're on Push-up, exercise 3 of 8." - the exact place the player will reopen to. Falls back
    /// to a neutral line for a degenerate (empty) snapshot that names no current exercise.
    private var positionText: String {
        let total = state.slots.count
        guard total > 0, state.slots.indices.contains(state.currentStepIndex) else {
            return "You have a session in progress."
        }
        let name = state.slots[state.currentStepIndex].prescription.exercise.displayName
        return "You're on \(name), exercise \(state.currentStepIndex + 1) of \(total)."
    }
}

// MARK: - Consistency card

/// The "how I'm doing" surface (US-J02): the forgiving Consistency Score, framed by identity and
/// pride, never by loss. The copy leads with who the user *is* ("You're someone who moves.") and
/// surfaces their best on-goal run as earned pride; the score is shown only once there is history,
/// so a brand-new user is never greeted with a discouraging zero. There is no streak-to-break, no
/// "you missed" language, no XP. Drawn as DESIGN's score card: the `sun` numeral left, the overline,
/// headline and footnote right.
private struct ConsistencyCard: View {
    let consistency: Consistency

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// A session or a logged Outside Activity (which counts as showing up) has been recorded.
    private var hasHistory: Bool { consistency.totalWorkoutsCompleted > 0 || consistency.score > 0 }

    var body: some View {
        if hasHistory && !dynamicTypeSize.isAccessibilitySize {
            // DESIGN's score card: the score the Progress tab also reads, in `sun`, beside its words.
            ScoreCard(score: Int(consistency.score.rounded()), headline: Self.headline, footnote: pride)
                .accessibilityLabel(accessibilityText)
        } else {
            stackedCard
        }
    }

    private static let headline = "You're someone who moves."

    /// Before there is a score, the words alone; at the accessibility text sizes, the score stacked above
    /// them, so neither column is squeezed into breaking a word across lines.
    private var stackedCard: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Spacing.sm))
            : AnyLayout(HStackLayout(alignment: .center, spacing: Theme.Spacing.md))
        return layout {
            if hasHistory {
                Text("\(Int(consistency.score.rounded()))")
                    .cappedDisplayFont(Theme.Typography.FontName.displayLarge, size: 76)
                    .monospacedDigit()
                    .foregroundStyle(Theme.Colors.sun)
                    .lineLimit(1)
                    .fixedSize()
            }

            VStack(alignment: .leading, spacing: 3) {
                if hasHistory {
                    Text("Consistency Score".uppercased())
                        .overlineStyle()
                        .foregroundStyle(Theme.Colors.sun)
                        .fixedSize(horizontal: false, vertical: true)
                        // Tracked open, "CONSISTENCY" outgrows a small phone's card at the largest sizes
                        // and would break inside the word; it stops growing where it still fits whole.
                        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                }
                Text(Self.headline)
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.text1)
                    .fixedSize(horizontal: false, vertical: true)
                Text(pride)
                    .font(Theme.Typography.footnote)
                    .foregroundStyle(Theme.Colors.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    /// The earned point of pride - the longest on-goal run ever achieved - or an encouraging,
    /// never-loss-framed line for a user without a run yet.
    private var pride: String {
        guard consistency.longestChain > 0 else {
            return "Every time you show up counts - even five minutes."
        }
        let run = CountWording.phrase(consistency.longestChain, singular: "week", plural: "weeks")
        return "Best run: \(run) on goal."
    }

    private var accessibilityText: String {
        hasHistory
            ? "You're someone who moves. Consistency \(Int(consistency.score.rounded())). \(pride)"
            : "You're someone who moves. \(pride)"
    }
}

// MARK: - Policy note card

/// The "what the app changed" surface (US-J02): the honest, templated note the Programmer attached
/// to the last real change (US-F04/US-G03). It only ever appears when a note exists, and only ever
/// names a change the sessions actually reflect. Rendered as a quiet card with the `sun` spark, never a nag.
private struct PolicyNoteCard: View {
    let note: SessionPolicy.Note

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.smd) {
            ScaledIcon(icon: .spark, size: 22, relativeTo: .body)
                .foregroundStyle(Theme.Colors.sun)
            Text(note.text)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.text1)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("What changed: \(note.text)")
    }
}

// MARK: - Block card

/// One session block (warm-up / training / cooldown) with its prescribed exercises and targets: an
/// overline naming the block - in the day's color for the training block - over rows split by 1 pt
/// `line` separators.
private struct BlockCard: View {
    let block: WorkoutBlock
    let tone: DayTone

    private var isTraining: Bool { block.category == .strength || block.category == .primal }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(block.title.uppercased())
                .overlineStyle()
                .foregroundStyle(isTraining ? tone.color : Theme.Colors.text2)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(block.title)

            VStack(spacing: 0) {
                ForEach(Array(block.exercises.enumerated()), id: \.element.id) { index, prescription in
                    ExerciseRow(prescription: prescription)
                    if index < block.exercises.count - 1 {
                        GroupSeparator()
                    }
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }
}

private struct ExerciseRow: View {
    let prescription: PrescribedExercise

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        // At the accessibility text sizes the target stacks under the name (DESIGN: name above value).
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Spacing.xs))
            : AnyLayout(HStackLayout(alignment: .center, spacing: Theme.Spacing.smd))
        layout {
            Text(prescription.exercise.displayName)
                .font(Theme.Typography.rowName)
                .foregroundStyle(Theme.Colors.text1)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(targetText)
                .font(Theme.Typography.listValue)
                .monospacedDigit()
                .foregroundStyle(Theme.Colors.text1)
                .multilineTextAlignment(dynamicTypeSize.isAccessibilitySize ? .leading : .trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, Theme.Spacing.sm)
        .frame(minHeight: 52)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(prescription.exercise.displayName), \(spokenTarget)")
    }

    /// "3 × 12" for rep-based movements, "3 × 0:30" for holds, each with " per side" where the target is
    /// per side - the same prescription the player shows, so the preview cannot describe a slot
    /// differently from the screen the user then works it on. Shared with the player rather than
    /// re-derived, because a second copy is how the two drifted apart before.
    private var targetText: String {
        ActiveSessionView.targetText(prescription)
    }

    /// The spoken form, which spells the nouns out instead of reading the "×" glyph aloud.
    private var spokenTarget: String {
        ActiveSessionView.targetAccessibilityText(prescription)
    }
}

#Preview {
    ReadyView(services: .mock())
}
