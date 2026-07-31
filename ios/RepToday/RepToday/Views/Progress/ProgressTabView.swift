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
    @State private var showPaywall = false

    /// The subscription service the paywall (US-N04) purchases through. Held separately from the view
    /// model so the upsell can present the paywall sheet; the mock keeps previews rendering.
    private let subscriptionService: any SubscriptionServiceProtocol

    init(services: ServiceContainer) {
        _viewModel = State(
            initialValue: ProgressViewModel(
                userService: services.userService,
                workoutLogService: services.workoutLogService,
                exerciseService: services.exerciseService,
                subscriptionService: services.subscriptionService,
                consistencyService: services.consistencyService
            )
        )
        self.subscriptionService = services.subscriptionService
    }

    /// Test/preview seam so a fixed clock and pre-seeded view model can be injected.
    init(
        viewModel: ProgressViewModel,
        subscriptionService: any SubscriptionServiceProtocol = MockSubscriptionService()
    ) {
        _viewModel = State(initialValue: viewModel)
        self.subscriptionService = subscriptionService
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
        .sheet(isPresented: $showPaywall) {
            // On a successful unlock the paywall dismisses itself and calls this, so the gated depth
            // layer swaps in without leaving the tab. The reload is best-effort; the core loop and the
            // free surfaces are never affected.
            PaywallView(subscriptionService: subscriptionService) {
                Task { await viewModel.load() }
            }
        }
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

                    if let analytics = viewModel.analytics {
                        // The free legibility layer (US-M02): everyone sees where their training is
                        // balanced, where they stand in each foundational pattern, and their bests.
                        PillarBalanceCard(shares: analytics.pillarBalance)
                        ChainPositionCard(positions: analytics.chainPositions)
                        PersonalBestsCard(bests: analytics.personalBests)

                        // The deep layer is entitlement-gated (US-N04): premium users see it, free
                        // users see a clear, non-nagging upsell in its place. The core loop and the
                        // basic history above are never gated.
                        if viewModel.isPremium {
                            DeepAnalyticsSection(deep: analytics.deep)
                        } else {
                            PremiumUpsellCard(action: { showPaywall = true })
                        }
                    }
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
            // Keyed by position rather than by the symbol itself: a week's initials repeat in most
            // locales (en_US is S M T W T F S), so `id: \.self` hands SwiftUI the same id for Sunday
            // and Saturday, and again for Tuesday and Thursday - which it reports at runtime as
            // undefined results. The month grid below already keys its cells by offset.
            ForEach(Array(orderedWeekdaySymbols.enumerated()), id: \.offset) { _, symbol in
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

// MARK: - Pillar balance (US-M02, free)

/// How the user's training is balanced across the three pillars - a labeled bar per pillar. Shown to
/// everyone; it is basic legibility, never gated.
private struct PillarBalanceCard: View {
    let shares: [PillarShare]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("How you're balanced")
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.textPrimary)
            Text("The mix across strength, mobility, and primal movement.")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)

            VStack(spacing: Theme.Spacing.sm) {
                ForEach(shares) { share in
                    ProgressAnalyticsBar(
                        label: PillarLabels.name(for: share.pillar),
                        fraction: share.fraction,
                        trailing: "\(Int((share.fraction * 100).rounded()))%"
                    )
                }
            }
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Spacing.cardCornerRadius))
    }
}

// MARK: - Chain position (US-M02, free)

/// Where the user stands in each foundational pattern's active progression chain. Basic legibility,
/// shown to everyone.
private struct ChainPositionCard: View {
    let positions: [ChainPositionSummary]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Where you stand")
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.textPrimary)
            Text("Your current movement in each foundation.")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)

            VStack(spacing: Theme.Spacing.sm) {
                ForEach(positions) { position in
                    row(position)
                }
            }
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Spacing.cardCornerRadius))
    }

    private func row(_ position: ChainPositionSummary) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.md) {
            Text(PatternLabels.name(for: position.pattern))
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textPrimary)
                .frame(width: 88, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                if let exercise = position.currentExercise {
                    Text(exercise.displayName)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text(subtitle(for: position))
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                } else {
                    Text("Not started yet")
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel(for: position))
    }

    private func subtitle(for position: ChainPositionSummary) -> String {
        var text = "Tier \(position.tier) of \(position.chainLength)"
        if position.hasNextTier { text += " - next tier in reach" }
        return text
    }

    private func accessibilityLabel(for position: ChainPositionSummary) -> String {
        guard let exercise = position.currentExercise else {
            return "\(PatternLabels.name(for: position.pattern)), not started yet."
        }
        return "\(PatternLabels.name(for: position.pattern)), \(exercise.displayName), \(subtitle(for: position))."
    }
}

// MARK: - Personal bests (US-M02, free)

