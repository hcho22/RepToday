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

    /// The telemetry sink the presented paywall emits `paywall_shown`/`trial_started`/`subscribe`
    /// through (US-T12). Held alongside `subscriptionService` and threaded into `PaywallView`; the
    /// preview/test seam leaves it `nil` so those surfaces stay off the wire.
    private let analyticsService: (any AnalyticsServiceProtocol)?

    init(services: ServiceContainer) {
        _viewModel = State(
            initialValue: ProgressViewModel(
                userService: services.userService,
                workoutLogService: services.workoutLogService,
                exerciseService: services.exerciseService,
                subscriptionService: services.subscriptionService,
                consistencyService: services.consistencyService,
                phaseService: services.phaseService
            )
        )
        self.subscriptionService = services.subscriptionService
        self.analyticsService = services.analyticsService
    }

    /// Test/preview seam so a fixed clock and pre-seeded view model can be injected.
    init(
        viewModel: ProgressViewModel,
        subscriptionService: any SubscriptionServiceProtocol = MockSubscriptionService(),
        analyticsService: (any AnalyticsServiceProtocol)? = nil
    ) {
        _viewModel = State(initialValue: viewModel)
        self.subscriptionService = subscriptionService
        self.analyticsService = analyticsService
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
            PaywallView(
                subscriptionService: subscriptionService,
                analyticsService: analyticsService,
                entryPoint: .progressUpsell
            ) {
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

                    // The free "visible climb" toward the Strength Phase (US-SP04). Shown only while
                    // the user is still earning it (`.discipline`); once earned, US-SP06's graduation
                    // moment and the strength surfaces take over. Never gated.
                    if viewModel.phase == .discipline,
                       let progress = viewModel.phaseProgress,
                       !progress.hasEarnedStrength {
                        PhaseProgressCard(progress: progress)
                    }

                    ScoreTrendCard(trend: viewModel.trend)
                    SessionCalendarCard(
                        completedDays: viewModel.completedDays,
                        now: viewModel.displayNow,
                        calendar: viewModel.displayCalendar
                    )

                    if let analytics = viewModel.analytics {
                        // The free legibility layer (US-M02): everyone sees where their training is
                        // balanced, where they stand in each foundational pattern, and their bests.
                        PillarBalanceCard(shares: analytics.pillarBalance)
                        ChainPositionCard(positions: analytics.chainPositions)
                        ProgressionMapCard(map: analytics.progressionMap, phase: viewModel.phase)
                        PersonalBestsCard(bests: analytics.personalBests)

                        // The deep layer is entitlement-gated (US-N04): premium users see it, free
                        // users see a clear, non-nagging upsell in its place. The core loop and the
                        // basic history above are never gated.
                        if viewModel.isPremium {
                            DeepAnalyticsSection(
                                deep: analytics.deep,
                                phaseProgress: viewModel.phaseProgress,
                                phase: viewModel.phase
                            )
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
    private let spokenDateFormatter: DateFormatter

    // No default calendar: the days this card normalizes have to be normalized in the *same* calendar
    // `completedDays` was built in, or every dot silently disappears and a full history draws as an
    // empty month. Making the caller name it keeps that invariant unforgeable rather than documented.
    init(completedDays: Set<Date>, now: Date, calendar: Calendar) {
        self.completedDays = completedDays
        self.now = now
        self.calendar = calendar
        _monthAnchor = State(initialValue: calendar.startOfMonth(for: now))

        // A `DateFormatter` keeps its own time zone rather than taking the calendar's, so setting
        // only `calendar` leaves it resolving instants in the system zone: the cells' own dates are
        // built in `calendar`, so a calendar in any other zone would print - and speak - a day
        // number one off from the day the cell actually marks.
        let day = DateFormatter()
        day.calendar = calendar
        day.timeZone = calendar.timeZone
        day.dateFormat = "d"
        self.dayFormatter = day

        let month = DateFormatter()
        month.calendar = calendar
        month.timeZone = calendar.timeZone
        month.dateFormat = "MMMM yyyy"
        self.monthTitleFormatter = month

        // Built once here rather than per cell: it is read for every day of the displayed month while
        // `body` is being evaluated, and `body` re-runs on any observable change to the tab.
        // `locale` is deliberately left at the user's own, since this is a date read aloud to them.
        //
        // The weekday is named ("Wednesday, Jul 8, 2026") because the column header above carries it
        // for a sighted user but is hidden from VoiceOver: without it here, a listener swiping the grid
        // has no way to hear that their sessions cluster on weekends. Built from a *template* rather
        // than a fixed format string so the field order and separators stay the user's locale's own.
        let spoken = DateFormatter()
        spoken.calendar = calendar
        spoken.timeZone = calendar.timeZone
        spoken.setLocalizedDateFormatFromTemplate("EEEEdMMMy")
        self.spokenDateFormatter = spoken
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
        // Visual scaffolding for the grid below, whose cells each speak their own full date - weekday
        // included - and state ("Wednesday, Jul 8, 2026, today, session completed"). Read aloud, the
        // bare initials are seven disconnected letters that say nothing the day cells do not.
        .accessibilityHidden(true)
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
        var label = spokenDateFormatter.string(from: date)
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

// MARK: - Progression map (US-SP05, free)

/// The progression map (US-SP05): a visual per-pattern ladder the user is climbing, from the entry
/// tier through the Strength-Phase skill they will earn. It marks the current frontier ("you're
/// here") and shows the still-locked Strength-Phase rungs with an "earn the Strength Phase to unlock"
/// affordance - *previewable but never selectable*.
///
/// This is the visible strength journey, and it deliberately preserves the thesis: **there is no
/// start or select control on any rung.** Every value is a pure readout from `ProgressionMap`, whose
/// current-position marking reuses the same chain-position logic as the card above it, and whose
/// locked marking is the engine's own phase gate - so the map can never disagree with what the engine
/// would do. Copy is identity-framed and there is no XP, level, or badge; a rung is just a movement
/// with a state. Shown to everyone (free), same tier as the visible climb (US-SP04).
private struct ProgressionMapCard: View {
    let map: ProgressionMap
    /// The user's earned phase, so the footer can frame the locked summit honestly ("earn the
    /// Strength Phase") while a strength user simply sees their summit unlocked.
    let phase: Phase

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text("The ladder you're climbing")
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text("Each foundation's path - from where you started to the Strength-Phase skill at the top. This is the map, not a menu: the day's work is still chosen for you.")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                ForEach(map.ladders) { ladder in
                    LadderView(ladder: ladder, phase: phase)
                }
            }
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Spacing.cardCornerRadius))
    }
}

/// One pattern's ladder: the pattern name, then a rung per movement (entry first, summit last).
private struct LadderView: View {
    let ladder: PatternLadder
    let phase: Phase

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
                Text(PatternLabels.name(for: ladder.pattern))
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Spacer(minLength: 0)
                Text(headerNote)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            // The header names the pattern once for VoiceOver; each rung below reads its own state.
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(PatternLabels.name(for: ladder.pattern)) ladder. \(headerNote).")

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(ladder.rungs.enumerated()), id: \.element.id) { index, rung in
                    LadderRungRow(
                        rung: rung,
                        isFirst: index == 0,
                        isLast: index == ladder.rungs.count - 1
                    )
                }
            }
        }
    }

    private var headerNote: String {
        guard ladder.hasStarted, let current = ladder.currentRung else {
            return "Not started yet"
        }
        return "You're on \(current.displayName)"
    }
}

