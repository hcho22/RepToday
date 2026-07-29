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
struct ReadyView: View {
    @State private var viewModel: ReadyViewModel
    /// What the active-session player is presented for (US-K01/US-K04): a fresh session started from
    /// Start, or an abandoned session resumed from the Ready Screen. The `.fullScreenCover` presents
    /// the player for it and clears it on dismiss.
    @State private var presentedPlayer: PlayerPresentation?

    /// Held so the active-session player can be handed the engine seam for the in-session swap
    /// (US-K03) and the store it persists to (US-K04); the user and recent logs it also needs come
    /// from the loaded `viewModel`.
    private let services: ServiceContainer

    init(services: ServiceContainer) {
        self.services = services
        _viewModel = State(
            initialValue: ReadyViewModel(
                userService: services.userService,
                sessionPolicyService: services.sessionPolicyService,
                workoutEngine: services.workoutEngine,
                workoutLogService: services.workoutLogService,
                consistencyService: services.consistencyService,
                activeSessionStore: services.activeSessionStore
            )
        )
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
            } else if viewModel.isLoading {
                ProgressView().tint(Theme.Colors.accent)
            } else {
                emptyState
            }
        }
        .task { await viewModel.load() }
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
                    onFinish: { completed in Task { await viewModel.handlePlayerDismiss(completed: completed) } }
                )
            }
        }
    }

    // MARK: - Session

    private func sessionScroll(_ workout: Workout) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    header

                    if let state = viewModel.resumableSession {
                        ResumeSessionCard(
                            state: state,
                            onResume: { presentedPlayer = .resume(state) },
                            onDiscard: { Task { await viewModel.discardResumableSession() } }
                        )
                    }

                    if let consistency = viewModel.consistency {
                        ConsistencyCard(consistency: consistency)
                    }

                    if let note = viewModel.policyNote {
                        PolicyNoteCard(note: note)
                    }

                    durationChips

                    ForEach(workout.blocks) { block in
                        BlockCard(block: block)
                    }
                }
                .padding(Theme.Spacing.lg)
            }

            startBar
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(greeting)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)
            Text("Today: \(viewModel.requestedMinutes) min")
                .font(Theme.Typography.largeTitle)
                .foregroundStyle(Theme.Colors.textPrimary)
            Text(subtitle)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var greeting: String {
        let name = viewModel.user?.displayName ?? ""
        return name.isEmpty ? "Ready when you are." : "Ready when you are, \(name)."
    }

    /// The header subtitle *is* the Variety Language line when there is one - the honest "what today
    /// is" contrast the engine produced (US-G03). It falls back to a neutral line for a degenerate
    /// warm-up-only session that has no lead pillar to name.
    private var subtitle: String {
        viewModel.varietyNote?.text ?? "A complete session, ready to go."
    }

    // MARK: - Duration chips

    /// A non-blocking, one-tap duration selector. Tapping a chip regenerates the session in place on
    /// the sub-100ms engine; the current session and Start stay put while it swaps, so the screen
    /// never gates entry behind a duration question.
    private var durationChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.sm) {
                ForEach(viewModel.durationChips, id: \.self) { minutes in
                    DurationChip(
                        minutes: minutes,
                        isSelected: minutes == viewModel.selectedMinutes
                    ) {
                        Task { await viewModel.selectDuration(minutes) }
                    }
                }
            }
        }
    }

    /// The pinned, visually dominant Start action. It is always present and enabled - the Ready
    /// Screen never gates Start behind an unanswered question. Tapping it opens the active-session
    /// player (US-K01) for the already-generated session.
    private var startBar: some View {
        Button(action: { presentedPlayer = viewModel.workout.map(PlayerPresentation.fresh) }) {
            Text("Start")
                .font(Theme.Typography.button)
                .frame(maxWidth: .infinity)
                .frame(height: Theme.Spacing.buttonHeight)
        }
        .buttonStyle(.borderedProminent)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Spacing.cardCornerRadius))
        .padding(Theme.Spacing.lg)
        .background(Theme.Colors.background)
    }

    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "figure.strengthtraining.functional")
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(Theme.Colors.accent)
            Text(viewModel.errorMessage ?? "No session yet.")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
            Button("Try again") { Task { await viewModel.load() } }
                .font(Theme.Typography.button)
                .frame(minHeight: Theme.Spacing.minTouchTarget)
        }
        .padding(Theme.Spacing.lg)
    }
}

// MARK: - Duration chip