/// The user's headline bests from real history - stat tiles, identity-framed. Basic legibility,
/// shown to everyone.
private struct PersonalBestsCard: View {
    let bests: PersonalBests

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Your bests")
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.textPrimary)

            LazyVGrid(columns: columns, spacing: Theme.Spacing.md) {
                tile(value: "\(bests.totalSessions)", label: "sessions logged")
                tile(value: "\(bests.longestSessionMinutes) min", label: "longest session")
                tile(value: "\(bests.mostSessionsInAWeek)", label: "best week")
                tile(value: "\(bests.totalMinutesMoved) min", label: "total moved")
                if let reps = bests.bestReps {
                    tile(value: "\(reps.value) reps", label: "best set - \(reps.displayName)")
                }
                if let hold = bests.bestHold {
                    tile(value: "\(hold.value)s", label: "longest hold - \(hold.displayName)")
                }
            }
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Spacing.cardCornerRadius))
    }

    private func tile(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(Theme.Typography.title)
                .foregroundStyle(Theme.Colors.accent)
            Text(label)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(value), \(label)")
    }
}

// MARK: - Deep analytics (US-M02, premium)

/// The premium-only deep layer: finer pattern balance, weekly training volume, and how sessions have
/// felt. Rendered only when the user's entitlement unlocks it (US-N04).
private struct DeepAnalyticsSection: View {
    let deep: DeepAnalytics

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: "sparkles")
                    .foregroundStyle(Theme.Colors.accent)
                Text("Deeper analytics")
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)
            }

            PatternBalanceCard(shares: deep.patternBalance)
            WeeklyVolumeCard(points: deep.weeklyVolume)
            DifficultyMixCard(mix: deep.difficultyMix)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Finer than pillar balance - the share across every movement pattern the user has trained.
private struct PatternBalanceCard: View {
    let shares: [PatternShare]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Movement patterns")
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.textPrimary)

            VStack(spacing: Theme.Spacing.sm) {
                ForEach(shares) { share in
                    ProgressAnalyticsBar(
                        label: PatternLabels.name(for: share.pattern),
                        fraction: share.fraction,
                        trailing: "\(share.exerciseCount)"
                    )
                }
            }
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Spacing.cardCornerRadius))
    }
}

/// Completed sets per week over the rolling window, as a bar chart (Swift Charts).
private struct WeeklyVolumeCard: View {
    let points: [WeeklyVolumePoint]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Weekly volume")
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.textPrimary)
            Text("Sets completed each week.")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)

            Chart(points) { point in
                BarMark(
                    x: .value("Week", point.weekStart, unit: .weekOfYear),
                    y: .value("Sets", point.setsCompleted)
                )
                .foregroundStyle(Theme.Colors.accent)
                .cornerRadius(4)
            }
            .chartYAxis {
                AxisMarks(position: .leading)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .weekOfYear)) { _ in
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day(), centered: true)
                }
            }
            .frame(height: 160)
            .accessibilityLabel("Weekly training volume")
            .accessibilityValue(accessibilityValue)
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Spacing.cardCornerRadius))
    }

    private var accessibilityValue: String {
        let total = points.reduce(0) { $0 + $1.setsCompleted }
        return "\(total) sets over \(points.count) weeks."
    }
}

/// How sessions have felt - the too-easy / just-right / too-hard split behind Adaptive Overload.
private struct DifficultyMixCard: View {
    let mix: DifficultyMix

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("How it's felt")
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.textPrimary)

            if mix.ratedCount == 0 {
                Text("Rate a few sessions and your calibration shows up here.")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            } else {
                segmentedBar
                HStack(spacing: Theme.Spacing.md) {
                    legend(label: "Too easy", count: mix.tooEasy, opacity: 0.35)
                    legend(label: "Just right", count: mix.justRight, opacity: 1.0)
                    legend(label: "Too hard", count: mix.tooHard, opacity: 0.6)
                }
                Text(calibrationNote)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Spacing.cardCornerRadius))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("How it's felt. \(mix.tooEasy) too easy, \(mix.justRight) just right, \(mix.tooHard) too hard. \(calibrationNote)")
    }

    private var segmentedBar: some View {
        GeometryReader { geo in
            HStack(spacing: 2) {
                segment(width: geo.size.width, count: mix.tooEasy, opacity: 0.35)
                segment(width: geo.size.width, count: mix.justRight, opacity: 1.0)
                segment(width: geo.size.width, count: mix.tooHard, opacity: 0.6)
            }
        }
        .frame(height: 12)
    }

    private func segment(width: CGFloat, count: Int, opacity: Double) -> some View {
        let fraction = mix.ratedCount > 0 ? CGFloat(count) / CGFloat(mix.ratedCount) : 0
        return Capsule()
            .fill(Theme.Colors.accent.opacity(opacity))
            .frame(width: max(0, width * fraction))
    }

    private func legend(label: String, count: Int, opacity: Double) -> some View {
        HStack(spacing: Theme.Spacing.xs) {
            Circle()
                .fill(Theme.Colors.accent.opacity(opacity))
                .frame(width: 8, height: 8)
            Text("\(label) \(count)")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
    }

    /// A gentle, non-judgmental read of the calibration - never loss-framed.
    private var calibrationNote: String {
        if mix.justRight >= mix.tooEasy && mix.justRight >= mix.tooHard {
            return "Mostly dialed in - your sessions are landing right."
        }
        if mix.tooHard > mix.tooEasy {
            return "Running a little hard lately - the engine's easing you back."
        }
        return "Plenty in the tank - the engine's nudging you up."
    }
}