/// A single rung: a connector-and-marker rail on the left, the movement name and its state on the
/// right. No control - the whole row is a static accessibility element, not a button.
private struct LadderRungRow: View {
    let rung: LadderRung
    let isFirst: Bool
    let isLast: Bool

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            rail
            VStack(alignment: .leading, spacing: 2) {
                Text(rung.displayName)
                    .font(Theme.Typography.body)
                    .foregroundStyle(nameColor)
                    .fixedSize(horizontal: false, vertical: true)
                Text(stateNote)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(stateNoteColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // No `.accessibilityAddTraits(.isButton)` and no gesture: a rung is a readout, never a control.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    /// The left rail: the vertical connector line through the marker, so the rungs read as one
    /// climbing ladder rather than a flat list.
    private var rail: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(isFirst ? Color.clear : connectorColor)
                .frame(width: 2, height: 8)
            marker
            Rectangle()
                .fill(isLast ? Color.clear : connectorColor)
                .frame(width: 2)
                .frame(maxHeight: .infinity)
        }
        .frame(width: 22)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var marker: some View {
        switch rung.state {
        case .cleared:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Theme.Colors.accent)
        case .current:
            Image(systemName: "location.circle.fill")
                .foregroundStyle(Theme.Colors.accent)
        case .ahead:
            Image(systemName: rung.isLocked ? "lock.circle.fill" : "circle")
                .foregroundStyle(rung.isLocked ? Theme.Colors.textSecondary : Theme.Colors.textSecondary.opacity(0.6))
        }
    }

