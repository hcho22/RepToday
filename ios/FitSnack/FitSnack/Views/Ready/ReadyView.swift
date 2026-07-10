import SwiftUI

/// The minimal Ready Screen the app opens to after onboarding (US-I01).
///
/// It renders the complete session the deterministic engine generated at the user's Default
/// Duration - blocks and their prescribed exercises - with one dominant "Start" action, so there is
/// never a picker to clear before moving. There is no XP, no levels, and no badges; every token
/// comes from `Theme`.
///
/// US-J01 adds the non-blocking duration chip: a one-tap row offering 5/10/15/20/30/45/60 that
/// regenerates the session in place while Start stays present and enabled. The Variety Language
/// line, Consistency Score, policy note, and re-program-on-open (US-J02) build on this same
/// view/view model next. The Start action opens the active-session player in US-K01.
struct ReadyView: View {
    @State private var viewModel: ReadyViewModel

    init(services: ServiceContainer) {
        _viewModel = State(
            initialValue: ReadyViewModel(
                userService: services.userService,
                sessionPolicyService: services.sessionPolicyService,
                workoutEngine: services.workoutEngine,
                workoutLogService: services.workoutLogService
            )
        )
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
    }

    // MARK: - Session

    private func sessionScroll(_ workout: Workout) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    header

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
            Text("A complete session, ready to go.")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var greeting: String {
        let name = viewModel.user?.displayName ?? ""
        return name.isEmpty ? "You're someone who moves." : "Ready when you are, \(name)."
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
    /// Screen never gates Start behind an unanswered question. The active-session player is US-K01.
    private var startBar: some View {
        Button(action: {}) {
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
