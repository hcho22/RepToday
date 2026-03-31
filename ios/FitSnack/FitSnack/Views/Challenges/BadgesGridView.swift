import SwiftUI

struct BadgesGridView: View {
    let badges: [Badge]
    @State private var selectedBadge: Badge?

    private let columns = [
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible()),
    ]

    var body: some View {
        FitSnackCard {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                HStack {
                    Text("Badges")
                        .font(AppTypography.headline)
                        .foregroundStyle(AppColors.textPrimary)
                    Spacer()
                    Text("\(badges.filter(\.isUnlocked).count)/\(badges.count)")
                        .font(AppTypography.subheadline)
                        .foregroundStyle(AppColors.textSecondary)
                }

                LazyVGrid(columns: columns, spacing: AppSpacing.md) {
                    ForEach(badges) { badge in
                        Button {
                            selectedBadge = badge
                        } label: {
                            BadgeItemView(badge: badge)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .sheet(item: $selectedBadge) { badge in
            BadgeDetailView(badge: badge)
        }
    }
}

struct BadgeItemView: View {
    let badge: Badge

    var body: some View {
        VStack(spacing: AppSpacing.xs) {
            Image(systemName: badge.iconName)
                .font(.system(size: 28))
                .foregroundStyle(badge.isUnlocked ? AppColors.warning : AppColors.textSecondary.opacity(0.3))
                .frame(width: 56, height: 56)
                .background(badge.isUnlocked ? AppColors.warning.opacity(0.1) : AppColors.divider.opacity(0.3))
                .clipShape(Circle())
                .overlay {
                    if !badge.isUnlocked {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }

            Text(badge.name)
                .font(AppTypography.caption)
                .foregroundStyle(badge.isUnlocked ? AppColors.textPrimary : AppColors.textSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .opacity(badge.isUnlocked ? 1 : 0.5)
        .accessibilityLabel("\(badge.name): \(badge.isUnlocked ? "unlocked" : "locked")")
    }
}