    private var connectorColor: Color {
        // Cleared/current rungs sit on the climbed part of the ladder (accent); ahead rungs are dim.
        switch rung.state {
        case .cleared, .current: return Theme.Colors.accent.opacity(0.5)
        case .ahead: return Theme.Colors.textSecondary.opacity(0.25)
        }
    }

    private var nameColor: Color {
        if rung.state == .current { return Theme.Colors.textPrimary }
        return rung.isLocked ? Theme.Colors.textSecondary : Theme.Colors.textPrimary
    }

    /// The one-line state note under the movement name - identity-framed, never loss-framed.
    private var stateNote: String {
        switch rung.state {
        case .cleared: return "Cleared"
        case .current: return "You're here"
        case .ahead:
            if rung.isLocked { return "Earn the Strength Phase to unlock" }
            return rung.isStrengthSkill ? "Strength skill - unlocked" : "Coming up"
        }
    }

    private var stateNoteColor: Color {
        if rung.state == .current { return Theme.Colors.accent }
        return Theme.Colors.textSecondary
    }

    /// Spoken as one element: name, then its state (including the locked affordance in words).
    private var accessibilityLabel: String {
        "\(rung.displayName), \(stateNote)."
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

/// The premium-only deep layer: the strength journey (US-AN01), finer pattern balance, weekly
/// training volume, and how sessions have felt. Rendered only when the user's entitlement unlocks it
/// (US-N04) - the gate lives at this render boundary, so every strength-journey view below is premium
/// by construction and a free user never reaches it.
private struct DeepAnalyticsSection: View {
    let deep: DeepAnalytics
    /// The phase-earning signals (US-SP04), reused here rather than recomputed so the strength journey
    /// can show how close the summit is; `nil` when the library read failed.
    let phaseProgress: PhaseProgress?
    /// The user's earned phase, so the phase-earning readout frames an earned summit as earned rather
    /// than as a climb still under way.
    let phase: Phase

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: "sparkles")
                    .foregroundStyle(Theme.Colors.accent)
                Text("Deeper analytics")
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)
            }

            StrengthJourneyCard(journey: deep.strengthJourney, phaseProgress: phaseProgress, phase: phase)
            PatternBalanceCard(shares: deep.patternBalance)
            WeeklyVolumeCard(points: deep.weeklyVolume)
            DifficultyMixCard(mix: deep.difficultyMix)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Strength journey (US-AN01, premium)

/// The strength journey (US-AN01): analytics anchored on the user's climb over time rather than this
/// week's numbers. For each foundational pattern the user has trained it shows the dated tier
/// advancement ("Knee Push-Up -> Standard Push-Up, over 6 weeks") read straight from real history,
/// then the current phase-earning progress (US-SP04's signals, reused). Premium-only: it renders only
/// inside `DeepAnalyticsSection`, which is gated at the render boundary.
///
/// Every value is a pure readout from `StrengthJourney`/`PhaseProgress`. No tier the user has not
/// actually performed appears, and a locked Strength tier is never shown as reached (the data layer
/// excludes it), so the surface can never over-claim. Copy is identity-framed; there is no XP, level,
/// or badge - just the honest, dated shape of a habit being built.
private struct StrengthJourneyCard: View {
    let journey: StrengthJourney
    let phaseProgress: PhaseProgress?
    let phase: Phase

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text("Your strength journey")
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text("Not just this week - how far you've climbed over time, one foundation at a time.")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }

            if journey.isEmpty {
                Text("Train a foundation and your climb starts here - each tier you reach, with the date you first did it.")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            } else {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    ForEach(journey.chains) { chain in
                        ChainJourneyView(chain: chain)
                    }
                }
            }

            if let phaseProgress {
                Divider().background(Theme.Colors.textSecondary.opacity(0.2))
                PhaseEarningSummary(progress: phaseProgress, phase: phase)
            }
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Spacing.cardCornerRadius))
    }
}

