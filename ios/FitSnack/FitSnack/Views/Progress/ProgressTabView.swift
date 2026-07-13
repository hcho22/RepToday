import Charts
import SwiftUI

/// The Progress tab (US-M01) - the reflection surface where the user feels their consistency
/// building. It renders the real Consistency Score with its earned `longestChain`, the score
/// trajectory over time (Swift Charts), and a calendar marking every day a session was completed.
///
/// All copy is identity-framed and never loss-framed: there is no streak to break, no guilt for a
/// missed day. Every token comes from `Theme`; there is no XP, no levels, and no badges. Deeper,
/// premium-gated analytics (pillar balance, chain position, bests) land in US-M02.
///
/// Named `ProgressTabView` rather than `ProgressView` to avoid colliding with SwiftUI's own
/// `ProgressView` (the spinner), which the app uses elsewhere.
struct ProgressTabView: View {
    @State private var viewModel: ProgressViewModel

    init(services: ServiceContainer) {
        _viewModel = State(
            initialValue: ProgressViewModel(
                userService: services.userService,
                workoutLogService: services.workoutLogService,
                consistencyService: services.consistencyService
            )
        )
    }

    /// Test/preview seam so a fixed clock and pre-seeded view model can be injected.
    init(viewModel: ProgressViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        ZStack {
            Theme.Colors.background.ignoresSafeArea()

            if viewModel.isLoading && !viewModel.hasHistory {
                SwiftUI.ProgressView().tint(Theme.Colors.accent)
            } else {
                content
            }
        }
        .task { await viewModel.load() }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                header

                if viewModel.hasHistory {
                    if let consistency = viewModel.consistency {
                        ConsistencyHeadlineCard(consistency: consistency)
                    }
                    ScoreTrendCard(trend: viewModel.trend)
                    SessionCalendarCard(
                        completedDays: viewModel.completedDays,
                        now: Date()
                    )
                } else {
                    emptyState
                }
            }
            .padding(Theme.Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text("Your progress")
                .font(Theme.Typography.largeTitle)
                .foregroundStyle(Theme.Colors.textPrimary)
            Text("Every show-up is proof of who you're becoming.")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Image(systemName: "figure.walk.motion")
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(Theme.Colors.accent)
            Text("Your history starts with your first session.")
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.textPrimary)
            Text("Show up once and this space fills with proof - a calendar, a rising score, and the longest run you've ever put together.")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Spacing.cardCornerRadius))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Consistency headline

/// The identity-framed score card - the big number, "you're someone who moves," and the earned
/// `longestChain` surfaced as pride (never a threat).
private struct ConsistencyHeadlineCard: View {
    let consistency: Consistency

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(alignment: .center, spacing: Theme.Spacing.md) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text("You're someone who moves.")
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text(pride)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }

                Spacer(minLength: Theme.Spacing.md)

                VStack(spacing: 0) {
                    Text("\(Int(consistency.score.rounded()))")
                        .font(Theme.Typography.largeTitle)
                        .foregroundStyle(Theme.Colors.accent)
                    Text("consistency")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }

            HStack(spacing: Theme.Spacing.lg) {
                stat(value: "\(consistency.totalWorkoutsCompleted)", label: "sessions")
                stat(value: "\(consistency.totalMinutesExercised)", label: "minutes moved")
            }
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Spacing.cardCornerRadius))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private func stat(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value)
                .font(Theme.Typography.title)
                .foregroundStyle(Theme.Colors.textPrimary)
            Text(label)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
    }

    /// The earned point of pride - the longest on-goal run ever achieved - or an encouraging,
    /// never-loss-framed line for a user without a run yet.
    private var pride: String {
        guard consistency.longestChain > 0 else {
            return "Every time you show up counts - even five minutes."
        }
        let unit = consistency.longestChain == 1 ? "week" : "weeks"
        return "Best run: \(consistency.longestChain) \(unit) on goal."
    }

    private var accessibilityText: String {
        "You're someone who moves. Consistency \(Int(consistency.score.rounded())). \(pride) \(consistency.totalWorkoutsCompleted) sessions, \(consistency.totalMinutesExercised) minutes moved."
    }
}

