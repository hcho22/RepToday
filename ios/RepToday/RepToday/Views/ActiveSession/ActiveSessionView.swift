import SwiftUI
import UIKit
import Lottie

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
/// seconds down and records it at zero with no tap, offering a quiet **Done** to advance early. Since
/// US-CC05 the **warm-up and cooldown bookend holds auto-start hands-free** too - no Start-hold tap, a
/// per-side stretch flowing side 1 -> a brief "Switch sides" beat -> side 2 with no tap - while a timed
/// *strength / primal* hold keeps the deliberate Start-hold tap; a rep-based set outside a training
/// block, were one generated, keeps the manual "Complete set".
struct ActiveSessionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    /// The persisted one-shot flag for the first-run explainer (US-CC13). Declared optional so the
    /// player still renders when hosted without an `AppState` in the environment (the evidence-test
    /// surfaces do exactly that); production always provides one, so the explainer only ever runs
    /// where the flag can be read and written.
    @Environment(AppState.self) private var appState: AppState?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var viewModel: ActiveSessionViewModel

    /// Drives the first-run explainer overlay (US-CC13). Set once, on first arrival at the player, and
    /// only when the persisted one-shot flag says it has never been shown.
    @State private var showExplainer = false

    /// Reports, as the player dismisses, whether the session completed (US-K04). The Ready Screen uses
    /// this to refresh the resumable session *without* racing the store's completion clear: a completed
    /// session leaves nothing resumable, while an abandoned one is re-read from the store.
    private let onFinish: ((Bool) -> Void)?

    /// Start a fresh session for `workout`. When `store` and `userId` are supplied, the player
    /// persists its progress so it survives backgrounding and relaunch (US-K04).
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
        onFinish: ((Bool) -> Void)? = nil
    ) {
        self.onFinish = onFinish
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
        onFinish: ((Bool) -> Void)? = nil
    ) {
        self.onFinish = onFinish
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

    /// Present the first-run explainer (US-CC13) at most once, ever. The one-shot flag is flipped the
    /// moment we decide to show it - not on dismissal - so a force-quit while it is up can never bring
    /// it back on the next session; "Got it" then only has to dismiss the overlay. A missing `AppState`
    /// (hosted evidence surfaces) simply never shows it. The entrance is animated unless Reduce Motion
    /// is on, in which case it appears in place with no transition.
    private func presentExplainerIfNeeded() {
        guard let appState, appState.shouldShowContinuousCircuitExplainer else { return }
        appState.markContinuousCircuitExplainerSeen()
        if reduceMotion {
            showExplainer = true
        } else {
            withAnimation(.easeOut(duration: 0.25)) { showExplainer = true }
        }
    }

    /// Dismiss the explainer, honoring Reduce Motion the same way the entrance does.
    private func dismissExplainer() {
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
        ZStack {
            Theme.Colors.background.ignoresSafeArea()

            if viewModel.isComplete {
                completionState
            } else if viewModel.isResting {
                RestView(viewModel: viewModel) { close() }
            } else {
                player
            }

            // The first-run explainer (US-CC13) rides above the player as its own layer rather than a
            // sheet, so the entrance animation can be stilled under Reduce Motion and the session
            // underneath keeps initializing (its `onAppear` has already fired) - the explainer never
            // gates the start.
            if showExplainer {
                ContinuousCircuitExplainerView(onDismiss: dismissExplainer)
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .onAppear {
            viewModel.start()
            presentExplainerIfNeeded()
            // A rest paused on backgrounding and restored from a snapshot (US-K04) never sees a
            // scene-phase change when the resumed player is presented on an already-active app, so
            // resume it here too. A no-op unless a rest is currently paused, leaving a fresh session
            // and a resumed running rest untouched.
            //
            // There is deliberately no `resumeHold` counterpart (US-O03). A hold is never restored as a
            // countdown at all, so there is nothing frozen to un-freeze - and un-freezing one here is
            // precisely how a leg the user abandoned days ago used to finish itself moments after the
            // screen appeared, banking a set nobody performed. In-session backgrounding still
            // pauses and resumes the leg through `scenePhase` below, which is the interruption the user
            // is actually present for.
            viewModel.resumeRest(asOf: Date())
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

    private var player: some View {
        VStack(spacing: 0) {
            SessionTopBar(
                onClose: close,
                canPause: viewModel.canUserPause,
                isPaused: viewModel.isUserPaused,
                onTogglePause: togglePause
            )

            ProgressView(value: viewModel.progress)
                .tint(Theme.Colors.accent)
                .padding(.horizontal, Theme.Spacing.lg)

            if let step = viewModel.currentStep {
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                        blockContext(step)
                        // While a hold runs, the countdown takes the demo's place: the user is already
                        // in position, so what they need on screen is the time left, not the shape. A
                        // rep-based training set differs (US-CC11): its auto-advancing work window is
                        // *visual*-primary, pairing the movement illustration with a compact countdown
                        // ring in the same slot so the user follows along by eye without voice.
                        if viewModel.isHolding {
                            HoldCountdownView(viewModel: viewModel)
                        } else if viewModel.currentStepAutoAdvances {
                            WorkWindowCountdownView(viewModel: viewModel, prescription: step.prescription)
                        } else {
                            ExerciseDemoView(prescription: step.prescription)
                        }
                        exerciseHeadline(step)
                        setTracker(step)
                    }
                    .padding(Theme.Spacing.lg)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            controls
        }
        // A swap on a bookend hold ends the leg and lands on the substitute idle; re-arm the hands-free
        // auto-start once the swap settles (US-CC05), mirroring how `WorkWindowCountdownView` re-arms the
        // work window - the view stays mounted through a swap, so no fresh `onAppear` fires. A no-op off
        // the bookend-hold path (`autoStartHoldIfNeeded` guards on `canAutoStartHold`).
        .onChange(of: viewModel.isSwapping) { _, swapping in
            if !swapping { viewModel.autoStartHoldIfNeeded() }
        }
    }

    /// The block this exercise belongs to and its position across the session ("Warm-up · 1 of 8").
    private func blockContext(_ step: ActiveSessionViewModel.Step) -> some View {
        Text("\(step.blockTitle) · \(step.position) of \(step.total)")
            .font(Theme.Typography.caption)
            .foregroundStyle(Theme.Colors.textSecondary)
            .accessibilityLabel("\(step.blockTitle), exercise \(step.position) of \(step.total)")
    }

    private func exerciseHeadline(_ step: ActiveSessionViewModel.Step) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(step.prescription.exercise.displayName)
                .font(Theme.Typography.largeTitle)
                .foregroundStyle(Theme.Colors.textPrimary)
            // The per-side targets are the longest strings this line renders; letting it grow
            // vertically keeps "3 × 0:30 per side" whole at the largest Dynamic Type sizes rather than
            // truncating away the part that says how much work the set actually is.
            Text(Self.targetText(step.prescription))
                .font(Theme.Typography.title)
                .foregroundStyle(Theme.Colors.accent)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(step.prescription.exercise.displayName), \(Self.targetAccessibilityText(step.prescription))")
    }

    /// Set tracking, with a dot per set filled as they are completed. Inside a training-block circuit
    /// the headline reads "Round N of M" (US-CC02) - the block rotates one set of each exercise per
    /// round, and a station's r-th set is round r, so the dots below still track this exercise's own
    /// progress; a linear warm-up / cooldown bookend keeps "Set N of M". A per-side hold names the side
    /// too, because its set is two legs and the Hold Timer only counts one of them at a time - without
    /// it the user has no way to tell a finished set from a half-finished one.
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

        return VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(progressText)
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.textPrimary)

            if showsSide {
                Text(sideText)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }

            HStack(spacing: Theme.Spacing.sm) {
                ForEach(0..<step.prescription.sets, id: \.self) { index in
                    Circle()
                        .fill(index < viewModel.currentSet - 1 ? Theme.Colors.accent : Theme.Colors.surface)
                        .frame(width: Theme.Spacing.md, height: Theme.Spacing.md)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement()
        .accessibilityLabel(showsSide ? "\(progressText), side \(viewModel.holdSide) of \(sides)" : progressText)
    }

    /// The primary action plus the quieter secondary row - all meeting the 60pt active-screen touch
    /// target. Which primary action shows depends on the movement (US-O03): a rep-based exercise keeps
    /// "Complete set", and completing the last set of the last exercise finishes the session; a timed
    /// one offers "Start hold" instead, and the countdown records its own set at zero, so the timer
    /// rather than a tap is what ordinarily advances it - with the same completion still offered as a
    /// quiet slot in the row below (running leg included), so coming out early banks the work instead
    /// of losing it to a skip. Swapping (US-K03) replaces the current movement with a
    /// same-pillar/pattern peer, or, when none is safe and in budget, surfaces an honest "no
    /// alternative" notice above the actions.
    ///
    /// Which *slots* the secondary row carries is decided by the exercise, never by whether a hold
    /// happens to be running: starting one dims controls in place rather than removing them, so the
    /// row never reflows under the user's thumb mid-tap.
    private var controls: some View {
        VStack(spacing: Theme.Spacing.sm) {
            if viewModel.noSwapAlternative {
                noAlternativeNotice
            }

            primaryAction

            HStack(spacing: Theme.Spacing.md) {
                // A swap reshapes the slot the countdown is timing, so it is offered between holds
                // rather than during one - dimmed in place, so the row keeps its shape.
                if viewModel.canSwap {
                    secondaryAction(
                        title: viewModel.isSwapping ? "Swapping…" : "Swap",
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
                        accessibilityLabel: completeButtonTitle,
                        accessibilityHint: "Records this set without the timer",
                        isEnabled: true
                    ) {
                        viewModel.completeSet()
                    }
                }

                secondaryAction(
                    title: "Skip",
                    accessibilityLabel: "Skip this exercise",
                    accessibilityHint: nil,
                    isEnabled: true
                ) {
                    viewModel.skipExercise()
                }
            }
        }
        .padding(Theme.Spacing.lg)
        .background(Theme.Colors.background)
    }

    /// One quiet control in the secondary row. Every slot is built here so they share their styling,
    /// their 60pt active-screen touch target, and their column width - and so a control that is
    /// unavailable right now still holds its place in the row rather than letting the others slide.
    ///
    /// The columns are narrow - three of them on a timed movement - and the longest title in the row
    /// ("Finish exercise", "Finish session") is the one that says what the tap actually does, so the
    /// label wraps and the row grows rather than truncating it away at the largest Dynamic Type sizes.
    /// Same remedy the target line uses, and the 60pt active-screen touch target is the floor, never
    /// the ceiling.
    private func secondaryAction(
        title: String,
        accessibilityLabel: String,
        accessibilityHint: String?,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(Theme.Typography.body)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(Theme.Colors.textSecondary)
                .opacity(isEnabled ? 1 : 0.4)
                .frame(maxWidth: .infinity)
                .frame(minHeight: Theme.Spacing.workoutTouchTarget)
        }
        .disabled(!isEnabled)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint ?? "")
    }

    /// The one big action at the bottom of the player. Running a hold has no "do it now" action - the
    /// user is holding - so the slot is given to the quiet way out (`Stop hold`, bordered rather than
    /// prominent) instead of a prominent button competing with the countdown for attention.
    @ViewBuilder
    private var primaryAction: some View {
        if viewModel.isHolding {
            Button {
                viewModel.cancelHold()
            } label: {
                Text("Stop hold")
                    .font(Theme.Typography.button)
                    .frame(maxWidth: .infinity)
                    .frame(height: Theme.Spacing.workoutTouchTarget)
            }
            .buttonStyle(.bordered)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Spacing.cardCornerRadius))
            .accessibilityLabel("Stop hold")
            .accessibilityHint("Ends the countdown without recording the set")
        } else if viewModel.holdSecondsPerSide != nil {
            Button {
                viewModel.startHold()
            } label: {
                Text(startHoldTitle)
                    .font(Theme.Typography.button)
                    .frame(maxWidth: .infinity)
                    .frame(height: Theme.Spacing.workoutTouchTarget)
            }
            .buttonStyle(.borderedProminent)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Spacing.cardCornerRadius))
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
            // finish?".
            Button {
                viewModel.finishWorkWindowEarly()
            } label: {
                Text("Done")
                    .font(Theme.Typography.button)
                    .frame(maxWidth: .infinity)
                    .frame(height: Theme.Spacing.workoutTouchTarget)
            }
            .buttonStyle(.borderedProminent)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Spacing.cardCornerRadius))
            .accessibilityLabel("Done")
            .accessibilityHint("Ends this set early and moves on")
        } else {
            Button {
                viewModel.completeSet()
            } label: {
                Text(completeButtonTitle)
                    .font(Theme.Typography.button)
                    .frame(maxWidth: .infinity)
                    .frame(height: Theme.Spacing.workoutTouchTarget)
            }
            .buttonStyle(.borderedProminent)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Spacing.cardCornerRadius))
            .accessibilityLabel(completeButtonTitle)
        }
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
    /// score or streak: it leads with the show-up, then names the muscle/mobility coverage and the
    /// session's effort (duration, sets). The `WorkoutLog` is written by the view model the moment the
    /// session finished (US-L01); this screen just reflects it. It then collects the optional
    /// perceived-difficulty rating (US-L02), which feeds tomorrow's session. Every token comes from
    /// `Theme`; there is no XP/levels/badges.
    private var completionState: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.lg) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 72, weight: .semibold))
                    .foregroundStyle(Theme.Colors.accent)
                    .accessibilityHidden(true)

                VStack(spacing: Theme.Spacing.xs) {
                    Text("You showed up.")
                        .font(Theme.Typography.largeTitle)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text("That's the whole game.")
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                .multilineTextAlignment(.center)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("You showed up. That's the whole game.")

                if let summary = viewModel.summary {
                    summaryCard(summary)
                }

                ratingControl

                Button {
                    close()
                } label: {
                    Text("Done")
                        .font(Theme.Typography.button)
                        .frame(maxWidth: .infinity)
                        .frame(height: Theme.Spacing.workoutTouchTarget)
                }
                .buttonStyle(.borderedProminent)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Spacing.cardCornerRadius))
                .accessibilityLabel("Done")
            }
            .padding(Theme.Spacing.lg)
            .frame(maxWidth: .infinity)
        }
    }

    /// The optional, non-blocking perceived-difficulty rating (US-L02): three pills from easy to hard.
    /// Tapping one records it (and persists it onto the just-written log so the next session adjusts via
    /// the Asymmetric Ramp); the user can re-tap to change it or simply hit Done without rating, in which
    /// case the session stays unrated. Nothing here gates the Done action. Every control meets the 60pt
    /// active-screen touch target and every token comes from `Theme`.
    private var ratingControl: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Text("How did that feel?")
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.textPrimary)
                .accessibilityAddTraits(.isHeader)

            HStack(spacing: Theme.Spacing.sm) {
                ForEach(PerceivedDifficulty.allCases) { difficulty in
                    ratingPill(difficulty)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// One selectable rating pill. The selected pill fills with the accent; the rest sit on the surface.
    private func ratingPill(_ difficulty: PerceivedDifficulty) -> some View {
        let isSelected = viewModel.perceivedDifficulty == difficulty
        return Button {
            viewModel.rate(difficulty)
        } label: {
            Text(Self.ratingLabel(difficulty))
                .font(Theme.Typography.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(isSelected ? Theme.Colors.onAccent : Theme.Colors.textPrimary)
                .frame(maxWidth: .infinity)
                .frame(minHeight: Theme.Spacing.workoutTouchTarget)
                .padding(.horizontal, Theme.Spacing.xs)
                .background(
                    isSelected ? Theme.Colors.accent : Theme.Colors.surface,
                    in: RoundedRectangle(cornerRadius: Theme.Spacing.cardCornerRadius)
                )
        }
        .accessibilityLabel(Self.ratingLabel(difficulty))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    /// The user-facing label for a perceived-difficulty rating.
    private static func ratingLabel(_ difficulty: PerceivedDifficulty) -> String {
        switch difficulty {
        case .tooEasy: return "Too easy"
        case .justRight: return "Just right"
        case .tooHard: return "Too hard"
        }
    }

    /// The template summary card: the effort (duration + sets) and the muscle/mobility coverage the
    /// session produced, derived entirely from what the user actually did (US-L01).
    private func summaryCard(_ summary: SessionSummary) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(spacing: Theme.Spacing.lg) {
                statTile(value: "\(summary.durationMinutes)", unit: summary.durationMinutes == 1 ? "minute" : "minutes")
                statTile(value: "\(summary.completedSetCount)", unit: summary.completedSetCount == 1 ? "set" : "sets")
            }

            if !summary.coverageText.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text("You trained")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                    Text(summary.coverageText)
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    if !summary.focusText.isEmpty {
                        Text(summary.focusText)
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("You trained \(summary.coverageText).")
            }
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Spacing.cardCornerRadius))
    }

    /// One labelled metric (a value over its unit) in the summary card.
    private func statTile(value: String, unit: String) -> some View {
        VStack(spacing: 0) {
            Text(value)
                .font(Theme.Typography.largeTitle)
                .foregroundStyle(Theme.Colors.accent)
                .monospacedDigit()
            Text(unit)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .accessibilityElement(children: .combine)
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
    /// 45 second hold" - carrying the same " per side" suffix, since VoiceOver is the only place a
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
            let repsPhrase = reps == 1 ? "1 rep" : "\(reps) reps"
            return "\(setsPhrase(prescription.sets)) of \(repsPhrase)\(suffix)"
        }
        if let seconds = prescription.durationSeconds {
            // One set holds once, so the article moves with the noun: "1 set of a 30 second hold".
            let holdPhrase = prescription.sets == 1
                ? "a \(seconds) second hold"
                : "\(seconds) second holds"
            return "\(setsPhrase(prescription.sets)) of \(holdPhrase)\(suffix)"
        }
        return setsPhrase(prescription.sets)
    }

    /// `"1 set"` / `"3 sets"` - the set count agreeing with its noun.
    static func setsPhrase(_ sets: Int) -> String {
        sets == 1 ? "1 set" : "\(sets) sets"
    }

    /// "0:30" for a duration in seconds - the prescribed hold in the target line, and the remaining
    /// seconds in the rest and hold countdowns, which read it rather than carrying their own copy.
    static func clockText(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

// MARK: - Shared session chrome

/// The card that holds whatever occupies the demo slot - the exercise demonstration (US-K01) or, while
/// a hold runs, its countdown (US-O03). One definition of the slot's size and chrome, so the two states
/// differ only in their content and starting a hold never makes the card itself blink out.
private extension View {
    func exerciseSlotCard() -> some View {
        self
            .frame(maxWidth: .infinity)
            .frame(height: ExerciseDemoView.height)
            .background(
                Theme.Colors.secondaryBackground,
                in: RoundedRectangle(cornerRadius: Theme.Spacing.cardCornerRadius)
            )
    }
}

/// The player's top bar, shared by the exercise screen and the rest overlay.
///
/// It carries the close control and, since US-CC06, a quiet **Pause/Resume** toggle - one of the
/// in-flow escape hatches. Placing Pause here (rather than in the crowded secondary action row) means a
/// single control covers whichever countdown is running - the work window, a hold, or a rest - since
/// both the player and the rest overlay host this same bar, and it stays visually secondary to the
/// movement and countdown below it. It used to carry an always-on elapsed clock, which US-O03 removed:
/// no running session clock is visible anywhere during the session, so the total lands once, on the
/// completion summary, instead of counting at the user the whole way through.
private struct SessionTopBar: View {
    let onClose: () -> Void
    /// The Pause/Resume state. `canPause` is true while a countdown is live to freeze; `isPaused` is
    /// true while the user is holding an explicit pause. The toggle shows only when one of them holds -
    /// an idle Start-hold step or the moment before a countdown starts has nothing to pause. `nil`
    /// `onTogglePause` (the default) omits the control entirely for any host that has no timer to pause.
    var canPause: Bool = false
    var isPaused: Bool = false
    var onTogglePause: (() -> Void)? = nil

    var body: some View {
        HStack {
            Button {
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(Theme.Typography.button)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .frame(width: Theme.Spacing.workoutTouchTarget, height: Theme.Spacing.workoutTouchTarget)
            }
            .accessibilityLabel("End session")

            Spacer()

            if let onTogglePause, canPause || isPaused {
                Button {
                    onTogglePause()
                } label: {
                    Image(systemName: isPaused ? "play.fill" : "pause.fill")
                        .font(Theme.Typography.button)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .frame(width: Theme.Spacing.workoutTouchTarget, height: Theme.Spacing.workoutTouchTarget)
                }
                .accessibilityLabel(isPaused ? "Resume session" : "Pause session")
                .accessibilityHint(
                    isPaused
                        ? "Continues the countdown from where it stopped"
                        : "Freezes the countdown without ending the session"
                )
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.top, Theme.Spacing.sm)
    }
}

/// The countdown ring shared by the rest overlay (US-K02) and the Hold Timer (US-O03): a track plus an
/// accent arc that empties as the countdown runs out, with the remaining time in its centre. One
/// implementation, so the two timers the user meets in a session read as the same object.
private struct CountdownRing: View {
    let remaining: Int
    let fraction: Double
    let accessibilityLabel: String

    /// The ring's size and typography. The hold (US-O03) and rest (US-K02) overlays keep the full-size
    /// defaults, where the ring is the whole slot; the visual-primary work window (US-CC11) pairs a
    /// compact ring beside a larger movement illustration, so it passes a smaller diameter and font.
    var diameter: CGFloat = 200
    var lineWidth: CGFloat = 12
    var font: Font = Theme.Typography.largeTitle

    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.Colors.surface, lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: fraction)
                .stroke(Theme.Colors.accent, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.5), value: fraction)

            Text(ActiveSessionView.clockText(remaining))
                .font(font)
                .monospacedDigit()
                .foregroundStyle(Theme.Colors.textPrimary)
        }
        .frame(width: diameter, height: diameter)
        .accessibilityElement()
        .accessibilityLabel(accessibilityLabel)
    }
}

