import SwiftUI

struct BadgeDetailView: View {
    let badge: Badge

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showCelebration = false
    @State private var shimmer = false

    var body: some View {
        VStack(spacing: AppSpacing.lg) {
            ZStack {
                // Celebration rings behind badge
                if badge.isUnlocked && showCelebration {
                    Circle()
                        .stroke(AppColors.warning.opacity(0.3), lineWidth: 3)
                        .frame(width: 140, height: 140)
                        .scaleEffect(showCelebration ? 1.4 : 0.8)
                        .opacity(showCelebration ? 0.0 : 1.0)

                    Circle()
                        .stroke(AppColors.warning.opacity(0.2), lineWidth: 2)
                        .frame(width: 140, height: 140)
                        .scaleEffect(showCelebration ? 1.8 : 0.8)
                        .opacity(showCelebration ? 0.0 : 1.0)
                }

                Image(systemName: badge.iconName)
                    .font(.system(size: 56))
                    .foregroundStyle(badge.isUnlocked ? AppColors.warning : AppColors.textSecondary.opacity(0.3))
                    .frame(width: 100, height: 100)
                    .background(badge.isUnlocked ? AppColors.warning.opacity(0.1) : AppColors.divider.opacity(0.3))
                    .clipShape(Circle())
                    .overlay {
                        if !badge.isUnlocked {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(AppColors.textSecondary)
                        }
                    }
                    .scaleEffect(badge.isUnlocked && showCelebration ? 1.0 : (badge.isUnlocked ? 0.8 : 1.0))
            }

            Text(badge.name)
                .font(AppTypography.title2)
                .foregroundStyle(AppColors.textPrimary)

            Text(badge.description)
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)

            Divider()

            VStack(spacing: AppSpacing.sm) {
                Label(badge.criteria, systemImage: "target")
                    .font(AppTypography.subheadline)
                    .foregroundStyle(AppColors.textSecondary)

                if badge.isUnlocked, let date = badge.unlockedAt {
                    Label("Unlocked \(date.formatted(date: .abbreviated, time: .omitted))", systemImage: "checkmark.seal.fill")
                        .font(AppTypography.subheadline)
                        .foregroundStyle(AppColors.success)
                        .transition(.scale.combined(with: .opacity))
                }
            }

            Spacer()
        }
        .padding(AppSpacing.lg)
        .presentationDetents([.medium])
        .onAppear {
            guard badge.isUnlocked, !reduceMotion else {
                showCelebration = badge.isUnlocked
                return
            }
            withAnimation(.spring(response: 0.6, dampingFraction: 0.5).delay(0.2)) {
                showCelebration = true
            }
        }
    }
}