// MARK: - Score trend

/// The Consistency Score over time, rendered with Swift Charts (US-M01). With only a single week of
/// history there is no line to draw yet, so an encouraging note stands in its place.
private struct ScoreTrendCard: View {
    let trend: [ConsistencyTrendPoint]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Consistency over time")
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.textPrimary)

            if trend.count >= 2 {
                chart
            } else {
                Text("Your trend line grows as the weeks add up. Keep showing up and it'll take shape.")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Spacing.cardCornerRadius))
    }

    private var chart: some View {
        Chart(trend) { point in
            AreaMark(
                x: .value("Week", point.weekStart),
                y: .value("Consistency", point.score)
            )
            .foregroundStyle(
                LinearGradient(
                    colors: [Theme.Colors.accent.opacity(0.25), Theme.Colors.accent.opacity(0.02)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .interpolationMethod(.monotone)

            LineMark(
                x: .value("Week", point.weekStart),
                y: .value("Consistency", point.score)
            )
            .foregroundStyle(Theme.Colors.accent)
            .interpolationMethod(.monotone)
            .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))

            PointMark(
                x: .value("Week", point.weekStart),
                y: .value("Consistency", point.score)
            )
            .foregroundStyle(Theme.Colors.accent)
            .symbolSize(60)
        }
        .chartYScale(domain: 0...100)
        .chartYAxis {
            AxisMarks(values: [0, 50, 100]) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let score = value.as(Int.self) {
                        Text("\(score)")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .weekOfYear)) { value in
                AxisValueLabel(format: .dateTime.month(.abbreviated).day(), centered: false)
            }
        }
        .frame(height: 180)
        .accessibilityLabel("Consistency score over time")
        .accessibilityValue(trendAccessibilityValue)
    }

    private var trendAccessibilityValue: String {
        guard let first = trend.first, let last = trend.last else { return "" }
        return "From \(Int(first.score.rounded())) to \(Int(last.score.rounded())) over \(trend.count) weeks."
    }
}

// MARK: - Session calendar

/// A month calendar marking every day a session was completed (US-M01). The user can page back and
/// forth through their history; days with a session carry a filled accent dot.
private struct SessionCalendarCard: View {
    let completedDays: Set<Date>
    let now: Date

    @State private var monthAnchor: Date

    private let calendar: Calendar
    private let dayFormatter: DateFormatter
    private let monthTitleFormatter: DateFormatter