// MARK: - Hold timer

/// The per-exercise Hold Timer for a timed movement (US-O03).
///
/// It takes the demo's place while a hold runs and counts one side of the prescribed hold down. At
/// zero the view model fires the same accessible haptic/audio cue the rest timer uses - exactly once -
/// and either parks on the next side (a per-side movement is two legs per set) or records the set and
/// opens the rest. The ticker lives here rather than in the player, so it exists only while a hold is
/// actually running, and it drives a *pure* check (`completeHoldIfElapsed`) that is a no-op until the
/// deadline passes, so the cue can never fire early or per tick.
private struct HoldCountdownView: View {
    let viewModel: ActiveSessionViewModel

    /// Drives the countdown display and the completion check. Kept off the view body so the mutation
    /// happens in an action closure, never during a render pass.
    @State private var currentDate = Date()
    private let ticker = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        let remaining = viewModel.holdRemaining(asOf: currentDate)
        let total = max(viewModel.holdTotalSeconds, 1)

        CountdownRing(
            remaining: remaining,
            fraction: min(1, max(0, Double(remaining) / Double(total))),
            accessibilityLabel: "Hold, \(remaining) seconds remaining"
        )
        // The countdown stands in the demo's own card, so starting a hold changes what is in the slot
        // and nothing else - not the card under it, not the exercise name and target below it.
        .exerciseSlotCard()
        .onReceive(ticker) { date in
            currentDate = date
            viewModel.completeHoldIfElapsed(asOf: date)
        }
    }
}