// MARK: - Premium upsell (US-M02, free)

/// The clear, non-nagging upsell shown in place of the deep layer for free users (US-M02 / US-N04).
/// It states what premium unlocks and reassures that the core loop stays free - a single quiet card,
/// never a modal or a repeated prompt.
private struct PremiumUpsellCard: View {
    /// Opens the paywall (US-N04). The card is the only entry point; nothing here gates the core loop.
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                HStack(spacing: Theme.Spacing.xs) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(Theme.Colors.accent)
                    Text("Go deeper with Premium")
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Spacer(minLength: Theme.Spacing.sm)
                    Image(systemName: "chevron.right")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.accent)
                }
                Text("Unlock pattern-by-pattern balance, your weekly training volume, and how your sessions have felt over time.")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Your workouts are always free - Premium just adds the deeper view.")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(Theme.Spacing.md)
            .frame(maxWidth: .infinity, minHeight: Theme.Spacing.minTouchTarget, alignment: .leading)
            .background(Theme.Colors.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: Theme.Spacing.cardCornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Spacing.cardCornerRadius)
                    .strokeBorder(Theme.Colors.accent.opacity(0.25), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Go deeper with Premium. Unlock pattern-by-pattern balance, weekly training volume, and how your sessions have felt. Your workouts are always free.")
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Shared bar + labels

/// A labeled horizontal share bar used by the pillar and pattern balance cards.
private struct ProgressAnalyticsBar: View {
    let label: String
    let fraction: Double
    let trailing: String

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            Text(label)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textPrimary)
                .frame(width: 96, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Theme.Colors.accent.opacity(0.12))
                    Capsule()
                        .fill(Theme.Colors.accent)
                        .frame(width: max(0, geo.size.width * CGFloat(min(1, max(0, fraction)))))
                }
            }
            .frame(height: 10)

            Text(trailing)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
                .frame(width: 40, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label), \(trailing)")
    }
}

/// Presentation-only pillar labels for the Progress tab, matching `SessionSummary`'s wording.
private enum PillarLabels {
    static func name(for pillar: Pillar) -> String {
        switch pillar {
        case .strength: return "Strength"
        case .mobility: return "Mobility"
        case .primal: return "Primal"
        }
    }
}

/// Presentation-only movement-pattern labels for the Progress tab.
private enum PatternLabels {
    static func name(for pattern: MovementPattern) -> String {
        switch pattern {
        case .push: return "Push"
        case .squat: return "Squat"
        case .hinge: return "Hinge"
        case .core: return "Core"
        case .pull: return "Pull"
        case .mobility: return "Mobility"
        case .locomotion: return "Locomotion"
        }
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

#Preview("Premium") {
    ProgressTabView(viewModel: PreviewProgressViewModel.populated(premium: true))
}

/// Preview-only factory so the canvas renders without a running service stack.
private enum PreviewProgressViewModel {
    static func populated(premium: Bool = false) -> ProgressViewModel {
        let subscription = Subscription(
            tier: premium ? .premium : .free,
            provider: .apple,
            expiresAt: nil,
            trialEndsAt: nil
        )
        return ProgressViewModel(
            userService: MockUserService(user: MockPersistence.sampleUser),
            workoutLogService: MockWorkoutLogService(logs: sampleLogs()),
            exerciseService: try! MockExerciseService(),
            subscriptionService: MockSubscriptionService(subscription: subscription),
            consistencyService: ConsistencyScoreService()
        )
    }

    static func empty() -> ProgressViewModel {
        ProgressViewModel(
            userService: MockUserService(user: MockPersistence.sampleUser),
            workoutLogService: MockWorkoutLogService(logs: []),
            exerciseService: try! MockExerciseService(),
            subscriptionService: MockSubscriptionService()
        )
    }

    private static func sampleLogs() -> [WorkoutLog] {
        let calendar = Calendar.current
        let today = Date()
        let pillars: [(Pillar, MovementPattern, String)] = [
            (.strength, .push, "push_knee"),
            (.mobility, .mobility, "mobility_cat_cow"),
            (.primal, .locomotion, "primal_bear_crawl"),
        ]
        return (0..<18).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset * 2, to: today) else { return nil }
            let (pillar, pattern, exerciseId) = pillars[offset % pillars.count]
            let logged = LoggedExercise(
                id: UUID(), exerciseId: exerciseId, pillar: pillar, movementPattern: pattern,
                completedSets: [CompletedSet(reps: 12, durationSeconds: nil), CompletedSet(reps: 10, durationSeconds: nil)],
                skipped: false
            )
            return WorkoutLog(
                id: UUID(), workoutId: UUID(), completedAt: date,
                requestedMinutes: 15, durationMinutes: 12, wasReturn: false,
                shape: .singleFocus, focusPillar: pillar, perceivedDifficulty: .justRight,
                exercises: [logged]
            )
        }
    }
}
