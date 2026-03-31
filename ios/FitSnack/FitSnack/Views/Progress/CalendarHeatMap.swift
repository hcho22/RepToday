import SwiftUI

struct CalendarHeatMap: View {
    let data: [Date: Int]

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
    private let dayLabels = ["M", "T", "W", "T", "F", "S", "S"]

    var body: some View {
        FitSnackCard {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                HStack {
                    Text(monthYearString)
                        .font(AppTypography.headline)
                        .foregroundStyle(AppColors.textPrimary)
                    Spacer()
                }

                // Day labels
                HStack(spacing: 4) {
                    ForEach(dayLabels.indices, id: \.self) { i in
                        Text(dayLabels[i])
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.textSecondary)
                            .frame(maxWidth: .infinity)
                    }
                }

                // Calendar grid
                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(daysInMonth(), id: \.self) { date in
                        let minutes = data[date] ?? 0
                        RoundedRectangle(cornerRadius: 4)
                            .fill(colorForMinutes(minutes))
                            .frame(height: 32)
                            .overlay {
                                Text("\(Calendar.current.component(.day, from: date))")
                                    .font(.system(size: 10))
                                    .foregroundStyle(minutes > 0 ? .white : AppColors.textSecondary)
                            }
                            .accessibilityLabel("\(date.formatted(.dateTime.month(.abbreviated).day())): \(minutes > 0 ? "\(minutes) minutes" : "no activity")")
                    }
                }

                // Legend
                HStack(spacing: AppSpacing.sm) {
                    Text("Less")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textSecondary)
                    ForEach([0, 10, 20, 30], id: \.self) { mins in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(colorForMinutes(mins))
                            .frame(width: 16, height: 16)
                    }
                    Text("More")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textSecondary)
                }
            }
        }
    }

    private var monthYearString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: Date())
    }

    private func daysInMonth() -> [Date] {
        let calendar = Calendar.current
        let now = Date()
        guard let range = calendar.range(of: .day, in: .month, for: now),
              let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) else {
            return []
        }

        // Pad start to align with weekday
        let firstWeekday = calendar.component(.weekday, from: monthStart)
        let mondayOffset = (firstWeekday + 5) % 7 // Convert to Monday-based

        var dates: [Date] = []
        for i in 0..<mondayOffset {
            if let padDate = calendar.date(byAdding: .day, value: -(mondayOffset - i), to: monthStart) {
                dates.append(padDate)
            }
        }

        for day in range {
            if let date = calendar.date(byAdding: .day, value: day - 1, to: monthStart) {
                dates.append(date)
            }
        }

        return dates
    }

    private func colorForMinutes(_ minutes: Int) -> Color {
        switch minutes {
        case 0: return AppColors.divider.opacity(0.3)
        case 1...10: return AppColors.success.opacity(0.3)
        case 11...20: return AppColors.success.opacity(0.6)
        default: return AppColors.success
        }
    }
}