// MARK: - Work window (US-CC01)

/// The visual-primary auto-advancing work window for a rep-based training set (US-CC01, made
/// visual-primary in US-CC11).
///
/// It fills the demo slot while the set is on screen, pairing a **clear static movement illustration**
/// (so the user can follow along by eye, since there is no voice) with a compact **countdown ring**
/// that counts the set's planned per-set seconds down - the same number the engine budgeted
/// (`SessionAssembly.workSecondsPerSet`, US-CC08), so the screen window can never drift from the plan.
/// The illustration is the same `ExerciseIllustration` the standalone demo shows, so the US-O01 Lottie
/// seam is preserved by construction: where a per-movement clip exists it plays, where none does the
/// SF-Symbol glyph shows, and Reduce Motion stills either - a text-and-ring-only window is deliberately
/// rejected as too bare (US-CC11 AC).
///
/// Unlike the Hold Timer it *auto-starts*: appearing is enough to begin the countdown, so a rep-based
/// set is hands-free with no Start tap. At zero the view model records the set completed (identical to a
/// tapped completion) and flows into the rest, firing the same accessible cue exactly once. The ticker
/// lives here so it exists only while the window is on screen, and it drives a *pure* check
/// (`completeWorkWindowIfElapsed`) that is a no-op until the deadline passes, so the cue can never fire
/// early or per tick. A swap finishing (`isSwapping` back to false) re-arms the window for whatever slot
/// now occupies the position.
private struct WorkWindowCountdownView: View {
    let viewModel: ActiveSessionViewModel
    let prescription: PrescribedExercise

