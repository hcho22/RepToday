import SwiftUI
import UIKit

/// The active-session player (US-K01) - a focused, one-exercise-at-a-time screen that walks the user
/// through the generated session so they never lose their place.
///
/// It renders the current exercise's demo, target, and set tracking, and advances as each set is
/// completed. Every interactive control meets the 60pt active-screen touch target; every color, font,
/// and dimension comes from `Theme`. The rest timer between sets (US-K02), the in-session swap
/// (US-K03), background/resume (US-K04), and the post-session summary + log write (US-L01/L02) build
/// on this same view and view model.
///
/// There is deliberately **no running session clock** anywhere in the player (US-O03) - not in the top
/// bar, not on the rest overlay. A total ticking up in the corner turns the session into something to
/// get through and pulls attention off the movement; the total is revealed once, on the completion
/// summary. What replaces it is a clock that actually helps: a per-exercise Hold Timer on timed
/// movements, which counts one side of the hold down and records the set at zero, and - since US-CC01 -
/// an auto-advancing work window on rep-based training sets, which counts the set's planned per-set
/// seconds down and records it at zero with no tap, offering a quiet **Done** to advance early. Every
/// **hold auto-starts hands-free** too (US-CC05 for the bookends, ADR-0010 for training holds) - no
/// Start-hold tap, a per-side hold flowing side 1 -> a brief "Switch sides" beat -> side 2 with no tap -
/// and a rep-based warm-up / cooldown move runs on the same kind of window, so once a session starts it
/// needs no tap at all; Pause, Done, Skip, Swap, Stop hold and + More time are optional.
struct ActiveSessionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    /// The persisted one-shot flag for the first-run explainer (US-CC13). Declared optional so the
    /// player still renders when hosted without an `AppState` in the environment (the evidence-test
    /// surfaces do exactly that); production always provides one, so the explainer only ever runs
    /// where the flag can be read and written.
    @Environment(AppState.self) private var appState: AppState?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.legibilityWeight) private var legibilityWeight
    @State private var viewModel: ActiveSessionViewModel

    /// The session's Trainer (US-TP06) and whether the one-time choice must be asked first (US-TP10).
    @State private var trainerSession: TrainerSessionModel

    /// Drives the one-time Trainer choice overlay (US-TP10) for a user whose effective Trainer is
    /// unresolved. Shown before the session starts, before any Trainer art and before the US-CC13
    /// explainer, never stacked with it.
    @State private var showTrainerChoice = false

    /// Drives the first-run explainer overlay (US-CC13). Set once, on first arrival at the player, and
    /// only when the persisted one-shot flag says it has never been shown.
    @State private var showExplainer = false

    /// Whether this arrival holds the session's start for the first-run explainer (ADR-0010): the
    /// card shows *before* the session starts and its button starts it, so it never pauses a running
    /// session. Decided once, on first arrival, while the one-shot flag says it has never been shown
    /// (a missing `AppState`, as on hosted evidence surfaces, never shows it).
    @State private var startsAfterExplainer = false

    /// The height of the player's visible scroll area, and of everything in its column but the exercise
    /// card, measured so the card can fit a short screen (`cardHeight`). Unmeasured, there is room.
    @State private var scrollHeight = CGFloat.infinity
    @State private var heightAroundCard: CGFloat = 0

    /// The height of the timer (and any stacked actions) at the foot of the column, measured so the
    /// card is fitted to the room left above it.
    @State private var heightBelowColumn: CGFloat = 0

    /// Whether the running timer is in its last three seconds, as the timer reports it, so Done can
    /// turn `sun` with it.
    @State private var isTimerInLastSeconds = false

    /// The width the completion screen is laid out in. Unmeasured, it is roomy.
    @State private var completionWidth = CGFloat.infinity

    /// The height the player is laid out in, below the status bar - what tells a short screen
    /// (`isCompactColumn`). Unmeasured, the screen is tall.
    @State private var playerHeight = CGFloat.infinity

    /// The width the player is laid out in - what tells whether the secondary row fits
    /// (`stacksSecondaryActions`). Unmeasured, it fits.
    @State private var playerWidth = CGFloat.infinity

    /// Reports, as the player dismisses, whether the session completed (US-K04). The Ready Screen uses
    /// this to refresh the resumable session *without* racing the store's completion clear: a completed
    /// session leaves nothing resumable, while an abandoned one is re-read from the store.
    private let onFinish: ((Bool) -> Void)?

    /// Start a fresh session for `workout`. When `store` and `userId` are supplied, the player
    /// persists its progress so it survives backgrounding and relaunch (US-K04). `userService` lets the
    /// player follow the freshest stored Trainer and save the one-time Trainer choice (US-TP10).
    init(
        workout: Workout,
        workoutEngine: (any WorkoutEngineProtocol)? = nil,
        user: User? = nil,
        recentLogs: [WorkoutLog] = [],
        sessionPolicy: SessionPolicy = .default,
        store: (any ActiveSessionStore)? = nil,
        userId: String? = nil,
        completionService: (any SessionCompletionServiceProtocol)? = nil,
        analytics: (any AnalyticsServiceProtocol)? = nil,
        userService: (any UserServiceProtocol)? = nil,
        onFinish: ((Bool) -> Void)? = nil
    ) {
        self.onFinish = onFinish
        _trainerSession = State(initialValue: TrainerSessionModel(profile: user?.profile, userService: userService))
        _viewModel = State(
            initialValue: ActiveSessionViewModel(
                workout: workout,
                swapEngine: workoutEngine,
                user: user,
                recentLogs: recentLogs,
                sessionPolicy: sessionPolicy,
                store: store,
                userId: userId,
                completionService: completionService,
                analytics: analytics
            )
        )
    }

    /// Resume an abandoned session from its persisted snapshot (US-K04), restoring the exact position,
    /// completed work, elapsed-time origin, and rest timer.
    init(
        resuming state: ActiveSessionState,
        workoutEngine: (any WorkoutEngineProtocol)? = nil,
        user: User? = nil,
        recentLogs: [WorkoutLog] = [],
        sessionPolicy: SessionPolicy = .default,
        store: (any ActiveSessionStore)? = nil,
        userId: String? = nil,
        completionService: (any SessionCompletionServiceProtocol)? = nil,
        analytics: (any AnalyticsServiceProtocol)? = nil,
        userService: (any UserServiceProtocol)? = nil,
        onFinish: ((Bool) -> Void)? = nil
    ) {
        self.onFinish = onFinish
        _trainerSession = State(initialValue: TrainerSessionModel(profile: user?.profile, userService: userService))
        _viewModel = State(
            initialValue: ActiveSessionViewModel(
                state: state,
                swapEngine: workoutEngine,
                user: user,
                recentLogs: recentLogs,
                sessionPolicy: sessionPolicy,
                store: store,
                userId: userId,
                completionService: completionService,
                analytics: analytics
            )
        )
    }

    /// Dismiss the player, first reporting whether the session completed so the Ready Screen can
    /// refresh deterministically rather than racing the store (US-K04). Every dismiss path routes
    /// through here, so the completion signal is never missed.
    ///
    /// A running hold needs no handling here: it is never persisted, so leaving the screen ends it and
    /// the resumed session comes back owing the same side (US-O03). The dismissal is reported only once
    /// the last queued write has landed, so the Ready Screen's resume card reflects the position the
    /// user actually left rather than the one before it.
    private func close() {
        // US-T10: report the session's end at this one dismiss choke point, before dismissing. A
        // completed session emits `session_completed` here, reading the final play state - including
        // any perceived-difficulty rating the user just gave on the completion screen. A dismiss that
        // leaves the session resumable is a *pause*, not an abandonment, so it emits nothing here; the
        // abandonment fires only on a true give-up (Discard / overwrite) from the Ready Screen.
        viewModel.recordSessionEnd()
        let pendingWrite = viewModel.persistenceTask
        let completed = viewModel.isComplete
        let report = onFinish
        Task { @MainActor in
            await pendingWrite?.value
            report?(completed)
        }
        dismiss()
    }

    /// Start the session: its clock, its first window or hold, and the resume of a rest a snapshot
    /// restored paused. Idempotent (`start()` keeps the original origin), so a re-appearing view, the
    /// Trainer choice or the explainer's button can call it safely.
    ///
    /// A rest paused on backgrounding and restored from a snapshot (US-K04) never sees a scene-phase
    /// change when the resumed player is presented on an already-active app, so it is resumed here too.
    /// A no-op unless a rest is currently paused, leaving a fresh session and a resumed running rest
    /// untouched. There is deliberately no `resumeHold` counterpart (US-O03): a hold is never restored as
    /// a countdown at all, so there is nothing frozen to un-freeze - and un-freezing one here is
    /// precisely how a leg the user abandoned days ago used to finish itself moments after the screen
    /// appeared, banking a set nobody performed.
    private func startSession() {
        viewModel.start()
        viewModel.resumeRest(asOf: Date())
    }

    /// Present the first-run explainer over the not-yet-started session (ADR-0010), flipping its
    /// one-shot flag (US-CC13) the moment it shows - not on dismissal, so a force-quit while it is up can
    /// never bring it back, and not before, so a force-quit behind an earlier Trainer choice keeps it
    /// for the next arrival. The entrance is animated unless Reduce Motion is on, in which case it
    /// appears in place with no transition.
    private func presentExplainer() {
        appState?.markContinuousCircuitExplainerSeen()
        if reduceMotion {
            showExplainer = true
        } else {
            withAnimation(.easeOut(duration: 0.25)) { showExplainer = true }
        }
    }

    /// Decide, on each arrival, what to show before the session starts (US-TP10, decision 15; ADR-0010):
    /// the one-time Trainer choice first when the user's Trainer is unresolved, then the first-run
    /// explainer when this arrival is holding the start for it - never both at once, and the last one
    /// shown starts the session, so no tap is ever asked of a running session.
    ///
    /// A user whose snapshot is unresolved is held before the start while the freshest stored profile
    /// is read: a Trainer chosen in Settings or on an earlier arrival then resolves it with no prompt,
    /// and only a still-unresolved user is asked. That holds on every arrival the Trainer is still
    /// unresolved, including after a force-quit before choosing or a choice whose write failed (captain,
    /// Open Question 8). Everyone else goes straight on, and the re-read runs behind it so a Trainer
    /// switched in Settings since the Ready Screen loaded is the one this session shows.
    private func handleArrival() {
        if trainerSession.needsChoice {
            Task { @MainActor in
                if await trainerSession.refreshOnArrival() {
                    presentTrainerChoice()
                } else {
                    startOrPresentExplainer()
                }
            }
        } else {
            startOrPresentExplainer()
            Task { @MainActor in _ = await trainerSession.refreshOnArrival() }
        }
    }

    /// The last step before the session plays: the first-run explainer when this arrival is holding the
    /// start for it (its button then starts the session), otherwise the start itself.
    private func startOrPresentExplainer() {
        if startsAfterExplainer {
            presentExplainer()
        } else {
            startSession()
        }
    }

    /// Show the Trainer choice over the not-yet-started player, stilled under Reduce Motion.
    private func presentTrainerChoice() {
        if reduceMotion {
            showTrainerChoice = true
        } else {
            withAnimation(.easeOut(duration: 0.25)) { showTrainerChoice = true }
        }
    }

    /// Use the chosen Trainer at once, dismiss the choice, then start the session - or let the
    /// explainer follow if it is holding the start, and start it from there. The write runs in the
    /// background: if it fails the session keeps the chosen Trainer and, since nothing was stored, the
    /// next arrival asks again before its start (captain, Open Question 8).
    private func chooseTrainer(_ trainer: Trainer) {
        trainerSession.choose(trainer)
        if reduceMotion {
            showTrainerChoice = false
        } else {
            withAnimation(.easeIn(duration: 0.2)) { showTrainerChoice = false }
        }
        startOrPresentExplainer()
    }

    /// The explainer's button: dismiss it, honoring Reduce Motion the same way the entrance does, and
    /// start the session it was holding (ADR-0010). The card was shown before anything started, so the
    /// timer never stopped for it.
    private func dismissExplainer() {
        startsAfterExplainer = false
        startSession()
        if reduceMotion {
            showExplainer = false
        } else {
            withAnimation(.easeIn(duration: 0.2)) { showExplainer = false }
        }
    }

    /// Toggle the explicit user pause (US-CC06): freeze the live countdown, or resume it from its exact
    /// remainder. Reads the wall clock the same way the scene-phase background pause does; the view model
    /// keeps all countdown arithmetic pure over the injected clock behind it.
    private func togglePause() {
        if viewModel.isUserPaused {
            viewModel.resume(asOf: Date())
        } else {
            viewModel.pause(asOf: Date())
        }
    }

    var body: some View {
        // The width the screen offers, read off a reader whose size is what its parent proposes. A
        // player measuring itself - or anything sized by the stack around it - could read back a row its
        // own overflow had widened and keep laying that row out side by side, past the screen's edges.
        GeometryReader { _ in
            session
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { playerWidth = $0 }
    }

    private var session: some View {
        ZStack {
            Theme.Colors.background.ignoresSafeArea()

            // Exercise and rest swap in one cut, so the outgoing screen never lingers in VoiceOver's
            // tree beside the incoming one; the rest screen's next movement then rises in (`RiseIn`).
            if viewModel.isComplete {
                completionState
            } else if viewModel.isResting {
                RestView(viewModel: viewModel, tone: tone, width: playerWidth) { close() }
            } else {
                player
            }

            // The first-run explainer (US-CC13) rides above the player as its own layer rather than a
            // sheet, so the entrance animation can be stilled under Reduce Motion. It shows before the
            // session starts and its button starts it (ADR-0010), so it never pauses a running session.
            if showExplainer {
                ContinuousCircuitExplainerView(onDismiss: dismissExplainer)
                    .transition(.opacity)
                    .zIndex(1)
            }

            // The one-time Trainer choice (US-TP10), layered the same way and likewise shown before the
            // session starts. `handleArrival` never shows it together with the explainer: the choice
            // comes first and the explainer follows it.
            if showTrainerChoice {
                TrainerChoiceView(
                    exerciseId: viewModel.currentStep?.prescription.exercise.id ?? "",
                    onChoose: chooseTrainer
                )
                .transition(.opacity)
                .zIndex(2)
            }
        }
        // Every card and rest preview below reads the session's Trainer from here (US-TP06/US-TP08), and
        // takes the session's color.
        .environment(\.trainer, trainerSession.trainer)
        .environment(\.dayTone, tone)
        .onAppear {
            // The first time, the explainer holds the start: the card shows over the not-yet-started
            // session and its button starts it (ADR-0010). An unresolved Trainer holds it the same way
            // on every arrival (`handleArrival`). Every other arrival starts at once. A re-appearing view
            // while the card is still up keeps holding. In-session backgrounding pauses and resumes every
            // countdown through `scenePhase` below.
            if !startsAfterExplainer, !showExplainer {
                startsAfterExplainer = appState?.shouldShowContinuousCircuitExplainer ?? false
            }
            handleArrival()
            // The user puts the phone down mid-plank; the screen must not lock out from under a
            // running countdown, or its cue never lands. Scoped to the session being played, and
            // released the moment it finishes or the player is dismissed.
            UIApplication.shared.isIdleTimerDisabled = !viewModel.isComplete
        }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        // The celebration screen has no countdown to protect, and the player is not dismissed when the
        // session ends - so completion, not only dismissal, is what hands the screen back to auto-lock.
        .onChange(of: viewModel.isComplete) { _, isComplete in
            if isComplete { UIApplication.shared.isIdleTimerDisabled = false }
        }
        // Pause both countdowns while the app is away so neither blows past - and so a hold's cue can
        // never fire at a screen the user is not looking at; resume on return. The elapsed session
        // clock is wall-clock derived (US-K01) and intentionally keeps running, unseen (US-O03). A
        // return to the foreground never un-freezes a *user* pause (US-CC06): `resumeFromForeground`
        // leaves an explicit Pause held until the user taps Resume, so backgrounding a paused session
        // and coming back keeps it paused.
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                viewModel.resumeFromForeground(asOf: Date())
            case .inactive, .background:
                viewModel.pauseForBackground(asOf: Date())
            @unknown default:
                break
            }
        }
    }


    // MARK: - Player

    /// The session's color (DESIGN "Color"): its Training Day's, `rest` for a Recovery flow, `sun` for a
    /// session from before Training Days. Start, Done, the timer and the progress bars all use it.
    private var tone: DayTone {
        Self.tone(for: viewModel.workout)
    }

    /// The color a session takes: its Training Day's, or `rest` for a Recovery flow (every station a
    /// recovery stretch), or `sun` for an older session that names no day.
    static func tone(for workout: Workout) -> DayTone {
        if let day = workout.trainingDay { return DayTone(day) }
        let roles = workout.blocks.flatMap(\.exercises).compactMap(\.role)
        return !roles.isEmpty && roles.allSatisfy { $0 == .recovery } ? .rest : .sun
    }

    /// The exercise screen (DESIGN "Session screen layout"): the top bar; the block overline; the
    /// Trainer stage; the movement name with its target on the same baseline; the round tracker; then,
    /// one column gap below, the workout timer - with Done and the quiet actions pinned below. A roomy
    /// phone leaves its spare height under the timer, above the pinned actions. On a short screen or at
    /// large text the column scrolls beneath the pinned actions, the stage first shrinking to fit; the
    /// timer is never drawn under the art or the controls.
    private var player: some View {
        VStack(spacing: 0) {
            SessionTopBar(
                onClose: close,
                progress: viewModel.progress,
                segments: viewModel.currentStep?.total ?? 1,
                tone: tone.color,
                canPause: viewModel.canUserPause,
                isPaused: viewModel.isUserPaused,
                onTogglePause: togglePause
            )

            if let step = viewModel.currentStep {
                let cardHeight = cardHeight
                let rhythm = isCompactColumn ? Self.compactColumnRhythm : Self.columnRhythm
                let stacksActions = stacksSecondaryActions
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        VStack(alignment: .leading, spacing: rhythm) {
                            blockContext(step)
                            // The card belongs to the Trainer's poses in every state (ADR-0008): the rep
                            // work window, a running or idle hold, a rep-based stretch. The timer sits
                            // below, so starting one never changes what the card shows. The no-art mark
                            // pulses only on an idle card, as the demo slot always did.
                            ExerciseDemoView(
                                prescription: step.prescription,
                                height: cardHeight,
                                animatesGlyph: !(viewModel.isHolding || viewModel.currentStepAutoAdvances)
                            )
                            exerciseHeadline(step)
                            if let cue = step.prescription.exercise.cue {
                                exerciseCue(cue)
                            }
                            setTracker(step)
                        }
                        .dynamicTypeSize(...Self.columnTypeCap)
                        // Measured without the card, so the card can be fitted to what is left.
                        .onGeometryChange(for: CGFloat.self) { $0.size.height - cardHeight } action: { height in
                            if Self.isMeasurementChange(height, from: heightAroundCard) { heightAroundCard = height }
                        }

                        // The timer follows the content above at the column's rhythm; whatever height
                        // a roomy phone has left over stays below it.
                        Color.clear.frame(height: rhythm)

                        VStack(alignment: .leading, spacing: rhythm) {
                            timer
                                .dynamicTypeSize(...Self.columnTypeCap)
                            if stacksActions {
                                stackedSecondaryActions
                            }
                        }
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                            if Self.isMeasurementChange(height, from: heightBelowColumn) { heightBelowColumn = height }
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.screenMargin)
                    .padding(.top, rhythm)
                    .padding(.bottom, Self.columnBottomPadding)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { scrollHeight = $0 }
            }

            controls
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { playerHeight = $0 }
        // A swap on a hold ends the leg and lands on the substitute idle; re-arm the hands-free
        // auto-start once the swap settles (US-CC05), mirroring how `WorkWindowCountdownView` re-arms the
        // work window - the view stays mounted through a swap, so no fresh `onAppear` fires. Keyed on the
        // settled-swap counter rather than `isSwapping`, which a fast swap toggles inside one update. A
        // no-op off the hold path (`autoStartHoldIfNeeded` guards on `canAutoStartHold`).
        .onChange(of: viewModel.settledSwapCount) { _, _ in
            viewModel.autoStartHoldIfNeeded()
        }
    }

    /// The exercise card's height: two square poses across the column while it fits the visible scroll
    /// area. A short screen (375x667 pt) has no room for that, so the card and its poses shrink
    /// (decision 24), as the rest preview's do (decision 12), until the name, the round tracker and the
    /// timer clear the controls. The short screen's column also runs at its tight rhythm
    /// (`isCompactColumn`) at every station, so its spacing never changes from one to the next.
    private var cardHeight: CGFloat {
        let natural = ExerciseDemoView.naturalHeight(width: playerWidth - 2 * Theme.Spacing.screenMargin)
        let rhythm = isCompactColumn ? Self.compactColumnRhythm : Self.columnRhythm
        // The column above the card and the gap above the timer each take one rhythm.
        let room = scrollHeight - heightAroundCard - heightBelowColumn - 2 * rhythm - Self.columnBottomPadding
        return min(natural, ExerciseDemoView.fittedHeight(room: room))
    }

    /// Whether the column runs at its tight rhythm (its gaps and the round tracker's gaps between its
    /// lines): on a short screen, always. A roomy phone always keeps the full rhythm.
    private var isCompactColumn: Bool {
        playerHeight < Self.shortScreenHeight
    }

    /// The movement name and target on a short screen (DESIGN `Z1-Exercise-375`).
    private static let compactNameFont = ThemeFont(Theme.Typography.FontName.display, size: 28, relativeTo: .largeTitle)
    private static let compactTargetFont = ThemeFont(Theme.Typography.FontName.display, size: 24, relativeTo: .title)

    /// The largest text size the column above the pinned actions - the overline, the stage's labels, the
    /// title row, the round tracker and the timer's label - draws at (DESIGN `Z2-Exercise-AX`): past it
    /// they stop growing and keep wrapping, so at every accessibility size the timer opens whole above
    /// Done with no scrolling, even on a 375x667 screen.
    static let columnTypeCap = DynamicTypeSize.xxxLarge

    /// The column's gap between its pieces, and above the first: full, and tight on a short screen.
    private static let columnRhythm = Theme.Spacing.smd
    private static let compactColumnRhythm = Theme.Spacing.sm

    /// The room under the timer before the pinned controls.
    private static let columnBottomPadding = Theme.Spacing.sm

    /// The round tracker's gap between its lines (its label, any side line and its dots): full, and
    /// tight on a short screen.
    private static let trackerGap = Theme.Spacing.sm
    private static let compactTrackerGap = Theme.Spacing.xs

    /// Below this player height the screen is short (an iPhone SE's 647 pt under its status bar); every
    /// larger phone is laid out taller and never tightens the rhythm.
    private static let shortScreenHeight: CGFloat = 700

    /// The smallest change in a measured height worth acting on: far below a pixel, far above the
    /// floating-point noise between two layouts of the same column.
    private static let measurementTolerance: CGFloat = 0.01

    /// Whether `measured` is a real change from the `stored` height around the card. Two layouts of the
    /// same column can measure a hair apart (iOS 18: 189.66666666666669, then 189.66666666666663), and
    /// feeding that noise back into the card's height would relayout forever.
    static func isMeasurementChange(_ measured: CGFloat, from stored: CGFloat) -> Bool {
        abs(measured - stored) > measurementTolerance
    }

    /// The block this exercise belongs to and its position across the session ("WARM-UP · 1 OF 8"), an
    /// overline in the session's color.
    private func blockContext(_ step: ActiveSessionViewModel.Step) -> some View {
        Text("\(step.blockTitle) · \(step.position) of \(step.total)".uppercased())
            .overlineStyle()
            .foregroundStyle(tone.color)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel("\(step.blockTitle), exercise \(step.position) of \(step.total)")
    }

    /// The movement name (Bricolage 34, 28 on a short screen) with its target (30, 24 on a short screen)
    /// in the session's color on the same baseline (`MovementTitleRow`).
    private func exerciseHeadline(_ step: ActiveSessionViewModel.Step) -> some View {
        // The per-side targets are the longest strings this line renders; the row wraps them rather than
        // truncating away the part that says how much work the set actually is.
        MovementTitleRow(
            name: step.prescription.exercise.displayName,
            target: Self.targetText(step.prescription),
            nameFont: isCompactColumn ? Self.compactNameFont : Theme.Typography.largeTitle,
            targetFont: isCompactColumn ? Self.compactTargetFont : Theme.Typography.target,
            targetColor: tone.color,
            width: playerWidth - 2 * Theme.Spacing.screenMargin
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(step.prescription.exercise.displayName), \(Self.targetAccessibilityText(step.prescription))")
    }

    /// The movement's one coaching line (`Exercise.cue`), quiet under its name - the Standard Push-Up's
    /// easier options for someone who cannot yet do a full push-up. It sits inside the measured column, so
    /// the Trainer card shrinks to make room for it rather than pushing the timer under the controls.
    private func exerciseCue(_ cue: String) -> some View {
        Text(cue)
            .font(Theme.Typography.callout)
            .foregroundStyle(Theme.Colors.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Set tracking, with a pip per set: done pips filled in the session's color, the current one a ring,
    /// the rest on `surface3`. Inside a training-block circuit the label reads "Round N of M" (US-CC02) -
    /// the block rotates one set of each exercise per round, and a station's r-th set is round r, so the
    /// pips still track this exercise's own progress; a linear warm-up / cooldown bookend keeps "Set N of
    /// M". A per-side hold names the side too, because its set is two legs and the timer only counts one
    /// of them at a time - without it the user has no way to tell a finished set from a half-finished one.
    private func setTracker(_ step: ActiveSessionViewModel.Step) -> some View {
        let sides = viewModel.holdSidesPerSet
        let showsSide = viewModel.holdSecondsPerSide != nil && sides > 1
        let progressText: String = {
            if let round = viewModel.currentRound, let rounds = viewModel.circuitRoundCount {
                return "Round \(round) of \(rounds)"
            }
            return "Set \(viewModel.currentSet) of \(step.prescription.sets)"
        }()
        let sideText = "Side \(viewModel.holdSide) of \(sides)"
        let label = Text(progressText)
            .font(Theme.Typography.calloutSemiBold)
            .foregroundStyle(Theme.Colors.textSecondary)
            // "Round N of M" / "Set N of M" wraps rather than truncating at the largest Dynamic Type
            // sizes (US-CC14, AC3).
            .fixedSize(horizontal: false, vertical: true)
        let pips = HStack(spacing: 6) {
            ForEach(0..<step.prescription.sets, id: \.self) { index in
                pip(state: index < viewModel.currentSet - 1 ? .done : (index == viewModel.currentSet - 1 ? .current : .ahead))
            }
        }

        // The tracker's lines tighten with the column (`isCompactColumn`), staying evenly spaced as one
        // group on a short screen.
        return VStack(alignment: .leading, spacing: isCompactColumn ? Self.compactTrackerGap : Self.trackerGap) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    label
                    pips
                }
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    label
                    pips
                }
            }

            if showsSide {
                Text(sideText)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement()
        .accessibilityLabel(showsSide ? "\(progressText), side \(viewModel.holdSide) of \(sides)" : progressText)
    }

    private enum PipState { case done, current, ahead }

    /// One 14 pt pip of the round tracker.
    private func pip(state: PipState) -> some View {
        Circle()
            .fill(state == .done ? tone.color : (state == .current ? Theme.Colors.black : Theme.Colors.surface3))
            .overlay {
                if state == .current { Circle().strokeBorder(tone.color, lineWidth: 3) }
            }
            .frame(width: 14, height: 14)
    }

    /// The workout timer for the step: the work window's countdown on a rep-based set, the running
    /// hold's on a timed one, or - before a hold leg starts, as after "Stop hold" - the hold's full time,
    /// still. A step with neither shows no timer.
    @ViewBuilder
    private var timer: some View {
        if viewModel.isHolding {
            HoldCountdownView(viewModel: viewModel, tone: tone.color, isInLastSeconds: $isTimerInLastSeconds)
        } else if viewModel.currentStepAutoAdvances {
            WorkWindowCountdownView(viewModel: viewModel, tone: tone.color, isInLastSeconds: $isTimerInLastSeconds)
        } else if let seconds = viewModel.holdSecondsPerSide {
            // Still, so VoiceOver has nothing to count: Start hold below is what it offers.
            WorkoutTimerView(
                kind: .hold(target: nil), remaining: seconds, total: seconds,
                label: "Hold", spokenName: "Hold", tone: tone.color,
                isPaused: false, isRunning: false
            )
            .accessibilityHidden(true)
        }
    }

    /// The primary action plus the quieter secondary row - all meeting the 60pt active-screen touch
    /// target. Which primary action shows depends on the movement (ADR-0010): a rep-based exercise,
    /// warm-up and cooldown moves included, runs on its work window with **Done** to move on early; a
    /// timed one starts on its own and shows "Stop hold" while its leg runs ("Start hold" only while no
    /// leg runs, as after "Stop hold"). Either way the countdown records its own set at zero, so the
    /// timer rather than a tap is what advances it - with a timed one's completion still offered as a
    /// quiet slot in the row below (running leg included), so coming out early banks the work instead
    /// of losing it to a skip. Swapping (US-K03) replaces the current movement with a
    /// same-pillar/pattern peer, or, when none is safe and in budget, surfaces an honest "no
    /// alternative" notice above the actions.
    ///
    /// Which *slots* the secondary row carries is decided by the exercise, never by whether a hold
    /// happens to be running: starting one dims controls in place rather than removing them, so the
    /// row never reflows under the user's thumb mid-tap.
    private var controls: some View {
        VStack(spacing: Theme.Spacing.xs) {
            if viewModel.noSwapAlternative, !stacksSecondaryActions {
                noAlternativeNotice
                    .padding(.bottom, Theme.Spacing.xs)
            }

            primaryAction

            if !stacksSecondaryActions {
                HStack(spacing: Theme.Spacing.xs) {
                    secondaryActions
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.screenMargin)
        .padding(.top, Theme.Spacing.xs)
        .padding(.bottom, Theme.Spacing.sm)
        .background(Theme.Colors.background)
    }

    /// The secondary row's controls stacked as full-width rows in the scrolling column, below the timer,
    /// for when they no longer fit side by side (`stacksSecondaryActions`). The "no alternative" notice
    /// travels with them, since it answers the Swap among them.
    private var stackedSecondaryActions: some View {
        VStack(spacing: Theme.Spacing.sm) {
            if viewModel.noSwapAlternative {
                noAlternativeNotice
            }
            secondaryActions
        }
    }

    /// Whether the secondary row gives up its side-by-side columns: when the columns cannot each hold the
    /// longest word of their title, the row would break words in two at large Dynamic Type sizes and grow
    /// past the screen, so its controls move into the scrolling column as full-width rows instead and only
    /// the primary action stays pinned. At accessibility sizes the pinned area holds only the primary
    /// action, so the timer keeps its room above it (DESIGN `Z2-Exercise-AX`). A roomy screen at the
    /// default sizes keeps the row.
    private var stacksSecondaryActions: Bool {
        dynamicTypeSize.isAccessibilitySize || !Self.secondaryRowFits(
            titles: secondaryTitles,
            width: playerWidth - 2 * Theme.Spacing.screenMargin,
            size: dynamicTypeSize,
            weight: legibilityWeight
        )
    }

    /// The titles the secondary row can show at this step, one per slot. "+ More time" is measured
    /// whether or not the step's countdown runs right now, and a swap in flight by its resting "Swap",
    /// so starting or stopping a hold or a swap never moves the controls between the row and the column.
    private var secondaryTitles: [String] {
        var titles = [Self.moreTimeTitle]
        if viewModel.canSwap { titles.append("Swap") }
        if viewModel.holdSecondsPerSide != nil { titles.append(completeButtonTitle) }
        titles.append("Skip")
        return titles
    }

    /// "+ More time"'s visible title, a no-break space holding the "+" to "More" so a narrow column wraps
    /// it "+ More" / "time" rather than orphaning the "+"; `longestWordWidth` splits only at a breaking
    /// space, so it measures "+ More" as the one word it draws. VoiceOver reads "More time".
    static let moreTimeTitle = "+\u{00A0}More time"

    /// The gap between two quiet actions in the row.
    static let secondaryRowSpacing = Theme.Spacing.xs

    /// Whether `titles` fit side by side in `width`: each column at least as wide as the longest word of
    /// its title (`longestWordWidth`), set in the quiet actions' type at `size` and `weight`.
    static func secondaryRowFits(titles: [String], width: CGFloat, size: DynamicTypeSize, weight: LegibilityWeight?) -> Bool {
        guard width.isFinite, !titles.isEmpty else { return true }
        let words = titles.reduce(0) { $0 + longestWordWidth($1, size: size, weight: weight) }
        return words + CGFloat(titles.count - 1) * secondaryRowSpacing <= width
    }

    /// The width of the longest word of a secondary control's `title` at `size` and `weight`: the
    /// narrowest its column may be, so the word is never broken across lines.
    static func longestWordWidth(_ title: String, size: DynamicTypeSize, weight: LegibilityWeight?) -> CGFloat {
        title.split(separator: " ").map { textWidth(String($0), style: .quietAction, size: size, weight: weight) }.max() ?? 0
    }

    /// The session's text styles whose drawn width decides between side-by-side and stacked controls.
    enum MeasuredStyle {
        /// The quiet actions' labels (+ More time, Swap, Skip): Inter SemiBold 13.
        case quietAction
        /// The rest screen's buttons (+15s, Skip rest): Inter Bold 20.
        case sessionSecondaryButton

        /// The type token the style draws in.
        var font: ThemeFont {
            switch self {
            case .quietAction: return Theme.Typography.quietAction
            case .sessionSecondaryButton: return Theme.Typography.sessionSecondaryButton
            }
        }
    }

    /// The width `text` takes on one line in Theme's type for `style` at `size`, in the heavier cut when
    /// `weight` is Bold Text (`ThemeFont.width(of:size:weight:)`) - the measurement behind the player's
    /// and the rest screen's choice between side-by-side and stacked controls.
    static func textWidth(_ text: String, style: MeasuredStyle, size: DynamicTypeSize, weight: LegibilityWeight?) -> CGFloat {
        style.font.width(of: text, size: size, weight: weight)
    }

    /// The secondary row's controls, laid side by side in the pinned controls or stacked in the column.
    @ViewBuilder
    private var secondaryActions: some View {
        // US-CC14 / FR-16: **+ More time** is first-class and always present on a live work
        // window or hold - the "never rush anyone" hatch. It adds the same +15s the rest's
        // "+ More time" uses, purely to the on-screen countdown; it changes nothing logged
        // (US-CC09) and never touches the plan. Shown only while a window or hold is counting
        // down (the rest screen carries its own "+15s"), so the two never double up.
        if viewModel.canExtendActiveCountdown {
            secondaryAction(
                title: Self.moreTimeTitle,
                icon: .moretime,
                accessibilityLabel: "More time",
                accessibilityHint: "Adds \(ActiveSessionViewModel.restExtension) seconds to the current timer",
                isEnabled: true
            ) {
                viewModel.extendActiveCountdown()
            }
        } else if viewModel.holdSecondsPerSide != nil {
            // A stopped hold keeps the slot, unseen and silent, so the row's columns - and how their
            // labels wrap - stay exactly as they were while the hold ran, and nothing moves.
            secondaryAction(
                title: Self.moreTimeTitle, icon: .moretime, accessibilityLabel: "More time",
                accessibilityHint: nil, isEnabled: false
            ) {}
            .hidden()
            .accessibilityHidden(true)
        }

        // A swap reshapes the slot the countdown is timing, so it is offered between holds
        // rather than during one - dimmed in place, so the row keeps its shape.
        if viewModel.canSwap {
            secondaryAction(
                title: viewModel.isSwapping ? "Swapping…" : "Swap",
                icon: .swap,
                measuredTitle: "Swap",
                accessibilityLabel: "Swap this exercise",
                accessibilityHint: "Replaces it with a similar movement",
                isEnabled: !viewModel.isSwapping && !viewModel.isHolding
            ) {
                Task { await viewModel.swapCurrentExercise() }
            }
        }

        // A timed movement records itself at zero, but the timer is an offer, not the only way
        // out: a user who held it off-timer, or was interrupted part-way through a three-set
        // plank, can still bank the work they did instead of losing it to a skip. It stays
        // offered *while* a leg runs too - otherwise the only visible ways out of a running
        // hold are "Stop hold", which records nothing, and "Skip", which discards every set
        // already banked for the exercise. Tapping it ends the leg without firing the cue (the
        // user came out of it early) and banks the set through the same path the countdown
        // takes at zero.
        if viewModel.holdSecondsPerSide != nil {
            secondaryAction(
                title: completeButtonTitle,
                icon: .check,
                accessibilityLabel: completeButtonTitle,
                accessibilityHint: "Records this set without the timer",
                isEnabled: true
            ) {
                viewModel.completeSet()
            }
        }

        secondaryAction(
            title: "Skip",
            icon: .skip,
            accessibilityLabel: "Skip this exercise",
            accessibilityHint: nil,
            isEnabled: true
        ) {
            viewModel.skipExercise()
        }
    }

    /// One quiet control in the secondary row: its icon over a 13 pt `text2` label. Every slot is built
    /// here so they share their styling, their 60pt active-screen touch target, and their column width -
    /// and so a control that is unavailable right now still holds its place in the row rather than
    /// letting the others slide.
    ///
    /// The columns are narrow - four of them on a running timed movement - and the longest title in the
    /// row ("Finish exercise", "Finish session") is the one that says what the tap actually does, so the
    /// label wraps between words and the row grows rather than truncating it away. No column is narrower
    /// than its title's longest word, so a word is never split; once the row cannot give every column that
    /// much, the controls stack as full-width rows instead (`stacksSecondaryActions`). The 60pt
    /// active-screen touch target is the floor, never the ceiling.
    private func secondaryAction(
        title: String,
        icon: AppIcon,
        measuredTitle: String? = nil,
        accessibilityLabel: String,
        accessibilityHint: String?,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: Theme.Spacing.xs) {
                IconView(icon: icon, size: 22)
                Text(title)
                    .font(Theme.Typography.quietAction)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(Theme.Colors.textSecondary)
            .opacity(isEnabled ? 1 : 0.4)
            .frame(minWidth: Self.longestWordWidth(measuredTitle ?? title, size: dynamicTypeSize, weight: legibilityWeight), maxWidth: .infinity)
            .frame(minHeight: Theme.Spacing.workoutTouchTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint ?? "")
    }

    /// The color Done fills with: the session's, cut to `sun` in a countdown's last three seconds.
    private var primaryFill: Color {
        isInLastSeconds ? Theme.Colors.sun : tone.color
    }

    /// Whether the live countdown is in its last three seconds (DESIGN "Workout timer"), as the ticking
    /// timer last reported it.
    private var isInLastSeconds: Bool {
        isTimerInLastSeconds && !viewModel.isUserPaused
    }

    /// The one big action at the bottom of the player, 64 pt and fully round in the session's color.
    /// Running a hold has no "do it now" action - the user is holding - so the slot is given to the quiet
    /// way out (`Stop hold`, a secondary button) instead of a prominent button competing with the timer.
    @ViewBuilder
    private var primaryAction: some View {
        if viewModel.isHolding {
            Button {
                viewModel.cancelHold()
            } label: {
                primaryLabel("Stop hold", icon: nil)
            }
            .secondaryButtonStyle()
            .accessibilityLabel("Stop hold")
            .accessibilityHint("Ends the countdown without recording the set")
        } else if viewModel.holdSecondsPerSide != nil {
            Button {
                viewModel.startHold()
            } label: {
                // No icon, like "Stop hold" in the same slot, so stopping or starting a hold never
                // changes the button's height and moves the controls.
                primaryLabel(startHoldTitle, icon: nil)
            }
            .primaryButtonStyle(tone.color)
            // A timed movement always shows its timer as the primary action; a swap in flight makes it
            // momentarily unstartable (US-O03) without letting the button morph into a different one.
            .disabled(!viewModel.canStartHold)
            .accessibilityLabel(startHoldAccessibilityTitle)
            .accessibilityHint("Counts the hold down and records the set when it reaches zero")
        } else if viewModel.currentStepAutoAdvances {
            // A rep-based training set auto-advances on its work window (US-CC01): the timer, not a tap,
            // ordinarily advances it, so the primary control is **Done** - the quiet way to end the
            // current window early and move on. Being caught mid-rep at zero carries no penalty, so Done
            // is an escape hatch, not an obligation. It stays labelled "Done" even on the last set (the
            // completion celebration says what finished), so the hands-free flow never asks "did you
            // finish?". It turns `sun` with the timer in the last three seconds.
            Button {
                viewModel.finishWorkWindowEarly()
            } label: {
                primaryLabel("Done", icon: .check)
            }
            .primaryButtonStyle(primaryFill)
            .accessibilityLabel("Done")
            .accessibilityHint("Ends this set early and moves on")
        } else {
            Button {
                viewModel.completeSet()
            } label: {
                primaryLabel(completeButtonTitle, icon: .check)
            }
            .primaryButtonStyle(tone.color)
            .accessibilityLabel(completeButtonTitle)
        }
    }

    /// The primary button's label: an optional icon and the title in the session's 22 pt button type,
    /// at least 64 pt tall, wrapping rather than truncating at large text.
    private func primaryLabel(_ title: String, icon: AppIcon?) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            if let icon { ScaledIcon(icon: icon, size: 22, relativeTo: .headline) }
            Text(title)
                .font(Theme.Typography.sessionButton)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.sm)
        .frame(minHeight: Theme.Spacing.doneButtonHeight)
    }

    /// "Start hold", or "Start hold (side 2 of 2)" on a per-side movement, so the button never implies
    /// the whole set is one countdown when it is two.
    private var startHoldTitle: String {
        let sides = viewModel.holdSidesPerSet
        guard sides > 1 else { return "Start hold" }
        return "Start hold (side \(viewModel.holdSide) of \(sides))"
    }

    /// The spoken form of `startHoldTitle` - the parenthetical read as a clause rather than punctuation.
    private var startHoldAccessibilityTitle: String {
        let sides = viewModel.holdSidesPerSet
        guard sides > 1 else { return "Start hold" }
        return "Start hold, side \(viewModel.holdSide) of \(sides)"
    }

    /// The honest "no alternative" state (US-K03): when the swap engine finds no safe, same-kind peer
    /// within the time budget, the original movement stays and this quiet line says so, rather than
    /// the app forcing an unsafe or off-pattern substitution.
    private var noAlternativeNotice: some View {
        Text("No safe alternative for this one - it stays in your session.")
            .font(Theme.Typography.caption)
            .foregroundStyle(Theme.Colors.textSecondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .accessibilityLabel("No safe alternative for this exercise. It stays in your session.")
    }

    /// "Complete set" mid-exercise, "Finish exercise" on the last set, "Finish session" on the very
    /// last set - so the user always knows what the action does.
    private var completeButtonTitle: String {
        guard let step = viewModel.currentStep else { return "Complete set" }
        let onLastSet = viewModel.currentSet >= step.prescription.sets
        guard onLastSet else { return "Complete set" }
        return step.position >= step.total ? "Finish session" : "Finish exercise"
    }

    // MARK: - Completion (US-L01)

    /// The post-session celebration and template summary. The win is framed by identity, never by a
    /// score or streak: it leads with the show-up - the day's mark with a check, "You showed up." - then
    /// names the session's effort (minutes, sets) and the coverage it trained. The `WorkoutLog` is
    /// written by the view model the moment the session finished (US-L01); this screen just reflects it.
    /// It then collects the optional perceived-difficulty rating (US-L02), which feeds tomorrow's
    /// session. Done is pinned below the scrolling body. There is no XP/levels/badges.
    ///
    /// Motion (DESIGN "Motion"): the mark scales in from 60%, its check draws on, the headline rises and
    /// fades in, and the numbers count up. Under Reduce Motion the mark fades in at full size and the
    /// numbers show their final values.
    private var completionState: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.lg) {
                CompletionMark(tone: tone, size: isNarrowCompletion ? 96 : 132)
                    .padding(.top, Theme.Spacing.lg)

                VStack(spacing: Theme.Spacing.sm) {
                    // Display L on one line where it fits, a step smaller where it does not (42 at
                    // 375 pt), and wrapped only at accessibility text sizes - never "up." alone.
                    ViewThatFits(in: .horizontal) {
                        ForEach([56, 46, 42] as [CGFloat], id: \.self) { size in
                            Text("You showed up.")
                                .cappedDisplayFont(size: size)
                                .fixedSize()
                        }
                        Text("You showed up.")
                            .cappedDisplayFont(size: 56)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .foregroundStyle(Theme.Colors.textPrimary)
                    Text("That's the whole game.")
                        .font(Self.completionSubtitleFont)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .multilineTextAlignment(.center)
                .modifier(RiseIn(distance: 12, duration: 0.28, delay: 0.15))
                .accessibilityElement(children: .combine)
                .accessibilityLabel("You showed up. That's the whole game.")

                if let summary = viewModel.summary {
                    summaryCard(summary)
                }

                ratingControl

                if viewModel.asksWhichMovesWereNotFinished {
                    finishCheckControl
                }
            }
            .padding(.horizontal, Theme.Spacing.screenMargin)
            .padding(.bottom, Theme.Spacing.lg)
            .frame(maxWidth: .infinity)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { completionWidth = $0 }
        // Done stays reachable however long the body runs at large text.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button {
                close()
            } label: {
                Text("Done")
                    .font(Theme.Typography.sessionButton)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.Spacing.sm)
                    .frame(minHeight: Theme.Spacing.doneButtonHeight)
            }
            .primaryButtonStyle(tone.color)
            .accessibilityLabel("Done")
            .padding(.horizontal, Theme.Spacing.screenMargin)
            .padding(.top, Theme.Spacing.sm)
            .padding(.bottom, Theme.Spacing.sm)
            .background(Theme.Colors.background)
        }
        // At large text the summary runs past the screen; scrolled, it slides under a solid band
        // rather than beneath the status bar's clock.
        .statusBarBacking()
    }

    /// The optional, non-blocking perceived-difficulty rating (US-L02): three 52 pt chips from easy to
    /// hard. Tapping one records it (and persists it onto the just-written log so the next session
    /// adjusts via the Asymmetric Ramp); the user can re-tap to change it or simply hit Done without
    /// rating, in which case the session stays unrated. Nothing here gates the Done action. At
    /// accessibility text sizes the chips stack.
    private var ratingControl: some View {
        VStack(spacing: Theme.Spacing.smd) {
            Text("How did that feel?")
                .font(Self.completionHeaderFont)
                .foregroundStyle(Theme.Colors.textPrimary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(spacing: Theme.Spacing.sm))
                : AnyLayout(HStackLayout(spacing: Theme.Spacing.sm))
            layout {
                ForEach(PerceivedDifficulty.allCases) { difficulty in
                    ratingPill(difficulty)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// One selectable rating chip. The selected chip fills with `sun` and a black label; the rest sit on
    /// `surface2`.
    private func ratingPill(_ difficulty: PerceivedDifficulty) -> some View {
        let isSelected = viewModel.perceivedDifficulty == difficulty
        return Button {
            viewModel.rate(difficulty)
        } label: {
            Text(Self.ratingLabel(difficulty))
                .frame(maxWidth: .infinity)
                .frame(minHeight: Theme.Spacing.workoutTouchTarget - 2 * Theme.Spacing.xs)
        }
        .buttonStyle(ChipButtonStyle(isSelected: isSelected, height: Theme.Spacing.completeChipHeight, horizontalPadding: Theme.Spacing.smd))
        .accessibilityLabel(Self.ratingLabel(difficulty))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    /// The "too hard" follow-up (ADR-0011): the session's worked training moves, for the user to tap
    /// any they could not finish. A tapped move steps back next time and never counts toward moving up;
    /// with none tapped, every move eases off as "too hard" always has. Optional and non-blocking like
    /// the rating itself - nothing here gates Done. Each move is an option card carrying the selected
    /// trait, at the 60pt active-screen touch target.
    private var finishCheckControl: some View {
        VStack(spacing: Theme.Spacing.smd) {
            VStack(spacing: Theme.Spacing.xs) {
                Text("Any you couldn't finish?")
                    .font(Self.completionHeaderFont)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text("Tap them and only those ease off next time. Tap none and everything eases off a little.")
                    .font(Theme.Typography.callout)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)

            ForEach(viewModel.finishCheckMoves) { move in
                finishCheckRow(move)
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// One move in the "too hard" follow-up: a marked move takes the selected option card's tint, outline
    /// and check.
    private func finishCheckRow(_ move: ActiveSessionViewModel.FinishCheckMove) -> some View {
        let isMarked = viewModel.couldNotFinishExerciseIds.contains(move.id)
        return Button {
            viewModel.toggleCouldNotFinish(move.id)
        } label: {
            OptionCard(title: move.displayName, isSelected: isMarked, minHeight: Theme.Spacing.workoutTouchTarget)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(move.displayName)
        .accessibilityHint(isMarked ? "Clears the mark" : "Marks this move as not finished")
        .accessibilityAddTraits(isMarked ? [.isSelected] : [])
    }

    /// The completion screen's type (DESIGN `X20-Complete`, `Z1-Complete-375`).
    private static let completionSubtitleFont = ThemeFont(Theme.Typography.FontName.textMedium, size: 19, relativeTo: .body)
    private static let completionHeaderFont = ThemeFont(Theme.Typography.FontName.textBold, size: 18, relativeTo: .headline)
    private static let statFont = ThemeFont(Theme.Typography.FontName.displayLarge, size: 64, relativeTo: .largeTitle)
    private static let narrowStatFont = ThemeFont(Theme.Typography.FontName.display, size: 48, relativeTo: .largeTitle)
    private static let statUnitFont = ThemeFont(Theme.Typography.FontName.textSemiBold, size: 14, relativeTo: .footnote)

    /// Whether the completion screen is laid out on a narrow phone (375 pt), where its numbers step down.
    private var isNarrowCompletion: Bool { completionWidth < 390 }

    /// The user-facing label for a perceived-difficulty rating.
    private static func ratingLabel(_ difficulty: PerceivedDifficulty) -> String {
        switch difficulty {
        case .tooEasy: return "Too easy"
        case .justRight: return "Just right"
        case .tooHard: return "Too hard"
        }
    }

    /// The template summary card: the effort (minutes and sets, counting up in the session's color) and
    /// the coverage the session produced, derived entirely from what the user actually did (US-L01). At
    /// accessibility text sizes the coverage stacks under the numbers.
    private func summaryCard(_ summary: SessionSummary) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Spacing.md))
            : AnyLayout(HStackLayout(alignment: .center, spacing: Theme.Spacing.md))
        return layout {
            HStack(alignment: .top, spacing: Theme.Spacing.md) {
                statTile(
                    value: summary.durationMinutes,
                    unit: CountWording.noun(for: summary.durationMinutes, singular: "minute", plural: "minutes")
                )
                statTile(
                    value: summary.completedSetCount,
                    unit: CountWording.noun(for: summary.completedSetCount, singular: "set", plural: "sets")
                )
            }

            if !summary.coverageText.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text("You trained".uppercased())
                        .overlineStyle()
                        .foregroundStyle(Theme.Colors.textSecondary)
                    Text(summary.coverageText)
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    if !summary.focusText.isEmpty {
                        Text(summary.focusText)
                            .font(Theme.Typography.footnote)
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("You trained \(summary.coverageText).")
            }
        }
        .padding(Theme.Spacing.mlg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    /// One labelled metric (a value over its unit) in the summary card, its number counting up.
    private func statTile(value: Int, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            CountUpText(value: value)
                .font(isNarrowCompletion ? Self.narrowStatFont : Self.statFont)
                .tracking(Theme.Typography.timerTracking * (isNarrowCompletion ? 48 : 64))
                .foregroundStyle(tone.color)
            Text(unit)
                .font(Self.statUnitFont)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(value) \(unit)")
    }

    // MARK: - Formatting

    /// `" per side"` when the prescribed value is performed once on each side, empty otherwise.
    ///
    /// The engine charges a per-side movement for both sides - a 40-second `core_side_plank` slot is
    /// planned as 80 seconds of work - so the target the player shows has to say so, or a user who
    /// holds it once does half the work the session was built around. Driven off `isPerSide` (via
    /// `sidesPerSet`), the same field the timing model reads, so the prescription and the arithmetic
    /// behind it cannot drift apart.
    static func perSideSuffix(_ prescription: PrescribedExercise) -> String {
        prescription.exercise.sidesPerSet > 1 ? " per side" : ""
    }

    /// "3 × 12" for rep-based movements, "3 × 0:30" for holds, each with " per side" where the target
    /// is per side, falling back to the bare set count when the prescription carries neither.
    ///
    /// Shared with the Ready Screen's lineup rows rather than re-derived there, so the preview cannot
    /// describe a slot differently from the player the user then works it on.
    static func targetText(_ prescription: PrescribedExercise) -> String {
        let suffix = perSideSuffix(prescription)
        if let reps = prescription.reps {
            return "\(prescription.sets) × \(reps)\(suffix)"
        }
        if let seconds = prescription.durationSeconds {
            return "\(prescription.sets) × \(clockText(seconds))\(suffix)"
        }
        return setsPhrase(prescription.sets)
    }

    /// The spoken form of `targetText` - "3 sets of 12 reps", "3 sets of 30 second holds", "1 set of a
    /// 45 second hold", "4 sets of 3 minute holds" - carrying the same " per side" suffix, since VoiceOver is the only place a
    /// non-sighted user meets the prescription and dropping it there would hide exactly half the work.
    ///
    /// Unlike `targetText`, which shows bare numerals, this spells the nouns out, so every count it
    /// names has to agree with its noun. Warm-up and cooldown slots are single-set, which makes the
    /// singular the first and last thing a VoiceOver user hears in *every* session.
    ///
    /// Shared with the Ready Screen's lineup rows, which speak this rather than the visual string, so
    /// no surface reads the "×" glyph aloud.
    static func targetAccessibilityText(_ prescription: PrescribedExercise) -> String {
        let suffix = perSideSuffix(prescription)
        if let reps = prescription.reps {
            let repsPhrase = CountWording.phrase(reps, singular: "rep", plural: "reps")
            return "\(setsPhrase(prescription.sets)) of \(repsPhrase)\(suffix)"
        }
        if let seconds = prescription.durationSeconds {
            // One set holds once, so the article moves with the noun: "1 set of a 30 second hold".
            let length = spokenHoldLength(seconds)
            let holdPhrase = CountWording.noun(
                for: prescription.sets, singular: "a \(length) hold", plural: "\(length) holds"
            )
            return "\(setsPhrase(prescription.sets)) of \(holdPhrase)\(suffix)"
        }
        return setsPhrase(prescription.sets)
    }

    /// "30 second" / "3 minute" - a hold's length as the spoken target names it: whole minutes in minutes,
    /// so an advanced 3:00 plank (ADR-0022) is read as "3 minute", never "180 second".
    static func spokenHoldLength(_ seconds: Int) -> String {
        seconds >= 60 && seconds % 60 == 0 ? "\(seconds / 60) minute" : "\(seconds) second"
    }

    /// `"1 set"` / `"3 sets"` - the set count agreeing with its noun.
    static func setsPhrase(_ sets: Int) -> String {
        CountWording.phrase(sets, singular: "set", plural: "sets")
    }

    /// "0:30" for a duration in seconds - the prescribed hold in the target line, and the remaining
    /// seconds in the rest and hold countdowns, which read it rather than carrying their own copy.
    static func clockText(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}


// MARK: - Shared session chrome

/// The player's top bar, shared by the exercise screen and the rest screen: the End control, the
/// segmented session progress, and the Pause control, each control a 60 pt `surface1` circle.
///
/// It carries the close control and, since US-CC06, a quiet **Pause/Resume** toggle - one of the
/// in-flow escape hatches. Placing Pause here (rather than in the crowded secondary action row) means a
/// single control covers whichever countdown is running - the work window, a hold, or a rest - since
/// both the player and the rest screen host this same bar, and it stays visually secondary to the
/// movement and timer below it. It used to carry an always-on elapsed clock, which US-O03 removed:
/// no running session clock is visible anywhere during the session, so the total lands once, on the
/// completion summary, instead of counting at the user the whole way through.
private struct SessionTopBar: View {
    let onClose: () -> Void
    /// Session progress in `0...1`, drawn as `segments` capsules in `tone`.
    var progress: Double = 0
    var segments: Int = 1
    var tone: Color = Theme.Colors.sun
    /// The Pause/Resume state. `canPause` is true while a countdown is live to freeze; `isPaused` is
    /// true while the user is holding an explicit pause. The toggle shows only when one of them holds -
    /// an idle Start-hold step or the moment before a countdown starts has nothing to pause, and its
    /// place stays held so the bar never shifts. `nil` `onTogglePause` (the default) omits the control
    /// for any host that has no timer to pause.
    var canPause: Bool = false
    var isPaused: Bool = false
    var onTogglePause: (() -> Void)? = nil

    /// A long session is drawn as one continuous bar rather than slivers.
    private static let maxSegments = 12

    var body: some View {
        HStack(spacing: Theme.Spacing.smd) {
            Button {
                onClose()
            } label: {
                circle(.close)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("End session")

            ProgressView(value: min(1, max(0, progress)))
                .progressViewStyle(SegmentedProgressViewStyle(
                    segments: segments <= Self.maxSegments ? segments : 1,
                    tone: tone
                ))
                .frame(maxWidth: .infinity)

            if let onTogglePause, canPause || isPaused {
                Button {
                    onTogglePause()
                } label: {
                    circle(isPaused ? .play : .pause)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isPaused ? "Resume session" : "Pause session")
                .accessibilityHint(
                    isPaused
                        ? "Continues the countdown from where it stopped"
                        : "Freezes the countdown without ending the session"
                )
            } else {
                Color.clear
                    .frame(width: Theme.Spacing.workoutTouchTarget, height: Theme.Spacing.workoutTouchTarget)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, Theme.Spacing.screenMargin)
        .padding(.top, Theme.Spacing.sm)
    }

    private func circle(_ icon: AppIcon) -> some View {
        IconView(icon: icon, size: 24)
            .foregroundStyle(Theme.Colors.textPrimary)
            .frame(width: Theme.Spacing.workoutTouchTarget, height: Theme.Spacing.workoutTouchTarget)
            .background(Theme.Colors.surface1, in: Circle())
            .contentShape(Circle())
    }
}

// MARK: - Hold timer

/// The per-exercise Hold Timer for a timed movement (US-O03): the workout timer labelled HOLD below
/// the exercise name, counting one side of the prescribed hold down. At zero the view model fires the
/// same accessible haptic/audio cue the rest timer uses - exactly once - and either opens the brief
/// "Switch sides" beat, after which the next side starts on its own (a per-side movement is two legs
/// per set), or records the set and opens the rest. The ticker lives here rather than in the player, so
/// it exists only while a hold is actually running, and it drives a *pure* check
/// (`completeHoldIfElapsed`) that is a no-op until the deadline passes, so the cue can never fire early
/// or per tick.
private struct HoldCountdownView: View {
    let viewModel: ActiveSessionViewModel
    let tone: Color
    /// Reports the last-seconds state up, so Done can turn `sun` with the timer.
    @Binding var isInLastSeconds: Bool

    /// Drives the countdown display and the completion check. Kept off the view body so the mutation
    /// happens in an action closure, never during a render pass.
    @State private var currentDate = Date()
    @State private var announcer = WorkoutTimerAnnouncer()
    private let ticker = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        let remaining = viewModel.holdRemaining(asOf: currentDate)
        let total = max(viewModel.holdTotalSeconds, 1)

        WorkoutTimerView(
            kind: .hold(target: nil),
            remaining: remaining,
            total: total,
            label: "Hold",
            spokenName: "Hold",
            tone: tone,
            isPaused: viewModel.isUserPaused
        )
        .onReceive(ticker) { date in
            currentDate = date
            let remaining = viewModel.holdRemaining(asOf: date)
            isInLastSeconds = remaining > 0 && remaining <= WorkoutTimerView.lastSecondsThreshold
            announcer.tick(remaining: remaining, total: viewModel.holdTotalSeconds, isLive: !viewModel.isUserPaused)
            viewModel.completeHoldIfElapsed(asOf: date)
        }
        .onDisappear { isInLastSeconds = false }
    }
}

// MARK: - Work window (US-CC01)

/// The auto-advancing work window for a rep-based training set (US-CC01): the workout timer below the
/// exercise name, counting the set's planned per-set seconds down - the same number the engine budgeted
/// (`SessionAssembly.workSecondsPerSet`, US-CC08), so the screen window can never drift from the plan.
/// The stage above keeps the Trainer's poses, so the window stays visual-primary (US-CC11): the user
/// follows the movement by eye while the timer times it.
///
/// Unlike the Hold Timer it *auto-starts*: appearing is enough to begin the countdown, so a rep-based
/// set is hands-free with no Start tap. At zero the view model records the set completed (identical to a
/// tapped completion) and flows into the rest, firing the same accessible cue exactly once. The ticker
/// lives here so it exists only while the window is on screen, and it drives a *pure* check
/// (`completeWorkWindowIfElapsed`) that is a no-op until the deadline passes, so the cue can never fire
/// early or per tick. A swap settling (`settledSwapCount` moving on) re-arms the window for whatever slot
/// now occupies the position.
private struct WorkWindowCountdownView: View {
    let viewModel: ActiveSessionViewModel
    let tone: Color
    /// Reports the last-seconds state up, so Done can turn `sun` with the timer.
    @Binding var isInLastSeconds: Bool

    /// Drives the countdown display and the auto-advance/cue check. Kept off the view body so the
    /// mutation happens in an action closure, never during a render pass.
    @State private var currentDate = Date()
    @State private var announcer = WorkoutTimerAnnouncer()
    private let ticker = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        // The full window is the planned per-set seconds; before the window has started (the brief
        // moment between appearing and `startWorkWindow()`) the timer shows that full value rather than
        // an empty zero, so it never flashes drained.
        let total = max(viewModel.workWindowSecondsPerSet ?? viewModel.workWindowTotalSeconds, 1)
        let running = viewModel.isRunningWorkWindow
        let remaining = running ? viewModel.workWindowRemaining(asOf: currentDate) : total

        WorkoutTimerView(
            kind: .work,
            remaining: remaining,
            total: running ? max(viewModel.workWindowTotalSeconds, 1) : total,
            label: "Time left",
            spokenName: "Work window",
            tone: tone,
            isPaused: viewModel.isUserPaused,
            isRunning: running
        )
        // Auto-start on appear (hands-free) - and after a swap settles, where the view stays mounted so
        // no fresh `onAppear` fires (keyed on the settled-swap counter, which a fast swap cannot hide the
        // way it can toggle `isSwapping` inside one update). Both are idempotent via `canStartWorkWindow`.
        .onAppear { viewModel.startWorkWindow() }
        .onChange(of: viewModel.settledSwapCount) { _, _ in
            viewModel.startWorkWindow()
        }
        .onReceive(ticker) { date in
            currentDate = date
            if viewModel.isRunningWorkWindow {
                let remaining = viewModel.workWindowRemaining(asOf: date)
                isInLastSeconds = remaining > 0 && remaining <= WorkoutTimerView.lastSecondsThreshold
                announcer.tick(remaining: remaining, total: viewModel.workWindowTotalSeconds, isLive: !viewModel.isUserPaused)
            }
            // US-CC10: the optional midpoint tone, then the completion check. Both are pure no-ops until
            // their instant, so ordering them here fires the halfway cue before the window can elapse.
            viewModel.fireWorkWindowHalfwayIfReached(asOf: date)
            viewModel.completeWorkWindowIfElapsed(asOf: date)
        }
        .onDisappear { isInLastSeconds = false }
    }
}

// MARK: - Rest timer

/// The rest screen between sets (US-K02; DESIGN `X19-Rest`).
///
/// After a set, the player advances to the next effort but shows this focused countdown first so the
/// user paces the work without watching the clock. The workout timer is the hero at the top, in
/// `rest`; below it, "NEXT UP · ROUND 2 OF 4" names the movement the rest paces toward, with its target
/// and poses. When the timer reaches zero the session auto-advances (the rest screen dismisses to reveal
/// the already-current next set) and an accessible haptic/audio cue fires. The user can skip the rest
/// or extend it by 15s; the parent pauses the countdown on backgrounding. Every control meets the 60pt
/// active-screen touch target.
private struct RestView: View {
    let viewModel: ActiveSessionViewModel
    let tone: DayTone
    /// The width the screen offers, measured by the player's background - what tells whether the two
    /// controls fit side by side (`stacksControls`) and how wide the poses are. Unmeasured, they fit.
    let width: CGFloat
    let onClose: () -> Void

    /// Drives the countdown display and the auto-advance/cue check. Kept off the view body so the
    /// mutation happens in an action closure, never during a render pass.
    @State private var currentDate = Date()
    @State private var announcer = WorkoutTimerAnnouncer()
    private let ticker = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.legibilityWeight) private var legibilityWeight

    /// The body's visible height and the heights of its timer and next-up text, measured so the next
    /// movement's poses can fit what is left (`posesHeight`). Unmeasured, there is room.
    @State private var scrollHeight = CGFloat.infinity
    @State private var timerHeight: CGFloat = 0
    @State private var nextUpHeight: CGFloat = 0

    var body: some View {
        let remaining = viewModel.restRemaining(asOf: currentDate)
        let total = max(viewModel.restTotalSeconds, 1)

        VStack(spacing: 0) {
            SessionTopBar(
                onClose: onClose,
                progress: viewModel.progress,
                segments: viewModel.currentStep?.total ?? 1,
                tone: tone.color,
                canPause: viewModel.canUserPause,
                isPaused: viewModel.isUserPaused,
                onTogglePause: {
                    if viewModel.isUserPaused {
                        viewModel.resume(asOf: Date())
                    } else {
                        viewModel.pause(asOf: Date())
                    }
                }
            )

            // The body fits the screen by shrinking the next movement's poses (below). When even their
            // smallest size leaves too little room - large Dynamic Type on a short phone - it scrolls
            // between the pinned top bar and controls rather than pushing them off the screen. One
            // measured layout rather than alternatives to choose from, so only one copy of the poses is
            // ever in VoiceOver's tree.
            ScrollView {
                middle(remaining: remaining, total: total)
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { scrollHeight = $0 }

            controls
        }
        .onReceive(ticker) { date in
            currentDate = date
            announcer.tick(
                remaining: viewModel.restRemaining(asOf: date), total: viewModel.restTotalSeconds,
                isLive: !viewModel.isUserPaused
            )
            viewModel.completeRestIfElapsed(asOf: date)
        }
    }

    /// The timer, then - pushed to the bottom when there is room - the next-up text and the next
    /// movement's poses, which shrink with the screen down to their floor.
    private func middle(remaining: Int, total: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: Theme.Spacing.smd) {
            // A per-side bookend flows side 1 -> a brief "Switch sides" beat -> side 2 hands-free
            // (US-CC05); the beat reuses this rest screen but names itself so the user knows to change
            // position rather than read it as a plain between-set rest. Every other gap - a
            // between-station transition (US-CC04) and a between-round rest - stays a "Rest" here; the
            // transition beat earns its distinctness below, in `nextUp`'s prominent "Next" and movement
            // name (US-CC11), rather than by renaming this shared label.
            let heading = viewModel.isSwitchingSides ? "Switch sides" : "Rest"
            WorkoutTimerView(
                kind: .rest,
                remaining: remaining,
                total: total,
                label: heading,
                spokenName: heading,
                tone: Theme.Colors.rest,
                isPaused: viewModel.isUserPaused,
                isHero: true
            )
            .padding(.top, Theme.Spacing.smd)
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                if ActiveSessionView.isMeasurementChange(height, from: timerHeight) { timerHeight = height }
            }

            // The flexible space between the timer and what comes next.
            Color.clear.frame(height: gap)

            VStack(alignment: .leading, spacing: Theme.Spacing.smd) {
                nextUp
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                        if ActiveSessionView.isMeasurementChange(height, from: nextUpHeight) { nextUpHeight = height }
                    }
                nextUpPoses
            }
            .modifier(RiseIn(distance: 24, duration: 0.32, delay: 0.06))
        }
        .padding(.horizontal, Theme.Spacing.screenMargin)
        .padding(.bottom, Self.bottomPadding)
    }

    /// The room under the body before the pinned controls, and the least gap above the next-up text.
    private static let bottomPadding = Theme.Spacing.smd
    private static let minimumGap = Theme.Spacing.md

    /// The next movement's poses at the height the screen leaves them: their full height (two square
    /// poses across the column) when it fits, else what is left, never below the card's floor - past
    /// which the body scrolls.
    private var posesHeight: CGFloat {
        let natural = ExerciseDemoView.naturalHeight(width: width - 2 * Theme.Spacing.screenMargin)
        let upper = min(ExerciseDemoView.height, natural.isFinite ? natural : ExerciseDemoView.height)
        guard scrollHeight.isFinite else { return upper }
        let room = scrollHeight - timerHeight - Self.minimumGap - nextUpHeight - Theme.Spacing.smd - Self.bottomPadding
        return min(upper, max(room, Self.posesHeightRange.lowerBound))
    }

    /// The space between the timer and the next-up text: whatever the screen leaves over.
    private var gap: CGFloat {
        guard scrollHeight.isFinite else { return Self.minimumGap }
        let used = timerHeight + nextUpHeight + Theme.Spacing.smd + posesHeight + Self.bottomPadding
        return max(Self.minimumGap, scrollHeight - used)
    }

    /// A preview of the effort the rest is pacing toward, so the user knows what is next: an overline
    /// in the session's color ("NEXT UP · ROUND 2 OF 4"), then the movement's name with its target.
    /// Inside a training-block circuit the rest paces toward a round ("Round N of M", US-CC02); a linear
    /// bookend paces toward the exercise's next set.
    ///
    /// A between-station **transition beat** (US-CC04) keeps its own cue (US-CC11): its overline reads
    /// "NEXT" where a between-round rest and a plain bookend rest read "NEXT UP", and VoiceOver announces
    /// it as "Next: <exercise>"; a switch-sides beat names the owed side instead.
    @ViewBuilder
    private var nextUp: some View {
        if let step = viewModel.currentStep {
            // A switch-sides beat (US-CC05) paces toward the *same* stretch's next side, so it names the
            // side owed ("Side 2 of 2") rather than a set/round; every other rest paces toward the next
            // set, round, or stretch.
            let switching = viewModel.isSwitchingSides
            let transition = viewModel.isTransitionBeat
            let name = step.prescription.exercise.displayName
            let progressText: String = {
                if switching {
                    return "Side \(viewModel.holdSide) of \(viewModel.holdSidesPerSet)"
                }
                if let round = viewModel.currentRound, let rounds = viewModel.circuitRoundCount {
                    return "Round \(round) of \(rounds)"
                }
                return "Set \(viewModel.currentSet) of \(step.prescription.sets)"
            }()
            let heading = transition ? "Next" : (switching ? "Same stretch" : "Next up")
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text("\(heading) · \(progressText)".uppercased())
                    .overlineStyle()
                    .foregroundStyle(tone.color)
                    .fixedSize(horizontal: false, vertical: true)
                MovementTitleRow(
                    name: name,
                    target: ActiveSessionView.targetText(step.prescription),
                    nameFont: Theme.Typography.largeTitle,
                    targetFont: Theme.Typography.target,
                    targetColor: tone.color,
                    width: width - 2 * Theme.Spacing.screenMargin
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            // The transition beat announces the prominent visual cue verbatim ("Next: <exercise>"); the
            // quieter rests keep their existing "<heading>, <name>, <progress>" phrasing.
            .accessibilityLabel(
                transition
                    ? "Next: \(name), \(progressText)"
                    : "\(switching ? "Same stretch" : "Next up"), \(name), \(progressText)"
            )
        }
    }

    /// The upcoming movement's Trainer poses under the next-up text (US-TP08): the next station on a
    /// transition beat, the next round's movement on a between-round rest, and the same stretch on the
    /// switch-sides beat (decision 11) - `currentStep` is already the effort the rest paces toward. Same
    /// illustration, Trainer, pair/single/glyph rules and stage as the exercise card, at a height that
    /// shrinks to fit (a still mark: this is a preview, not the live demo).
    @ViewBuilder
    private var nextUpPoses: some View {
        if let step = viewModel.currentStep {
            ExerciseDemoView(prescription: step.prescription, height: posesHeight, animatesGlyph: false)
        }
    }

    /// The rest preview card's smallest and largest height.
    static let posesHeightRange: ClosedRange<CGFloat> = ExerciseDemoView.minHeight...ExerciseDemoView.height

    /// Extend (+15s, a secondary button) and Skip rest (filled in `rest`) - both meeting the 60pt
    /// active-screen touch target. Side by side while both titles fit their share of the row on one
    /// line; stacked full width once either would wrap (`stacksControls`).
    private var controls: some View {
        let layout = stacksControls
            ? AnyLayout(VStackLayout(spacing: Theme.Spacing.sm))
            : AnyLayout(HStackLayout(spacing: Theme.Spacing.sm))
        return layout {
            Button {
                viewModel.extendRest()
            } label: {
                Text("+\(ActiveSessionViewModel.restExtension)s")
                    .font(Theme.Typography.sessionSecondaryButton)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.Spacing.sm)
                    .frame(minHeight: Theme.Spacing.doneButtonHeight)
            }
            .secondaryButtonStyle()
            .frame(maxWidth: stacksControls ? .infinity : Self.extendShare * width)
            .accessibilityLabel("Extend rest by \(ActiveSessionViewModel.restExtension) seconds")

            Button {
                viewModel.skipRest()
            } label: {
                HStack(spacing: Theme.Spacing.sm) {
                    ScaledIcon(icon: .skip, size: 22, relativeTo: .headline)
                    Text("Skip rest")
                        .font(Theme.Typography.sessionSecondaryButton)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Spacing.sm)
                .frame(minHeight: Theme.Spacing.doneButtonHeight)
            }
            .primaryButtonStyle(Theme.Colors.rest)
            .accessibilityLabel("Skip rest")
        }
        .padding(.horizontal, Theme.Spacing.screenMargin)
        .padding(.top, Theme.Spacing.xs)
        .padding(.bottom, Theme.Spacing.sm)
    }

    /// The share of the row "+15s" takes beside "Skip rest".
    private static let extendShare: CGFloat = 0.38

    /// Whether the two controls stack: once either title no longer fits on one line inside its share of
    /// the row (less the button's own inset), so a label is never cut by the button's edge.
    private var stacksControls: Bool {
        guard width.isFinite else { return false }
        let row = width - 2 * Theme.Spacing.screenMargin - Theme.Spacing.sm
        let extend = Self.extendShare * width - Self.buttonLabelInset
        let skip = row - Self.extendShare * width - Self.buttonLabelInset - Self.skipIconWidth
        func needs(_ title: String) -> CGFloat {
            ActiveSessionView.textWidth(title, style: .sessionSecondaryButton, size: dynamicTypeSize, weight: legibilityWeight)
        }
        return needs("+\(ActiveSessionViewModel.restExtension)s") > extend || needs("Skip rest") > skip
    }

    /// The room a button keeps around its label, on both sides together.
    private static let buttonLabelInset = 2 * Theme.Spacing.md
    /// The skip icon and its gap beside "Skip rest".
    private static let skipIconWidth: CGFloat = 22 + Theme.Spacing.sm
}

// MARK: - Motion helpers

/// Rises `distance` points and fades in once, on appear; under Reduce Motion it only fades, over 200 ms.
private struct RiseIn: ViewModifier {
    let distance: CGFloat
    let duration: Double
    let delay: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : distance)
            .onAppear {
                withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .easeOut(duration: duration).delay(delay)) {
                    shown = true
                }
            }
    }
}

/// The completion mark: the session's day mark, filled, with a black check drawn on it. It scales in
/// from 60% on a spring and the check draws over 300 ms; under Reduce Motion it fades in at full size.
private struct CompletionMark: View {
    let tone: DayTone
    /// The mark's size: 132 pt, 96 on a narrow phone.
    var size: CGFloat = 132

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    private var mark: DayMark {
        switch tone {
        case .push: return .push
        case .pull: return .pull
        case .legs: return .legs
        case .rest: return .rest
        case .sun: return .sun
        }
    }

    var body: some View {
        ZStack {
            DayMarkView(mark: mark, filled: true, color: tone.color, size: size)
            CheckStroke()
                .trim(from: 0, to: shown || reduceMotion ? 1 : 0)
                .stroke(Theme.Colors.black, style: StrokeStyle(lineWidth: size / 16.5, lineCap: .round, lineJoin: .round))
                .frame(width: size / 3, height: size / 3)
                .offset(y: mark == .push || mark == .pull ? size / 11 : 0)
        }
        .frame(width: size, height: size)
        .scaleEffect(shown || reduceMotion ? 1 : 0.6)
        .opacity(shown ? 1 : 0)
        .accessibilityHidden(true)
        .onAppear {
            if reduceMotion {
                withAnimation(.easeInOut(duration: 0.2)) { shown = true }
            } else {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) { shown = true }
            }
        }
    }
}

/// The check glyph's path on a 24 pt grid, as the `check` icon draws it.
private struct CheckStroke: Shape {
    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 24
        var path = Path()
        path.move(to: CGPoint(x: 5 * scale, y: 12.5 * scale))
        path.addLine(to: CGPoint(x: 9.5 * scale, y: 17 * scale))
        path.addLine(to: CGPoint(x: 19 * scale, y: 7.5 * scale))
        return path
    }
}