/// One pattern's dated climb: a headline advancement line (from -> to, over N weeks) when the user has
/// advanced a tier, then a per-tier timeline with the date each tier was first reached.
private struct ChainJourneyView: View {
    let chain: ChainJourney

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMMd")
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
                Text(PatternLabels.name(for: chain.pattern))
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Spacer(minLength: 0)
                Text(headline)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.accent)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(PatternLabels.name(for: chain.pattern)) journey. \(spokenHeadline)")

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(chain.milestones.enumerated()), id: \.element.id) { index, milestone in
                    MilestoneRow(
                        milestone: milestone,
                        dateText: dateFormatter.string(from: milestone.firstReachedAt),
                        isFirst: index == 0,
                        isCurrent: milestone.id == chain.currentMilestone?.id
                    )
                }
            }
        }
    }

    /// The seen advancement headline: "Knee Push-Up -> Standard Push-Up, 6 weeks" when climbed, else a
    /// gentle "just started" note keyed off the single reached tier.
    private var headline: String {
        guard chain.hasAdvanced, let start = chain.startMilestone, let current = chain.currentMilestone else {
            return "Getting started"
        }
        return "\(start.displayName) -> \(current.displayName)" + durationSuffix
    }

    private var durationSuffix: String {
        guard let weeks = chain.weeksClimbed else { return "" }
        if weeks <= 0 { return ", this week" }
        return weeks == 1 ? ", 1 week" : ", \(weeks) weeks"
    }

    private var spokenHeadline: String {
        guard chain.hasAdvanced, let start = chain.startMilestone, let current = chain.currentMilestone else {
            return "Getting started at \(chain.currentMilestone?.displayName ?? "your first tier")."
        }
        let span: String
        if let weeks = chain.weeksClimbed {
            span = weeks <= 0 ? "this week" : (weeks == 1 ? "over 1 week" : "over \(weeks) weeks")
        } else {
            span = ""
        }
        return "Advanced from \(start.displayName) to \(current.displayName)\(span.isEmpty ? "" : ", \(span)")."
    }
}

/// A single milestone: a connector-and-marker rail on the left (current tier accented), the movement
/// name and the date it was first reached on the right. A static readout, never a control.
private struct MilestoneRow: View {
    let milestone: TierMilestone
    let dateText: String
    let isFirst: Bool
    let isCurrent: Bool

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            rail
            VStack(alignment: .leading, spacing: 2) {
                Text(milestone.displayName)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(isCurrent ? "Reached \(dateText) - you're here" : "Reached \(dateText)")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(isCurrent ? Theme.Colors.accent : Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var rail: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(isFirst ? Color.clear : Theme.Colors.accent.opacity(0.5))
                .frame(width: 2, height: 8)
            Image(systemName: isCurrent ? "location.circle.fill" : "checkmark.circle.fill")
                .foregroundStyle(Theme.Colors.accent)
            Rectangle()
                .fill(isCurrent ? Color.clear : Theme.Colors.accent.opacity(0.5))
                .frame(width: 2)
                .frame(maxHeight: .infinity)
        }
        .frame(width: 22)
        .accessibilityHidden(true)
    }

    private var accessibilityLabel: String {
        isCurrent
            ? "\(milestone.displayName), reached \(dateText), you're here."
            : "\(milestone.displayName), reached \(dateText)."
    }
}