    /// The compact ring's dimensions - smaller than the hold/rest ring so the movement illustration is
    /// the hero of the slot (the window is *visual*-primary, US-CC11) while the countdown stays legible
    /// beside it.
    private static let ringDiameter: CGFloat = 132
    private static let ringLineWidth: CGFloat = 10

    /// Drives the countdown display and the auto-advance/cue check. Kept off the view body so the
    /// mutation happens in an action closure, never during a render pass.
    @State private var currentDate = Date()
    private let ticker = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        // The full window is the planned per-set seconds; before the window has started (the brief
        // moment between appearing and `startWorkWindow()`) the ring shows that full value rather than
        // an empty zero, so it never flashes drained.
        let total = max(viewModel.workWindowSecondsPerSet ?? viewModel.workWindowTotalSeconds, 1)
        let remaining = viewModel.isRunningWorkWindow ? viewModel.workWindowRemaining(asOf: currentDate) : total

        HStack(spacing: Theme.Spacing.lg) {
            // The movement illustration leads - the user follows along by eye. It carries its own
            // "<name> demonstration" label so the ring, name, and target each stay distinct to VoiceOver.
            ExerciseIllustration(prescription: prescription, size: 132, animatesGlyph: false)
                .frame(maxWidth: .infinity)
                .accessibilityElement()
                .accessibilityLabel("\(prescription.exercise.displayName) demonstration")

            CountdownRing(
                remaining: remaining,
                fraction: min(1, max(0, Double(remaining) / Double(total))),
                accessibilityLabel: "Work window, \(remaining) seconds remaining",
                diameter: Self.ringDiameter,
                lineWidth: Self.ringLineWidth,
                font: Theme.Typography.title
            )
        }
        .padding(.horizontal, Theme.Spacing.lg)
        // Illustration and ring stand together in the demo's own card, so the visual-primary window
        // changes what is in the slot and nothing else - not the card under it, not the exercise name
        // and target below it.
        .exerciseSlotCard()
        // Auto-start on appear (hands-free) - and after a swap settles, where the view stays mounted so
        // no fresh `onAppear` fires. Both are idempotent via `canStartWorkWindow`.
        .onAppear { viewModel.startWorkWindow() }
        .onChange(of: viewModel.isSwapping) { _, swapping in
            if !swapping { viewModel.startWorkWindow() }
        }
        .onReceive(ticker) { date in
            currentDate = date
            // US-CC10: the optional midpoint tone, then the completion check. Both are pure no-ops until
            // their instant, so ordering them here fires the halfway cue before the window can elapse.
            viewModel.fireWorkWindowHalfwayIfReached(asOf: date)
            viewModel.completeWorkWindowIfElapsed(asOf: date)
        }
    }
}

