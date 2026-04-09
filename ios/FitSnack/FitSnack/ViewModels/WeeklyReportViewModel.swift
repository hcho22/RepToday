import SwiftUI

@Observable
final class WeeklyReportViewModel {
    var reports: [WeekReport] = []
    var isLoading = false
    var isPremium = false

    struct WeekReport: Identifiable {
        let id = UUID()
        let weekStart: Date
        let weekEnd: Date
        let workoutCount: Int
        let totalMinutes: Int
        var narrative: String
        var isGenerating: Bool

        var dateRangeFormatted: String {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            let start = formatter.string(from: weekStart)
            let end = formatter.string(from: weekEnd)
            return "\(start) – \(end)"
        }

        var isEmpty: Bool { workoutCount == 0 }
    }

    func loadReports(services: ServiceContainer?) async {
        guard let services else { return }
        isLoading = true
        isPremium = services.subscription.isPremium

        do {
            let history = try await services.workout.getHistory()
            let profile = try await services.user.getProfile() ?? .empty
            let stats = try await services.user.getGamificationStats()
            let calendar = Calendar.current
            let now = Date()

            // Build 4 weeks of report data
            var weekReports: [WeekReport] = []
            for weekOffset in 0..<4 {
                let weekEnd = calendar.date(byAdding: .weekOfYear, value: -weekOffset, to: now)!
                let weekStart = calendar.date(byAdding: .day, value: -6, to: weekEnd)!
                let startOfWeekStart = calendar.startOfDay(for: weekStart)
                let endOfWeekEnd = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: weekEnd))!

                let weekWorkouts = history.filter { workout in
                    let date = workout.completedAt ?? workout.createdAt
                    return date >= startOfWeekStart && date < endOfWeekEnd
                }

                let totalMinutes = weekWorkouts.reduce(0) {
                    $0 + ($1.actualDurationMinutes ?? $1.requestedDurationMinutes)
                }

                weekReports.append(WeekReport(
                    weekStart: startOfWeekStart,
                    weekEnd: calendar.startOfDay(for: weekEnd),
                    workoutCount: weekWorkouts.count,
                    totalMinutes: totalMinutes,
                    narrative: "",
                    isGenerating: !weekWorkouts.isEmpty
                ))
            }

            reports = weekReports
            isLoading = false

            // Generate narratives for non-empty weeks
            for i in reports.indices where !reports[i].isEmpty {
                let weekStart = reports[i].weekStart
                let weekEnd = calendar.date(byAdding: .day, value: 1, to: reports[i].weekEnd)!
                let weekWorkouts = history.filter { workout in
                    let date = workout.completedAt ?? workout.createdAt
                    return date >= weekStart && date < weekEnd
                }

                do {
                    let narrative = try await services.ai.generateWeeklyReport(
                        workouts: weekWorkouts,
                        userProfile: profile,
                        stats: stats
                    )
                    if i < reports.count {
                        reports[i].narrative = narrative
                        reports[i].isGenerating = false
                    }
                } catch {
                    if i < reports.count {
                        reports[i].narrative = "Unable to generate report."
                        reports[i].isGenerating = false
                    }
                }
            }
        } catch {
            isLoading = false
        }
    }
}
