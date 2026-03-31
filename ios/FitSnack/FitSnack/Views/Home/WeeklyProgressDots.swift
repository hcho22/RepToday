import SwiftUI

struct WeeklyProgressDots: View {
    let stats: HomeViewModel.WeeklyStats

    private let days = ["M", "T", "W", "T", "F", "S", "S"]
    private let fullDays = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]

    /// Index of today in Mon=0..Sun=6 layout
    private var todayIndex: Int {
        let weekday = Calendar.current.component(.weekday, from: Date()) // 1=Sun,2=Mon,...,7=Sat
        return weekday == 1 ? 6 : weekday - 2
    }

    var body: some View {
        FitSnackCard {
            VStack(spacing: AppSpacing.sm) {
                HStack {
                    Text("This Week")
                        .font(AppTypography.headline)
                        .foregroundStyle(AppColors.textPrimary)
                    Spacer()
                    Text("\(stats.completed) of \(stats.goal) done")
                        .font(AppTypography.subheadline)
                        .foregroundStyle(AppColors.textSecondary)
                }

                HStack(spacing: AppSpacing.sm) {
                    ForEach(0..<7, id: \.self) { index in
                        VStack(spacing: AppSpacing.xs) {
                            Circle()
                                .fill(stats.completedDays[index] ? AppColors.success : AppColors.divider)
                                .frame(width: 28, height: 28)
                                .overlay {
                                    if stats.completedDays[index] {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundStyle(.white)
                                    }
                                }
                                .overlay {
                                    if index == todayIndex {
                                        Circle()
                                            .strokeBorder(AppColors.brand, lineWidth: 2.5)
                                            .frame(width: 34, height: 34)
                                    }
                                }
                            Text(days[index])
                                .font(AppTypography.caption)
                                .foregroundStyle(AppColors.textSecondary)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(fullDays[index])\(index == todayIndex ? ", today" : ""): \(stats.completedDays[index] ? "completed" : "not completed")")
                        if index < 6 { Spacer() }
                    }
                }
            }
        }
    }
}