    init(completedDays: Set<Date>, now: Date, calendar: Calendar = .current) {
        self.completedDays = completedDays
        self.now = now
        self.calendar = calendar
        _monthAnchor = State(initialValue: calendar.startOfMonth(for: now))

        let day = DateFormatter()
        day.calendar = calendar
        day.dateFormat = "d"
        self.dayFormatter = day

        let month = DateFormatter()
        month.calendar = calendar
        month.dateFormat = "MMMM yyyy"
        self.monthTitleFormatter = month
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            monthHeader
            weekdayHeader
            grid
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Spacing.cardCornerRadius))
    }

    private var monthHeader: some View {
        HStack {
            Text(monthTitleFormatter.string(from: monthAnchor))
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.textPrimary)
            Spacer()
            Button { step(-1) } label: {
                Image(systemName: "chevron.left")
                    .frame(minWidth: Theme.Spacing.minTouchTarget, minHeight: Theme.Spacing.minTouchTarget)
            }
            .accessibilityLabel("Previous month")

            Button { step(1) } label: {
                Image(systemName: "chevron.right")
                    .frame(minWidth: Theme.Spacing.minTouchTarget, minHeight: Theme.Spacing.minTouchTarget)
            }
            .disabled(isCurrentMonth)
            .accessibilityLabel("Next month")
        }
        .foregroundStyle(Theme.Colors.accent)
    }

    private var weekdayHeader: some View {
        HStack(spacing: 0) {
            ForEach(orderedWeekdaySymbols, id: \.self) { symbol in
                Text(symbol)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var grid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Theme.Spacing.xs), count: 7), spacing: Theme.Spacing.sm) {
            ForEach(Array(monthCells.enumerated()), id: \.offset) { _, cell in
                if let date = cell {
                    dayCell(date)
                } else {
                    Color.clear.frame(height: 36)
                }
            }
        }
    }

    private func dayCell(_ date: Date) -> some View {
        let didMove = completedDays.contains(calendar.startOfDay(for: date))
        let isToday = calendar.isDate(date, inSameDayAs: now)
        return VStack(spacing: 2) {
            Text(dayFormatter.string(from: date))
                .font(Theme.Typography.caption)
                .foregroundStyle(isToday ? Theme.Colors.accent : Theme.Colors.textPrimary)
            Circle()
                .fill(didMove ? Theme.Colors.accent : Color.clear)
                .frame(width: 6, height: 6)
        }
        .frame(maxWidth: .infinity, minHeight: 36)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(for: date, didMove: didMove, isToday: isToday))
    }

    // MARK: - Layout math

    private var isCurrentMonth: Bool {
        calendar.isDate(monthAnchor, equalTo: calendar.startOfMonth(for: now), toGranularity: .month)
    }

    private func step(_ months: Int) {
        guard let next = calendar.date(byAdding: .month, value: months, to: monthAnchor) else { return }
        // Never page into the future beyond the current month.
        if months > 0 && next > calendar.startOfMonth(for: now) { return }
        monthAnchor = next
    }

    /// The weekday symbols in the calendar's own first-weekday order (e.g. Sun-first in the US).
    private var orderedWeekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let shift = calendar.firstWeekday - 1
        return Array(symbols[shift...] + symbols[..<shift])
    }

    /// The cells for the displayed month: leading `nil`s to align the first day under its weekday,
    /// then one date per day of the month.
    private var monthCells: [Date?] {
        guard let range = calendar.range(of: .day, in: .month, for: monthAnchor) else { return [] }
        let firstOfMonth = calendar.startOfMonth(for: monthAnchor)
        let leadingBlanks = (calendar.component(.weekday, from: firstOfMonth) - calendar.firstWeekday + 7) % 7
        var cells: [Date?] = Array(repeating: nil, count: leadingBlanks)
        for day in range {
            if let date = calendar.date(byAdding: .day, value: day - 1, to: firstOfMonth) {
                cells.append(date)
            }
        }
        return cells
    }

    private func accessibilityLabel(for date: Date, didMove: Bool, isToday: Bool) -> String {
        let long = DateFormatter()
        long.calendar = calendar
        long.dateStyle = .medium
        var label = long.string(from: date)
        if isToday { label += ", today" }
        label += didMove ? ", session completed" : ", no session"
        return label
    }
}

private extension Calendar {
    /// The first instant of the month containing `date`.
    func startOfMonth(for date: Date) -> Date {
        dateInterval(of: .month, for: date)?.start ?? startOfDay(for: date)
    }
}

#Preview("With history") {
    ProgressTabView(viewModel: PreviewProgressViewModel.populated())
}

#Preview("Empty") {
    ProgressTabView(viewModel: PreviewProgressViewModel.empty())
}

/// Preview-only factory so the canvas renders without a running service stack.
private enum PreviewProgressViewModel {
    static func populated() -> ProgressViewModel {
        let vm = ProgressViewModel(
            userService: MockUserService(user: MockPersistence.sampleUser),
            workoutLogService: MockWorkoutLogService(logs: sampleLogs()),
            consistencyService: ConsistencyScoreService()
        )
        return vm
    }

    static func empty() -> ProgressViewModel {
        ProgressViewModel(
            userService: MockUserService(user: MockPersistence.sampleUser),
            workoutLogService: MockWorkoutLogService(logs: [])
        )
    }

    private static func sampleLogs() -> [WorkoutLog] {
        let calendar = Calendar.current
        let today = Date()
        return (0..<18).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset * 2, to: today) else { return nil }
            return WorkoutLog(
                id: UUID(), workoutId: UUID(), completedAt: date,
                requestedMinutes: 15, durationMinutes: 12, wasReturn: false,
                shape: .singleFocus, focusPillar: .strength, perceivedDifficulty: .justRight,
                exercises: []
            )
        }
    }
}