/// A single, compact duration pill in the Ready Screen's one-tap selector. The selected chip fills
/// with the accent color; the touch target meets the 44pt minimum.
private struct DurationChip: View {
    let minutes: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("\(minutes) min")
                .font(Theme.Typography.headline)
                .foregroundStyle(isSelected ? Theme.Colors.onAccent : Theme.Colors.textPrimary)
                .padding(.horizontal, Theme.Spacing.md)
                .frame(minWidth: Theme.Spacing.minTouchTarget, minHeight: Theme.Spacing.minTouchTarget)
                .background(
                    isSelected ? Theme.Colors.accent : Theme.Colors.surface,
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(minutes) minute session")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

// MARK: - Resume session card

/// The Resume-or-Discard surface for an abandoned session (US-K04): when the user backgrounded out of
/// - or a relaunch interrupted - a session before finishing, it is offered back here rather than
/// silently lost. Resume reopens the player at the exact position; Discard lets the session go. Copy
/// is identity-framed and never guilt-framed. Every control meets the 44pt minimum touch target.
private struct ResumeSessionCard: View {
    let state: ActiveSessionState
    let onResume: () -> Void
    let onDiscard: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text("Pick up where you left off")
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text(positionText)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }

            HStack(spacing: Theme.Spacing.md) {
                Button(action: onResume) {
                    Text("Resume")
                        .font(Theme.Typography.button)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: Theme.Spacing.minTouchTarget)
                }
                .buttonStyle(.borderedProminent)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Spacing.cardCornerRadius))
                .accessibilityLabel("Resume session")

                Button(action: onDiscard) {
                    Text("Discard")
                        .font(Theme.Typography.button)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: Theme.Spacing.minTouchTarget)
                }
                .buttonStyle(.bordered)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Spacing.cardCornerRadius))
                .accessibilityLabel("Discard session")
            }
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Spacing.cardCornerRadius))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Session in progress. \(positionText)")
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
/// "you missed" language, no XP.
private struct ConsistencyCard: View {
    let consistency: Consistency

    private var hasHistory: Bool { consistency.totalWorkoutsCompleted > 0 }

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text("You're someone who moves.")
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text(pride)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }

            if hasHistory {
                Spacer(minLength: Theme.Spacing.md)
                VStack(spacing: 0) {
                    Text("\(Int(consistency.score.rounded()))")
                        .font(Theme.Typography.largeTitle)
                        .foregroundStyle(Theme.Colors.accent)
                    Text("consistency")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Spacing.cardCornerRadius))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    /// The earned point of pride - the longest on-goal run ever achieved - or an encouraging,
    /// never-loss-framed line for a user without a run yet.
    private var pride: String {
        guard consistency.longestChain > 0 else {
            return "Every time you show up counts - even five minutes."
        }
        let unit = consistency.longestChain == 1 ? "week" : "weeks"
        return "Best run: \(consistency.longestChain) \(unit) on goal."
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
/// names a change the sessions actually reflect. Rendered as a light accent callout, never a nag.
private struct PolicyNoteCard: View {
    let note: SessionPolicy.Note

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            Image(systemName: "sparkles")
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.accent)
            Text(note.text)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textPrimary)
            Spacer(minLength: 0)
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Spacing.cardCornerRadius))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("What changed: \(note.text)")
    }
}

// MARK: - Block card

/// One session block (warm-up / training / cooldown) with its prescribed exercises and targets.
private struct BlockCard: View {
    let block: WorkoutBlock

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text(block.title)
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.textPrimary)

            VStack(spacing: Theme.Spacing.sm) {
                ForEach(block.exercises) { prescription in
                    ExerciseRow(prescription: prescription)
                }
            }
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Spacing.cardCornerRadius))
    }
}

private struct ExerciseRow: View {
    let prescription: PrescribedExercise

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(prescription.exercise.displayName)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textPrimary)
            Spacer(minLength: Theme.Spacing.md)
            Text(targetText)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.trailing)
        }
        .frame(minHeight: Theme.Spacing.minTouchTarget)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(prescription.exercise.displayName), \(targetText)")
    }

    /// "3 × 12" for rep-based movements, "3 × 0:30" for holds.
    private var targetText: String {
        if let reps = prescription.reps {
            return "\(prescription.sets) × \(reps)"
        }
        if let seconds = prescription.durationSeconds {
            let minutes = seconds / 60
            let remainder = seconds % 60
            let time = String(format: "%d:%02d", minutes, remainder)
            return "\(prescription.sets) × \(time)"
        }
        return "\(prescription.sets) sets"
    }
}

#Preview {
    ReadyView(services: .mock())
}