// MARK: - Rest timer

/// The rest overlay between sets (US-K02).
///
/// After a set, the player advances to the next effort but shows this focused countdown first so the
/// user paces the work without watching the clock. A ring counts `restSeconds` down; when it reaches
/// zero the session auto-advances (the overlay dismisses to reveal the already-current next set) and
/// an accessible haptic/audio cue fires. The user can skip the rest or extend it by 15s; the parent
/// pauses the countdown on backgrounding. Every color, font, and dimension comes from `Theme`, and
/// every control meets the 60pt active-screen touch target.
private struct RestView: View {
    let viewModel: ActiveSessionViewModel
    let onClose: () -> Void

    /// Drives the countdown display and the auto-advance/cue check. Kept off the view body so the
    /// mutation happens in an action closure, never during a render pass.
    @State private var currentDate = Date()
    private let ticker = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        let remaining = viewModel.restRemaining(asOf: currentDate)
        let total = max(viewModel.restTotalSeconds, 1)
        let fraction = min(1, max(0, Double(remaining) / Double(total)))

        VStack(spacing: 0) {
            SessionTopBar(
                onClose: onClose,
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

            Spacer()

            VStack(spacing: Theme.Spacing.lg) {
                // A per-side bookend flows side 1 -> a brief "Switch sides" beat -> side 2 hands-free
                // (US-CC05); the beat reuses this rest overlay but names itself so the user knows to
                // change position rather than read it as a plain between-set rest. Every other gap - a
                // between-station transition (US-CC04) and a between-round rest - stays a "Rest" here; the
                // transition beat earns its distinctness below, in `nextUp`'s prominent "Next: <exercise>"
                // (US-CC11), rather than by renaming this shared header.
                let heading = viewModel.isSwitchingSides ? "Switch sides" : "Rest"
                Text(heading)
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.Colors.textSecondary)

                CountdownRing(
                    remaining: remaining,
                    fraction: fraction,
                    accessibilityLabel: heading + ", \(remaining) seconds remaining"
                )
                .padding(.horizontal, Theme.Spacing.lg)

                nextUp
            }

            Spacer()

            controls
        }
        .onReceive(ticker) { date in
            currentDate = date
            viewModel.completeRestIfElapsed(asOf: date)
        }
    }

    /// A preview of the effort the rest is pacing toward, so the user knows what is next. Inside a
    /// training-block circuit the rest paces toward a round ("Round N of M", US-CC02); a linear bookend
    /// paces toward the exercise's next set.
    ///
    /// A between-station **transition beat** (US-CC04) gets its own prominent treatment (US-CC11): since
    /// there is no spoken "next up", the movement name leads as a large "Next: <exercise>" so the visual
    /// cue reads at a glance rather than as a quiet caption. A between-round rest and a plain bookend
    /// rest keep the quieter "Next up" heading; a switch-sides beat names the owed side instead.
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
            VStack(spacing: Theme.Spacing.xs) {
                Text(transition ? "Next" : (switching ? "Same stretch" : "Next up"))
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                Text(name)
                    // The transition beat is the visual substitute for a spoken "next up", so the
                    // movement name is prominent (largeTitle) rather than the quieter headline a plain
                    // rest uses.
                    .font(transition ? Theme.Typography.largeTitle : Theme.Typography.headline)
                    .foregroundStyle(transition ? Theme.Colors.accent : Theme.Colors.textPrimary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Text(progressText)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .accessibilityElement(children: .combine)
            // The transition beat announces the prominent visual cue verbatim ("Next: <exercise>"); the
            // quieter rests keep their existing "<heading>, <name>, <progress>" phrasing.
            .accessibilityLabel(
                transition
                    ? "Next: \(name), \(progressText)"
                    : "\(switching ? "Same stretch" : "Next up"), \(name), \(progressText)"
            )
        }
    }

    /// Extend (+15s) and Skip - both meeting the 60pt active-screen touch target.
    private var controls: some View {
        HStack(spacing: Theme.Spacing.md) {
            Button {
                viewModel.extendRest()
            } label: {
                Text("+\(ActiveSessionViewModel.restExtension)s")
                    .font(Theme.Typography.button)
                    .frame(maxWidth: .infinity)
                    .frame(height: Theme.Spacing.workoutTouchTarget)
            }
            .buttonStyle(.bordered)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Spacing.cardCornerRadius))
            .accessibilityLabel("Extend rest by \(ActiveSessionViewModel.restExtension) seconds")

            Button {
                viewModel.skipRest()
            } label: {
                Text("Skip rest")
                    .font(Theme.Typography.button)
                    .frame(maxWidth: .infinity)
                    .frame(height: Theme.Spacing.workoutTouchTarget)
            }
            .buttonStyle(.borderedProminent)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Spacing.cardCornerRadius))
            .accessibilityLabel("Skip rest")
        }
        .padding(Theme.Spacing.lg)
    }
}

