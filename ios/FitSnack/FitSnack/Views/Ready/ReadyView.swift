import SwiftUI

/// The minimal Ready Screen the app opens to after onboarding (US-I01).
///
/// It renders the complete session the deterministic engine generated at the user's Default
/// Duration - blocks and their prescribed exercises - with one dominant "Start" action, so there is
/// never a picker to clear before moving. There is no XP, no levels, and no badges; every token
/// comes from `Theme`.
///
/// This is the landing surface US-I01 needs. The richer Ready Screen - the non-blocking duration
/// chip with instant regeneration (US-J01) and the Variety Language line, Consistency Score, policy
/// note, and re-program-on-open (US-J02) - builds on this same view/view model in Epic J. The Start
/// action opens the active-session player in US-K01.
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