/// The current phase-earning progress (US-SP04's signals, reused) inside the strength journey: a
/// compact readout of the two earn signals for a still-climbing user, or an earned confirmation once
/// the Strength Phase is unlocked. Never loss-framed.
private struct PhaseEarningSummary: View {
    let progress: PhaseProgress
    let phase: Phase

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text("Earning the Strength Phase")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textPrimary)
            Text(note)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Earning the Strength Phase. \(note)")
    }

    private var note: String {
        if phase == .strength || progress.hasEarnedStrength {
            return "Earned - the full catalog is unlocked and harder work is on the menu."
        }
        return "\(progress.weeksSustained) of \(progress.requiredWeeks) weeks steady, \(progress.clearedFoundationCount) of \(progress.foundationCount) foundations cleared. Keep climbing."
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

// MARK: - Phase progress (US-SP04, free)

/// The "visible climb" toward the earned Strength Phase (US-SP04) - a free, read-only card that shows
/// a Discipline-Phase user the two real earn signals so the summit is visible long before it is
/// reached: **consistency** (weeks of steady practice at the score bar) and **competence** (the four
/// foundations cleared, one at a time).
///
/// Every value comes straight from `PhaseProgress`, which is the *same* computation
/// `PhaseEvaluator.evaluate` gates on (`evaluate == progress().hasEarnedStrength`), so the card can
/// never show a number the gate disagrees with. Copy is identity-framed ("you're building real
/// strength"), never loss-framed, and there is no XP, level, or streak to break - just the honest
/// state of a habit being built.
private struct PhaseProgressCard: View {
    let progress: PhaseProgress

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text("Your climb to Strength")
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text("Strength is earned, not chosen. Keep showing up and keep clearing the foundations - here's where you stand.")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }

            consistencySection
            competenceSection
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Spacing.cardCornerRadius))
    }

    // MARK: Consistency

    private var consistencySection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                Text("Steady practice")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Spacer(minLength: Theme.Spacing.sm)
                Text("\(progress.weeksSustained) of \(progress.requiredWeeks) weeks")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.accent)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.Colors.accent.opacity(0.12))
                    Capsule()
                        .fill(Theme.Colors.accent)
                        .frame(width: max(0, geo.size.width * CGFloat(weeksFraction)))
                }
            }
            .frame(height: 10)

            Text(consistencyNote)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(consistencyAccessibility)
    }

    private var weeksFraction: Double {
        guard progress.requiredWeeks > 0 else { return 0 }
        return min(1, Double(progress.weeksSustained) / Double(progress.requiredWeeks))
    }

    /// Ties the weeks bar to the second half of the consistency signal - the score that has to hold
    /// above the bar - stated as steady facts, never a warning.
    private var consistencyNote: String {
        let threshold = Int(progress.scoreThreshold.rounded())
        let score = Int(progress.currentScore.rounded())
        if progress.meetsScoreThreshold {
            return "Consistency \(score), holding above \(threshold). Sustain it across \(progress.requiredWeeks) weeks."
        }
        return "Consistency \(score), building toward \(threshold)+. That's the bar to sustain."
    }

    private var consistencyAccessibility: String {
        "Steady practice, \(progress.weeksSustained) of \(progress.requiredWeeks) weeks. \(consistencyNote)"
    }

    // MARK: Competence

    private var competenceSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                Text("Foundations")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Spacer(minLength: Theme.Spacing.sm)
                Text("\(progress.clearedFoundationCount) of \(progress.foundationCount) cleared")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.accent)
            }

            VStack(spacing: Theme.Spacing.xs) {
                ForEach(progress.foundations) { foundation in
                    foundationRow(foundation)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func foundationRow(_ foundation: PhaseProgress.FoundationProgress) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: foundation.isCleared ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(foundation.isCleared ? Theme.Colors.accent : Theme.Colors.textSecondary)
            Text(PatternLabels.name(for: foundation.pattern))
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textPrimary)
            Spacer(minLength: 0)
            Text(foundation.isCleared ? "Cleared" : "In progress")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(PatternLabels.name(for: foundation.pattern)), \(foundation.isCleared ? "cleared" : "in progress").")
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