// MARK: - Exercise demo

/// The auto-playing exercise demonstration for the player (US-K01).
///
/// When the exercise names a bundled Lottie animation (US-O01) it plays that looping, auto-playing
/// animation; otherwise it renders a large, movement-appropriate SF Symbol that pulses continuously
/// to signal "this is the live demo". The Lottie path is the seam a richer per-exercise demo drops
/// into as its file is added - no animation files ship yet, so every exercise currently falls back
/// to its symbol, and a named-but-missing file falls back too, so a demo is never blank.
/// Under Reduce Motion the animation shows a static frame and the symbol drops its pulse for a
/// static glyph - the required accessible fallback - so the screen never animates against the
/// user's preference. The `"<displayName> demonstration"` accessibility label is retained.
struct ExerciseDemoView: View {
    let prescription: PrescribedExercise

    /// The height of the demo slot. Shared with the Hold Timer's countdown (US-O03) and the
    /// visual-primary work window (US-CC11), which both stand in this same slot, so swapping between the
    /// three shifts nothing below it.
    static let height: CGFloat = 220

    var body: some View {
        ExerciseIllustration(prescription: prescription)
            .exerciseSlotCard()
            .accessibilityElement()
            .accessibilityLabel("\(prescription.exercise.displayName) demonstration")
    }
}

