import SwiftUI

struct ProgressionChainDetailView: View {
    let chain: ProgressionChain
    let userLevel: Int
    let exercises: [Exercise]

    @State private var selectedExercise: Exercise?
    @State private var selectedLevelIndex: Int?

    var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.lg) {
                // Chain description
                Text(chain.description)
                    .font(AppTypography.subheadline)
                    .foregroundStyle(AppColors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, AppSpacing.md)

                // Horizontal chain visualization
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        ForEach(Array(chain.levels.enumerated()), id: \.offset) { index, level in
                            let exercise = exercises.first { $0.id == level.exerciseId }
                            let state = levelState(for: index)

                            HStack(spacing: 0) {
                                chainNode(
                                    exercise: exercise,
                                    level: level,
                                    index: index,
                                    state: state
                                )

                                if index < chain.levels.count - 1 {
                                    connectorLine(completed: index < userLevel)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, AppSpacing.md)
                    .padding(.vertical, AppSpacing.sm)
                }

                // Selected exercise detail
                if let selectedIndex = selectedLevelIndex,
                   selectedIndex < chain.levels.count {
                    let level = chain.levels[selectedIndex]
                    let exercise = exercises.first { $0.id == level.exerciseId }
                    exerciseDetailCard(
                        exercise: exercise,
                        level: level,
                        index: selectedIndex
                    )
                    .padding(.horizontal, AppSpacing.md)
                }

                // All exercises list
                VStack(alignment: .leading, spacing: AppSpacing.md) {
                    Text("All Exercises")
                        .font(AppTypography.headline)
                        .foregroundStyle(AppColors.textPrimary)
                        .padding(.horizontal, AppSpacing.md)

                    ForEach(Array(chain.levels.enumerated()), id: \.offset) { index, level in
                        let exercise = exercises.first { $0.id == level.exerciseId }
                        let state = levelState(for: index)

                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedLevelIndex = index
                            }
                        } label: {
                            exerciseRow(
                                exercise: exercise,
                                level: level,
                                index: index,
                                state: state
                            )
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, AppSpacing.md)
                    }
                }
            }
            .padding(.top, AppSpacing.md)
        }
        .background(AppColors.background)
        .navigationTitle(chain.name)
    }

    // MARK: - Level State

    private enum LevelState {
        case completed, current, locked
    }

    private func levelState(for index: Int) -> LevelState {
        if index < userLevel { return .completed }
        if index == userLevel { return .current }
        return .locked
    }

    // MARK: - Chain Node

    private func chainNode(exercise: Exercise?, level: ProgressionChain.ChainLevel, index: Int, state: LevelState) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedLevelIndex = index
            }
        } label: {
            VStack(spacing: AppSpacing.sm) {
                ZStack {
                    Circle()
                        .fill(nodeBackground(for: state))
                        .frame(width: 56, height: 56)

                    if state == .completed {
                        Image(systemName: "checkmark")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(.white)
                    } else {
                        Text("\(index + 1)")
                            .font(AppTypography.headline)
                            .foregroundStyle(state == .current ? .white : AppColors.textSecondary)
                    }
                }
                .overlay {
                    if state == .current {
                        Circle()
                            .strokeBorder(AppColors.brandLight, lineWidth: 3)
                            .frame(width: 64, height: 64)
                    }
                }

                Text(exercise?.displayName ?? "Exercise \(index + 1)")
                    .font(AppTypography.caption)
                    .foregroundStyle(state == .locked ? AppColors.textSecondary.opacity(0.5) : AppColors.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(width: 80)
            }
            .frame(minHeight: 100)
        }
        .buttonStyle(.plain)
    }

    private func connectorLine(completed: Bool) -> some View {
        Rectangle()
            .fill(completed ? AppColors.success : AppColors.divider)
            .frame(width: 32, height: 3)
            .padding(.bottom, 30)
    }

    private func nodeBackground(for state: LevelState) -> Color {
        switch state {
        case .completed: AppColors.success
        case .current: AppColors.brand
        case .locked: AppColors.divider
        }
    }

    // MARK: - Exercise Detail Card

    private func exerciseDetailCard(exercise: Exercise?, level: ProgressionChain.ChainLevel, index: Int) -> some View {
        let state = levelState(for: index)

        return FitSnackCard {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                HStack {
                    stateIcon(for: state)
                    Text(exercise?.displayName ?? "Exercise \(index + 1)")
                        .font(AppTypography.title2)
                        .foregroundStyle(AppColors.textPrimary)
                    Spacer()
                    Text("Level \(index + 1)")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textSecondary)
                }

                if let description = exercise?.description, !description.isEmpty {
                    Text(description)
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.textSecondary)
                }

                Divider()

                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    Text("Advancement Criteria")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textSecondary)

                    Text(level.advancementCriteria)
                        .font(AppTypography.headline)
                        .foregroundStyle(AppColors.brand)
                }

                if state == .completed {
                    Label("Completed", systemImage: "checkmark.circle.fill")
                        .font(AppTypography.subheadline)
                        .foregroundStyle(AppColors.success)
                } else if state == .current {
                    Label("Current Level", systemImage: "star.fill")
                        .font(AppTypography.subheadline)
                        .foregroundStyle(AppColors.brand)
                } else {
                    Label("Locked", systemImage: "lock.fill")
                        .font(AppTypography.subheadline)
                        .foregroundStyle(AppColors.textSecondary)
                }
            }
        }
    }

    // MARK: - Exercise Row

    private func exerciseRow(exercise: Exercise?, level: ProgressionChain.ChainLevel, index: Int, state: LevelState) -> some View {
        FitSnackCard {
            HStack(spacing: AppSpacing.md) {
                stateIcon(for: state)

                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text(exercise?.displayName ?? "Exercise \(index + 1)")
                        .font(AppTypography.body)
                        .foregroundStyle(state == .locked ? AppColors.textSecondary.opacity(0.5) : AppColors.textPrimary)

                    Text(level.advancementCriteria)
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textSecondary)
                }

                Spacer()

                Text("Level \(index + 1)")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
        .opacity(state == .locked ? 0.6 : 1.0)
    }

    @ViewBuilder
    private func stateIcon(for state: LevelState) -> some View {
        switch state {
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 24))
                .foregroundStyle(AppColors.success)
        case .current:
            Image(systemName: "star.circle.fill")
                .font(.system(size: 24))
                .foregroundStyle(AppColors.brand)
        case .locked:
            Image(systemName: "lock.circle.fill")
                .font(.system(size: 24))
                .foregroundStyle(AppColors.textSecondary.opacity(0.4))
        }
    }
}
