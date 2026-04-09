import SwiftUI

struct ProgressionChainView: View {
    @Environment(\.services) private var services
    @State private var chains: [ProgressionChain] = []
    @State private var userLevels: [String: Int] = [:]
    @State private var isLoading = true

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if activeChains.isEmpty {
                ContentUnavailableView(
                    "No Chains Available",
                    systemImage: "arrow.up.right",
                    description: Text("Progression chains will appear here once exercises are available.")
                )
            } else {
                ScrollView {
                    VStack(spacing: AppSpacing.md) {
                        ForEach(activeChains) { chain in
                            let level = userLevels[chain.id] ?? 0
                            NavigationLink(destination: ProgressionChainDetailView(
                                chain: chain,
                                userLevel: level,
                                exercises: exercisesFor(chain)
                            )) {
                                chainCard(chain: chain, userLevel: level)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, AppSpacing.md)
                    .padding(.top, AppSpacing.md)
                }
            }
        }
        .background(AppColors.background)
        .navigationTitle("Progression Chains")
        .task { await loadData() }
    }

    /// Only show chains that have exercises
    private var activeChains: [ProgressionChain] {
        chains.filter { !$0.levels.isEmpty }
    }

    private func chainCard(chain: ProgressionChain, userLevel: Int) -> some View {
        let totalLevels = chain.levels.count
        let currentExercise = exerciseAt(level: userLevel, in: chain)
        let progress = totalLevels > 0 ? Double(userLevel) / Double(totalLevels) : 0

        return FitSnackCard {
            HStack(spacing: AppSpacing.md) {
                // Icon
                Image(systemName: iconFor(chain.movementPattern))
                    .font(.system(size: 28))
                    .foregroundStyle(AppColors.brand)
                    .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text(chain.name)
                        .font(AppTypography.headline)
                        .foregroundStyle(AppColors.textPrimary)

                    Text(currentExercise?.displayName ?? "Not started")
                        .font(AppTypography.subheadline)
                        .foregroundStyle(AppColors.textSecondary)

                    HStack(spacing: AppSpacing.sm) {
                        ProgressView(value: progress)
                            .tint(AppColors.brand)

                        Text("Level \(userLevel) of \(totalLevels)")
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.textSecondary)
                            .fixedSize()
                    }
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .foregroundStyle(AppColors.textSecondary)
                    .font(.system(size: 14, weight: .semibold))
            }
        }
    }

    private func exerciseAt(level: Int, in chain: ProgressionChain) -> Exercise? {
        guard let services, level < chain.levels.count else { return nil }
        let exerciseId = chain.levels[level].exerciseId
        return services.exercise.getExercise(by: exerciseId)
    }

    private func exercisesFor(_ chain: ProgressionChain) -> [Exercise] {
        guard let services else { return [] }
        return chain.levels.compactMap { services.exercise.getExercise(by: $0.exerciseId) }
    }

    private func loadData() async {
        guard let services else { return }
        chains = services.progression.getAllChains()

        var levels: [String: Int] = [:]
        for chain in chains {
            if let level = try? await services.progression.getUserLevel(for: chain.id) {
                levels[chain.id] = level
            }
        }
        userLevels = levels
        isLoading = false
    }

    private func iconFor(_ pattern: MovementPattern) -> String {
        switch pattern {
        case .pushHorizontal, .pushVertical: "arrow.up.forward"
        case .pullVertical, .pullHorizontal: "arrow.down.backward"
        case .squat: "figure.strengthtraining.functional"
        case .hinge: "figure.flexibility"
        case .coreAntiExtension, .coreFlexion, .coreRotation, .coreCompression: "figure.core.training"
        case .primal: "figure.mixed.cardio"
        default: "figure.run"
        }
    }
}
