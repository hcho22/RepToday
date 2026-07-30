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
/// movements, which counts one side of the hold down and records the set at zero. Rep-based exercises
/// keep the manual set tracker and "Complete set" exactly as they were.
struct ActiveSessionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var viewModel: ActiveSessionViewModel

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
                completionService: completionService
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
                completionService: completionService
            )
        )
    }

    /// Dismiss the player, first reporting whether the session completed so the Ready Screen can
    /// refresh deterministically rather than racing the store (US-K04). Every dismiss path routes
    /// through here, so the completion signal is never missed.
    private func close() {
        onFinish?(viewModel.isComplete)
        dismiss()
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
        }
        .onAppear {
            viewModel.start()
            // A rest or hold paused on backgrounding and restored from a snapshot (US-K04/US-O03) never
            // sees a scene-phase change when the resumed player is presented on an already-active app,
            // so resume both here too. No-ops unless one is currently paused, leaving a fresh session
            // and a resumed running countdown untouched.
            viewModel.resumeRest(asOf: Date())
            viewModel.resumeHold(asOf: Date())
            // The user puts the phone down mid-plank; the screen must not lock out from under a
            // running countdown, or its cue never lands. Scoped to the player and released on exit.
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        // Pause both countdowns while the app is away so neither blows past - and so a hold's cue can
        // never fire at a screen the user is not looking at; resume on return. The elapsed session
        // clock is wall-clock derived (US-K01) and intentionally keeps running, unseen (US-O03).
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                viewModel.resumeRest(asOf: Date())
                viewModel.resumeHold(asOf: Date())
            case .inactive, .background:
                viewModel.pauseRest(asOf: Date())
                viewModel.pauseHold(asOf: Date())
            @unknown default:
                break
            }
        }
    }

    // MARK: - Player

    private var player: some View {
        VStack(spacing: 0) {
            SessionTopBar(onClose: close)

            ProgressView(value: viewModel.progress)
                .tint(Theme.Colors.accent)
                .padding(.horizontal, Theme.Spacing.lg)

            if let step = viewModel.currentStep {
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                        blockContext(step)
                        // While a hold runs, the countdown takes the demo's place: the user is already
                        // in position, so what they need on screen is the time left, not the shape.
                        if viewModel.isHolding {
                            HoldCountdownView(viewModel: viewModel)
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

    /// Set tracking: which set of how many, with a dot per set filled as they are completed. A per-side
    /// hold names the side too, because its set is two legs and the Hold Timer only counts one of them
    /// at a time - without it the user has no way to tell a finished set from a half-finished one.
    private func setTracker(_ step: ActiveSessionViewModel.Step) -> some View {
        let sides = viewModel.holdSidesPerSet
        let showsSide = viewModel.holdSecondsPerSide != nil && sides > 1
        let setText = "Set \(viewModel.currentSet) of \(step.prescription.sets)"
        let sideText = "Side \(viewModel.holdSide) of \(sides)"

        return VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(setText)
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
        .accessibilityLabel(showsSide ? "\(setText), side \(viewModel.holdSide) of \(sides)" : setText)
    }

    /// The primary action plus quieter "swap" and "skip" - all meeting the 60pt active-screen touch
    /// target. Which primary action shows depends on the movement (US-O03): a rep-based exercise keeps
    /// "Complete set", and completing the last set of the last exercise finishes the session; a timed
    /// one offers "Start hold" instead, and the countdown records its own set at zero, so it is the
    /// timer - not a tap - that advances. Swapping (US-K03) replaces the current movement with a
    /// same-pillar/pattern peer, or, when none is safe and in budget, surfaces an honest "no
    /// alternative" notice above the actions.
    private var controls: some View {
        VStack(spacing: Theme.Spacing.sm) {
            if viewModel.noSwapAlternative {
                noAlternativeNotice
            }

            primaryAction

            HStack(spacing: Theme.Spacing.md) {
                // A swap reshapes the slot the countdown is timing, so it is offered between holds
                // rather than during one. Skip stays, as the escape hatch it is on every other slot.
                if viewModel.canSwap && !viewModel.isHolding {
                    Button {
                        Task { await viewModel.swapCurrentExercise() }
                    } label: {
                        Text(viewModel.isSwapping ? "Swapping…" : "Swap")
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .frame(maxWidth: .infinity)
                            .frame(height: Theme.Spacing.workoutTouchTarget)
                    }
                    .disabled(viewModel.isSwapping)
                    .accessibilityLabel("Swap this exercise")
                    .accessibilityHint("Replaces it with a similar movement")
                }

                Button {
                    viewModel.skipExercise()
                } label: {
                    Text("Skip")
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: Theme.Spacing.workoutTouchTarget)
                }
                .accessibilityLabel("Skip this exercise")
            }
        }
        .padding(Theme.Spacing.lg)
        .background(Theme.Colors.background)
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
        } else if viewModel.canStartHold {
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
            .accessibilityLabel(startHoldAccessibilityTitle)
            .accessibilityHint("Counts the hold down and records the set when it reaches zero")
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

/// The player's top bar, shared by the exercise screen and the rest overlay.
///
/// It carries the close control and nothing else. It used to carry an always-on elapsed clock, which
/// US-O03 removed: no running session clock is visible anywhere during the session, so the total lands
/// once, on the completion summary, instead of counting at the user the whole way through.
private struct SessionTopBar: View {
    let onClose: () -> Void

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

    private static let diameter: CGFloat = 200
    private static let lineWidth: CGFloat = 12

    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.Colors.surface, lineWidth: Self.lineWidth)

            Circle()
                .trim(from: 0, to: fraction)
                .stroke(Theme.Colors.accent, style: StrokeStyle(lineWidth: Self.lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.5), value: fraction)

            Text(ActiveSessionView.clockText(remaining))
                .font(Theme.Typography.largeTitle)
                .monospacedDigit()
                .foregroundStyle(Theme.Colors.textPrimary)
        }
        .frame(width: Self.diameter, height: Self.diameter)
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
        // Matches the demo card it stands in for, so starting a hold swaps the content without
        // shifting the exercise name and target underneath it.
        .frame(maxWidth: .infinity)
        .frame(height: ExerciseDemoView.height)
        .onReceive(ticker) { date in
            currentDate = date
            viewModel.completeHoldIfElapsed(asOf: date)
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
            SessionTopBar(onClose: onClose)

            Spacer()

            VStack(spacing: Theme.Spacing.lg) {
                Text("Rest")
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.Colors.textSecondary)

                CountdownRing(
                    remaining: remaining,
                    fraction: fraction,
                    accessibilityLabel: "Rest, \(remaining) seconds remaining"
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

    /// A preview of the effort the rest is pacing toward, so the user knows what is next.
    @ViewBuilder
    private var nextUp: some View {
        if let step = viewModel.currentStep {
            VStack(spacing: Theme.Spacing.xs) {
                Text("Next up")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                Text(step.prescription.exercise.displayName)
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text("Set \(viewModel.currentSet) of \(step.prescription.sets)")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Next up, \(step.prescription.exercise.displayName), set \(viewModel.currentSet) of \(step.prescription.sets)")
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The height of the demo slot. Shared with the Hold Timer's countdown (US-O03), which stands in
    /// this same slot while a hold runs, so the swap between them shifts nothing below it.
    static let height: CGFloat = 220

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Theme.Spacing.cardCornerRadius)
                .fill(Theme.Colors.secondaryBackground)
            demo
        }
        .frame(maxWidth: .infinity)
        .frame(height: Self.height)
        .accessibilityElement()
        .accessibilityLabel("\(prescription.exercise.displayName) demonstration")
    }

    /// The bundled Lottie animation when the exercise names one that actually resolves to a file,
    /// else the SF-Symbol fallback so a demo is never blank.
    @ViewBuilder
    private var demo: some View {
        if let name = prescription.exercise.animationName, LottieAnimation.named(name) != nil {
            LottieDemoView(animationName: name, isPlaying: !reduceMotion)
                .frame(width: 200, height: 200)
        } else {
            glyph
        }
    }

    @ViewBuilder
    private var glyph: some View {
        let base = Image(systemName: symbolName)
            .font(.system(size: 92, weight: .semibold))
            .foregroundStyle(Theme.Colors.accent)

        if reduceMotion {
            base // static fallback - no animation against the user's Reduce Motion preference
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
