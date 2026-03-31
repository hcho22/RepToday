import SwiftUI

struct WorkoutCompleteView: View {
    let viewModel: WorkoutViewModel
    let weeklyStreak: Int
    let onDone: (Int, Workout.PerceivedDifficulty) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedRating: Int = 3
    @State private var selectedDifficulty: Workout.PerceivedDifficulty? = .justRight
    @State private var displayedXP: Int = 0
    @State private var showCelebration = false

    private var earnedXP: Int {
        viewModel.elapsedSeconds / 60 * Constants.XP.perMinute
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.lg) {
                // Celebration
                Image(systemName: "party.popper.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(Theme.Colors.success)
                    .padding(.top, Theme.Spacing.xl)
                    .scaleEffect(showCelebration ? 1.0 : 0.5)
                    .opacity(showCelebration ? 1.0 : 0.0)
                    .animation(reduceMotion ? .none : .spring(response: 0.6, dampingFraction: 0.6), value: showCelebration)

                Text("Workout Complete!")
                    .font(Theme.Typography.largeTitle)
                    .foregroundStyle(Theme.Colors.textPrimary)

                // Stats summary
                HStack(spacing: Theme.Spacing.xl) {
                    statItem(value: viewModel.elapsedFormatted, label: "Duration")
                    statItem(value: "\(viewModel.completedExercises)", label: "Exercises")
                    statItem(value: "\(viewModel.workout.estimatedCalories ?? viewModel.workout.requestedDurationMinutes * 5)", label: "~Cal")
                }
                .padding(.vertical, Theme.Spacing.md)

                // Muscle groups
                let muscles = Set(viewModel.workout.allExercises.flatMap { $0.exercise.muscleGroups.primary.map(\.displayName) })
                if !muscles.isEmpty {
                    VStack(spacing: Theme.Spacing.sm) {
                        Text("Muscles Worked")
                            .font(Theme.Typography.headline)
                        FlowLayout(spacing: Theme.Spacing.xs) {
                            ForEach(Array(muscles), id: \.self) { muscle in
                                Text(muscle)
                                    .font(Theme.Typography.caption)
                                    .padding(.horizontal, Theme.Spacing.sm)
                                    .padding(.vertical, Theme.Spacing.xs)
                                    .background(Theme.Colors.brand.opacity(0.1))
                                    .clipShape(Capsule())
                            }
                        }
                    }
                }

                Divider()
                    .padding(.horizontal, Theme.Spacing.lg)

                // Rating
                VStack(spacing: Theme.Spacing.md) {
                    Text("How was your workout?")
                        .font(Theme.Typography.headline)

                    RatingPicker(selectedRating: $selectedRating)
                }

                // Difficulty
                VStack(spacing: Theme.Spacing.md) {
                    Text("How did it feel?")
                        .font(Theme.Typography.headline)

                    DifficultyPicker(selectedDifficulty: $selectedDifficulty)
                }

                // XP earned with count-up animation
                FitSnackCard {
                    HStack {
                        Image(systemName: "star.fill")
                            .foregroundStyle(Theme.Colors.warning)
                        Text("+\(displayedXP) XP earned!")
                            .font(Theme.Typography.headline)
                            .foregroundStyle(Theme.Colors.textPrimary)
                            .contentTransition(.numericText())
                    }
                }
                .padding(.horizontal, Theme.Spacing.lg)

                // Streak display
                if weeklyStreak > 0 {
                    FitSnackCard {
                        HStack {
                            Image(systemName: "flame.fill")
                                .foregroundStyle(Theme.Colors.fire)
                            Text("Week \(weeklyStreak) streak!")
                                .font(Theme.Typography.headline)
                                .foregroundStyle(Theme.Colors.textPrimary)
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.lg)
                    .transition(.scale.combined(with: .opacity))
                }

                PrimaryButton(title: "Done") {
                    onDone(selectedRating, selectedDifficulty ?? .justRight)
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.bottom, Theme.Spacing.xl)
            }
        }
        .onAppear {
            showCelebration = true
            if reduceMotion {
                displayedXP = earnedXP
            } else {
                animateXPCount()
            }
        }
    }

    private func statItem(value: String, label: String) -> some View {
        VStack(spacing: Theme.Spacing.xs) {
            Text(value)
                .font(Theme.Typography.title)
                .foregroundStyle(Theme.Colors.brand)
            Text(label)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
    }

    private func animateXPCount() {
        let target = earnedXP
        guard target > 0 else { return }
        let steps = min(target, 20)
        let interval = 0.8 / Double(steps)

        for i in 1...steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * interval) {
                withAnimation(.easeOut(duration: 0.1)) {
                    displayedXP = target * i / steps
                }
            }
        }
    }
}

// Simple flow layout for tags
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private func arrangeSubviews(proposal: ProposedViewSize, subviews: Subviews) -> (positions: [CGPoint], size: CGSize) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }

        return (positions, CGSize(width: maxWidth, height: y + rowHeight))
    }
}