/// A whole number that counts up from zero to `value` over 600 ms on appear; under Reduce Motion it
/// shows the final value at once.
private struct CountUpText: View {
    let value: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown: Double = 0

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .modifier(CountingNumber(value: reduceMotion ? Double(value) : shown))
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeOut(duration: 0.6)) { shown = Double(value) }
            }
            .onChange(of: value) { _, newValue in shown = Double(newValue) }
    }
}

/// Draws an animatable number as text, so `CountUpText` can tween it.
private struct CountingNumber: ViewModifier, Animatable {
    var value: Double

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    func body(content: Content) -> some View {
        Text("\(Int(value.rounded()))")
            .monospacedDigit()
    }
}

#Preview {
    ActiveSessionView(workout: .previewSample)
        .environment(AppState.preview())
}

private extension Workout {
    /// A small two-block session for the player preview: a warm-up hold plus two strength moves.
    static var previewSample: Workout {
        func exercise(_ id: String, pattern: MovementPattern, isHold: Bool) -> Exercise {
            Exercise(
                id: id, displayName: id.replacingOccurrences(of: "_", with: " ").capitalized,
                pillar: .strength, movementPattern: pattern, category: .strength, difficulty: 2,
                phase: .discipline, equipment: [], isHold: isHold,
                defaultReps: isHold ? nil : 10, defaultDurationSeconds: isHold ? 30 : nil,
                estimatedTimePerSetSeconds: 40, metValue: 4, progressionChainId: "\(id)_chain",
                progressionOrder: 0, regressionId: nil, progressionId: nil,
                advancementCriteria: "3x12", apartmentFriendly: true
            )
        }
        return Workout(
            id: UUID(), createdAt: Date(), shape: .blend, focusPillar: nil, requestedMinutes: 15,
            wasReturn: false,
            blocks: [
                WorkoutBlock(id: UUID(), title: "Warm-up", category: .warmup, exercises: [
                    PrescribedExercise(id: UUID(), exercise: exercise("cat_cow", pattern: .mobility, isHold: true), sets: 1, reps: nil, durationSeconds: 30, restSeconds: 20)
                ]),
                WorkoutBlock(id: UUID(), title: "Strength", category: .strength, exercises: [
                    PrescribedExercise(id: UUID(), exercise: exercise("push_up", pattern: .push, isHold: false), sets: 3, reps: 12, durationSeconds: nil, restSeconds: 45),
                    PrescribedExercise(id: UUID(), exercise: exercise("air_squat", pattern: .squat, isHold: false), sets: 2, reps: 15, durationSeconds: nil, restSeconds: 45)
                ])
            ]
        )
    }
}