/// The movement illustration itself - the bundled Lottie clip when the exercise names one that resolves
/// (US-O01), otherwise the movement-appropriate SF-Symbol glyph so a demonstration is never blank.
///
/// Carries no card chrome or accessibility of its own: `ExerciseDemoView` (US-K01) frames and labels it
/// in the standalone demo slot, and the visual-primary work window (US-CC11) embeds the same content
/// beside its countdown ring. Sharing one source is what keeps the Lottie fast-follow a data change -
/// dropping in ~71 per-movement clips lights them up in both hosts at once, no rewrite.
///
/// Under Reduce Motion the animation holds its first frame and the glyph drops its pulse for a static
/// glyph - the required accessible still - so the illustration never animates against the preference.
struct ExerciseIllustration: View {
    let prescription: PrescribedExercise

    /// The intrinsic size of the illustration content. The work window passes a smaller value so the
    /// glyph/clip sits comfortably beside its ring; the standalone demo slot keeps the roomier default.
    var size: CGFloat = 200

    /// Whether the SF-Symbol glyph pulses. The standalone demo pulses it to read as "this is the live
    /// demo" (US-K01); the visual-primary work window (US-CC11) wants a **static illustration at launch**
    /// (the countdown ring is the live element beside it, and the AC requires the illustration be still
    /// where no clip exists), so it passes `false`. A bundled Lottie clip still plays where one exists -
    /// the AC allows that - and Reduce Motion stills either regardless.
    var animatesGlyph: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if let name = prescription.exercise.animationName, LottieAnimation.named(name) != nil {
            LottieDemoView(animationName: name, isPlaying: !reduceMotion)
                .frame(width: size, height: size)
        } else {
            glyph
        }
    }

    @ViewBuilder
    private var glyph: some View {
        let base = Image(systemName: symbolName)
            .font(.system(size: size * 0.46, weight: .semibold))
            .foregroundStyle(Theme.Colors.accent)

        if reduceMotion || !animatesGlyph {
            base // static fallback - no animation against Reduce Motion, or where a still illustration is wanted
        } else {
            base.symbolEffect(.pulse, options: .repeating) // auto-plays continuously
        }
    }

    /// A movement-appropriate SF Symbol so the demo reads as the right kind of exercise.
    private var symbolName: String {
        switch prescription.exercise.movementPattern {
        case .push: return "figure.strengthtraining.traditional"
        case .squat: return "figure.cross.training"
        case .hinge: return "figure.strengthtraining.functional"
        case .core: return "figure.core.training"
        case .pull: return "figure.climbing"
        case .mobility: return "figure.flexibility"
        case .locomotion: return "figure.run"
        }
    }
}

/// Plays a bundled Lottie animation for the exercise demo (US-O01), looping and auto-playing.
///
/// When `isPlaying` is false (Reduce Motion) it holds the first frame as a static image rather than
/// animating, preserving the auto-play + static-fallback contract. The caller only constructs this
/// for an `animationName` that already resolved to a bundled file, so the animation is never nil.
private struct LottieDemoView: UIViewRepresentable {
    let animationName: String
    let isPlaying: Bool

    func makeUIView(context: Context) -> LottieAnimationView {
        let view = LottieAnimationView(name: animationName)
        view.contentMode = .scaleAspectFit
        view.loopMode = .loop
        apply(to: view)
        return view
    }

    func updateUIView(_ uiView: LottieAnimationView, context: Context) {
        let next = LottieAnimation.named(animationName)
        if uiView.animation !== next {
            uiView.animation = next
        }
        apply(to: uiView)
    }

    private func apply(to view: LottieAnimationView) {
        if isPlaying {
            if !view.isAnimationPlaying { view.play() }
        } else {
            view.pause()
            view.currentProgress = 0 // static first frame under Reduce Motion
        }
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
