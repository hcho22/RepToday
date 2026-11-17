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

    /// Whether the one-time "foundations are now Push, Pull, Legs, Core" note (ADR-0006) is up on the
    /// climb card. Decided when that card appears; the persisted one-shot flag is flipped when the note
    /// itself appears, so an empty state cannot consume a note it never rendered.
    @State private var showFoundationsNote = false

    /// Optional so the tab still renders when hosted without an `AppState` (previews, evidence suites);
    /// with none, the note is simply never raised.
    @Environment(AppState.self) private var appState: AppState?
    /// For the paywall's account link (M4, US-CA02): a purchase made here also unlocks the Coach.
    @Environment(\.services) private var services

    /// The subscription service the paywall (US-N04) purchases through. Held separately from the view
    /// model so the upsell can present the paywall sheet; the mock keeps previews rendering.
    private let subscriptionService: any SubscriptionServiceProtocol
    private let premiumSessionAuthority: PremiumSessionAuthority

    /// The telemetry sink the presented paywall emits `paywall_shown`/`trial_started`/`subscribe`
    /// through (US-T12). Held alongside `subscriptionService` and threaded into `PaywallView`; the
    /// preview/test seam leaves it `nil` so those surfaces stay off the wire.
    private let analyticsService: (any AnalyticsServiceProtocol)?

    init(services: ServiceContainer) {
        _viewModel = State(
            initialValue: ProgressViewModel(
                userService: services.userService,
                workoutLogService: services.workoutLogService,
                outsideActivityService: services.outsideActivityService,
                exerciseService: services.exerciseService,
                subscriptionService: services.subscriptionService,
                premiumSessionAuthority: services.premiumSessionAuthority,
                consistencyService: services.consistencyService,
                phaseService: services.phaseService
            )
        )
        self.subscriptionService = services.subscriptionService
        self.premiumSessionAuthority = services.premiumSessionAuthority
        self.analyticsService = services.analyticsService
    }

    /// Test/preview seam so a fixed clock and pre-seeded view model can be injected.
    init(
        viewModel: ProgressViewModel,
        subscriptionService: any SubscriptionServiceProtocol = MockSubscriptionService(),
        premiumSessionAuthority: PremiumSessionAuthority = PremiumSessionAuthority(),
        analyticsService: (any AnalyticsServiceProtocol)? = nil
    ) {
        _viewModel = State(initialValue: viewModel)
        self.subscriptionService = subscriptionService
        self.premiumSessionAuthority = premiumSessionAuthority
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
        .statusBarBacking()
        .task {
            await viewModel.load()
        }
        .sheet(isPresented: $showPaywall) {
            // The paywall accepts the exact verified grant into the shared authority before dismissal
            // and this callback, so the gated layer survives an immediately lagging entitlement read.
            // The reload is best-effort; the core loop and free surfaces are never affected.
            PaywallView(
                subscriptionService: subscriptionService,
                premiumSessionAuthority: premiumSessionAuthority,
                analyticsService: analyticsService,
                entryPoint: .progressUpsell,
                entitlements: services.premiumEntitlements
            ) { _ in
                Task { await viewModel.load() }
            }
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                header

                if viewModel.hasHistory {
                    if let consistency = viewModel.consistency {
                        ConsistencyHeadlineCard(consistency: consistency)
                    }

                    // The free "visible climb" toward the Strength Phase (US-SP04). Shown only while
                    // the user is still earning it (`.discipline`); once earned, US-SP06's graduation
                    // moment and the strength surfaces take over. Never gated.
                    if viewModel.showsClimbCard, let progress = viewModel.phaseProgress {
                        PhaseProgressCard(
                            progress: progress,
                            showsFoundationsNote: showFoundationsNote,
                            onShowFoundationsNote: { appState?.markFoundationsUpdateNoteSeen() },
                            onDismissFoundationsNote: { showFoundationsNote = false }
                        )
                        .onAppear(perform: presentFoundationsNoteIfNeeded)
                    }

                    ScoreTrendCard(trend: viewModel.trend)
                    SessionCalendarCard(
                        completedDays: viewModel.completedDays,
                        now: viewModel.displayNow,
                        calendar: viewModel.displayCalendar
                    )

                    if let analytics = viewModel.analytics {
                        // The free legibility layer (US-M02): everyone sees where their training is
                        // balanced, where they stand on each foundation line, and their bests.
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
            .padding(.horizontal, Theme.Spacing.screenMargin)
            .padding(.top, Theme.Spacing.sm)
            .padding(.bottom, Theme.Spacing.mlg)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Raises the one-time foundations note for an install that predates the change, once its climb
    /// card is on screen. The note itself persists that it was shown when it appears.
    private func presentFoundationsNoteIfNeeded() {
        guard !showFoundationsNote,
              let appState,
              appState.shouldShowFoundationsUpdateNote,
              viewModel.isFoundationsUpdateNoteEligible else { return }
        showFoundationsNote = true
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Your progress")
                .cappedDisplayFont(size: 44)
                .foregroundStyle(Theme.Colors.textPrimary)
                .keepsWordsWhole("Your progress")
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text("Every show-up is proof of who you're becoming.")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyState: some View {
        // Not drawn in the handoff; built from the same parts as the drawn cards: the `sun` mark (you)
        // in outline, since nothing has been done yet, over a card title and its supporting line.
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            DayMarkView(mark: .sun, filled: false, color: Theme.Colors.sun, size: 44)
                .padding(.bottom, Theme.Spacing.xs)
            Text("Your history starts with your first session.")
                .font(Theme.Typography.title)
                .foregroundStyle(Theme.Colors.textPrimary)
                .keepsWordsWhole("Your history starts with your first session.")
                .fixedSize(horizontal: false, vertical: true)
            Text("Show up once and this space fills with proof - a calendar, a rising score, and the longest run you've ever put together.")
                .font(Theme.Typography.callout)
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .progressCard()
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Consistency headline

/// The identity-framed score card - the big number, "you're someone who moves," and the earned
/// `longestChain` surfaced as pride (never a threat).
private struct ConsistencyHeadlineCard: View {
    let consistency: Consistency
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            // At accessibility sizes the score stacks above the message instead of squeezing the words
            // into a narrow column beside a numeral that no longer leaves room for them.
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Spacing.sm))
                : AnyLayout(HStackLayout(alignment: .bottom, spacing: 14))
            layout {
                Text("\(Int(consistency.score.rounded()))")
                    .cappedDisplayFont(Theme.Typography.FontName.displayLarge, size: 128)
                    .monospacedDigit()
                    .foregroundStyle(Theme.Colors.sun)
                    .lineLimit(1)
                    .fixedSize()
                    // The numeral's line box carries the font's tall ascender above the figures; the
                    // 120 pt frame trims that so the score sits as close under the header as DESIGN's
                    // 128/112 setting draws it.
                    .frame(height: dynamicTypeSize.isAccessibilitySize ? nil : 120, alignment: .bottom)

                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text("Consistency Score".uppercased())
                        .overlineStyle()
                        .foregroundStyle(Theme.Colors.sun)
                    Text("You're someone who moves.")
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(pride)
                        .font(Theme.Typography.footnote)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.bottom, dynamicTypeSize.isAccessibilitySize ? 0 : Theme.Spacing.xs)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Two tiles side by side; at accessibility sizes one above the other, so neither number
            // has to shrink into half a narrow screen.
            let tiles = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(spacing: 10))
                : AnyLayout(HStackLayout(alignment: .top, spacing: 10))
            tiles {
                stat(value: "\(consistency.totalWorkoutsCompleted)", label: sessionsNoun)
                stat(value: "\(consistency.totalMinutesExercised)", label: minutesMovedNoun)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private func stat(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .cappedDisplayFont(size: 44)
                .monospacedDigit()
                .foregroundStyle(Theme.Colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(Theme.Typography.calloutSemiBold)
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .cardSurface()
    }

    /// The earned point of pride - the longest on-goal run ever achieved - or an encouraging,
    /// never-loss-framed line for a user without a run yet.
    private var pride: String {
        guard consistency.longestChain > 0 else {
            return "Every time you show up counts - even five minutes."
        }
        let run = CountWording.phrase(consistency.longestChain, singular: "week", plural: "weeks")
        return "Best run: \(run) on goal."
    }

    private var sessionsNoun: String {
        CountWording.noun(for: consistency.totalWorkoutsCompleted, singular: "session", plural: "sessions")
    }

    private var minutesMovedNoun: String {
        CountWording.noun(for: consistency.totalMinutesExercised, singular: "minute moved", plural: "minutes moved")
    }

    private var accessibilityText: String {
        "You're someone who moves. Consistency \(Int(consistency.score.rounded())). \(pride) \(consistency.totalWorkoutsCompleted) \(sessionsNoun), \(consistency.totalMinutesExercised) \(minutesMovedNoun)."
    }
}

// MARK: - Score trend

/// The Consistency Score over time, rendered with Swift Charts (US-M01). With only a single week of
/// history there is no line to draw yet, so an encouraging note stands in its place.
private struct ScoreTrendCard: View {
    let trend: [ConsistencyTrendPoint]
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// Axis labels grow with text size only so far: past that the chart has no room left to draw, and
    /// VoiceOver reads the whole trend from the chart's own value.
    @ScaledMetric(relativeTo: .footnote) private var axisSize: CGFloat = 13

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.smd) {
            Text("Consistency over time")
                .font(Theme.Typography.title)
                .foregroundStyle(Theme.Colors.textPrimary)
                .keepsWordsWhole("Consistency over time")
                .fixedSize(horizontal: false, vertical: true)

            if trend.count >= 2 {
                chart
            } else {
                Text("Your trend line grows as the weeks add up. Keep showing up and it'll take shape.")
                    .font(Theme.Typography.callout)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .progressCard()
    }

    private var chart: some View {
        Chart(trend) { point in
            LineMark(
                x: .value("Week", point.weekStart),
                y: .value("Consistency", point.score)
            )
            .foregroundStyle(Theme.Colors.sun)
            .interpolationMethod(.linear)
            .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))

            // Each week an open ring; this week a filled dot carrying its score above it.
            if point.id == trend.last?.id {
                PointMark(
                    x: .value("Week", point.weekStart),
                    y: .value("Consistency", point.score)
                )
                .foregroundStyle(Theme.Colors.sun)
                .symbolSize(220)
                .annotation(position: .top, spacing: Theme.Spacing.xs) {
                    Text("\(Int(point.score.rounded()))")
                        .font(ThemeFont(Theme.Typography.FontName.displaySmall, fixedSize: 22))
                        .monospacedDigit()
                        .foregroundStyle(Theme.Colors.sun)
                }
            } else {
                PointMark(
                    x: .value("Week", point.weekStart),
                    y: .value("Consistency", point.score)
                )
                .symbol {
                    Circle()
                        .strokeBorder(Theme.Colors.sun, lineWidth: 2.5)
                        .background(Circle().fill(Theme.Colors.surface1))
                        .frame(width: 12, height: 12)
                }
            }
        }
        .chartYScale(domain: 0...100)
        .chartYAxis {
            AxisMarks(values: [0, 50, 100]) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundStyle(Theme.Colors.line)
                AxisValueLabel {
                    if let score = value.as(Int.self) {
                        Text("\(score)")
                            .font(ThemeFont(Theme.Typography.FontName.textRegular, fixedSize: min(axisSize, 18)))
                            .foregroundStyle(Theme.Colors.text3)
                    }
                }
            }
        }
        .chartXAxis {
            // The week labels are too wide to sit under every week once there are more than five, and at
            // accessibility sizes, without overprinting (Charts would drop whichever collides).
            AxisMarks(values: .stride(by: .weekOfYear, count: dynamicTypeSize.isAccessibilitySize ? 3 : trend.count > 5 ? 2 : 1)) { _ in
                AxisValueLabel(format: .dateTime.month(.abbreviated).day(), anchor: .top)
                    .font(ThemeFont(Theme.Typography.FontName.textSemiBold, fixedSize: min(axisSize, 18)).font(for: nil))
                    .foregroundStyle(Theme.Colors.text2)
            }
        }
        // Room at both ends so the first and last week's labels, centered under their points, stay whole.
        .chartXScale(range: .plotDimension(startPadding: 20, endPadding: 20))
        .chartPlotStyle { $0.padding(.top, Theme.Spacing.lg) }
        .frame(height: 190)
        .accessibilityLabel("Consistency score over time")
        .accessibilityValue(trendAccessibilityValue)
    }

    private var trendAccessibilityValue: String {
        guard let first = trend.first, let last = trend.last else { return "" }
        return "From \(Int(first.score.rounded())) to \(Int(last.score.rounded())) over \(CountWording.phrase(trend.count, singular: "week", plural: "weeks"))."
    }
}

// MARK: - Session calendar

/// A month calendar marking every day a session was completed (US-M01). The user can page back and
/// forth through their history; days with a session carry a filled accent dot.
private struct SessionCalendarCard: View {
    let completedDays: Set<Date>
    let now: Date

    @State private var monthAnchor: Date
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// The day numbers and weekday initials grow with text size only as far as a seventh of the card
    /// leaves room for, so two digits never crowd into their neighbors.
    @ScaledMetric(relativeTo: .footnote) private var dayNumberSize: CGFloat = 14
    @ScaledMetric(relativeTo: .caption2) private var weekdaySize: CGFloat = 11

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
        VStack(alignment: .leading, spacing: 10) {
            monthHeader
            weekdayHeader
            grid
        }
        .progressCard()
    }

    private var monthHeader: some View {
        // At accessibility sizes the month takes the full width and the paging buttons sit under it.
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Spacing.sm))
            : AnyLayout(HStackLayout(spacing: Theme.Spacing.sm))
        let title = monthTitleFormatter.string(from: monthAnchor)
        return layout {
            Text(title)
                .font(Theme.Typography.title)
                .foregroundStyle(Theme.Colors.textPrimary)
                .keepsWordsWhole(title)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: Theme.Spacing.sm) {
                pagingButtons
            }
        }
    }

    @ViewBuilder
    private var pagingButtons: some View {
            Button { step(-1) } label: {
                IconView(icon: .chevl, size: 22)
            }
            .circleIconButtonStyle()
            .accessibilityLabel("Previous month")

            Button { step(1) } label: {
                IconView(icon: .chevr, size: 22)
            }
            .circleIconButtonStyle()
            .disabled(isCurrentMonth)
            .accessibilityLabel("Next month")
    }

    private var weekdayHeader: some View {
        HStack(spacing: 0) {
            // Keyed by position rather than by the symbol itself: a week's initials repeat in most
            // locales (en_US is S M T W T F S), so `id: \.self` hands SwiftUI the same id for Sunday
            // and Saturday, and again for Tuesday and Thursday - which it reports at runtime as
            // undefined results. The month grid below already keys its cells by offset.
            ForEach(Array(orderedWeekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .font(ThemeFont(Theme.Typography.FontName.textBold, fixedSize: min(weekdaySize, 16)))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .frame(maxWidth: .infinity)
            }
        }
        // Visual scaffolding for the grid below, whose cells each speak their own full date - weekday
        // included - and state ("Wednesday, Jul 8, 2026, today, session completed"). Read aloud, the
        // bare initials are seven disconnected letters that say nothing the day cells do not.
        .accessibilityHidden(true)
    }

    private var grid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 2) {
            ForEach(Array(monthCells.enumerated()), id: \.offset) { _, cell in
                if let date = cell {
                    dayCell(date)
                } else {
                    Color.clear.frame(height: 50)
                }
            }
        }
    }

    /// A day: its number over a mark. A day with a session carries the filled `sun` mark (you showed
    /// up); today is a filled `sun` tile with black type and a TODAY tag.
    private func dayCell(_ date: Date) -> some View {
        let didMove = completedDays.contains(calendar.startOfDay(for: date))
        let isToday = calendar.isDate(date, inSameDayAs: now)
        let isFuture = !isToday && date > now
        return VStack(spacing: 3) {
            Text(dayFormatter.string(from: date))
                .font(ThemeFont(isToday ? Theme.Typography.FontName.textExtraBold
                                : isFuture ? Theme.Typography.FontName.textMedium : Theme.Typography.FontName.textSemiBold,
                                fixedSize: min(dayNumberSize, 20)))
                .monospacedDigit()
                .foregroundStyle(isToday ? Theme.Colors.onAccent : isFuture ? Theme.Colors.textSecondary : Theme.Colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            if isToday {
                // Fixed: the tag stays inside the tile at every text size; VoiceOver reads "today" from
                // the cell's own label.
                Text("TODAY")
                    .font(ThemeFont(Theme.Typography.FontName.textExtraBold, fixedSize: 9))
                    .tracking(0.54)
                    .foregroundStyle(Theme.Colors.onAccent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(height: 16)
            } else if didMove {
                DayMarkView(mark: .sun, filled: true, color: Theme.Colors.sun, size: 16)
            } else {
                Color.clear.frame(width: 16, height: 16)
            }
        }
        .padding(.vertical, Theme.Spacing.xs)
        .frame(maxWidth: .infinity, minHeight: 50)
        .background(isToday ? Theme.Colors.sun : Color.clear, in: RoundedRectangle(cornerRadius: 14))
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
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            CardHeader(
                title: "How you're balanced",
                detail: "The mix across strength, mobility, and primal movement."
            )

            VStack(spacing: 2) {
                ForEach(shares) { share in
                    ProgressAnalyticsBar(
                        label: PillarLabels.name(for: share.pillar),
                        fraction: share.fraction,
                        trailing: "\(Int((share.fraction * 100).rounded()))%"
                    )
                }
            }
        }
        .progressCard()
    }
}

// MARK: - Chain position (US-M02, free)

/// Where the user stands on each foundation line's active progression chain: Push, Pull, Legs (a
/// Squat side and a Hinge side), Core. Basic legibility, shown to everyone.
private struct ChainPositionCard: View {
    let positions: [ChainPositionSummary]
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            CardHeader(title: "Where you stand", detail: "Your current movement in each foundation.")

            VStack(spacing: 0) {
                ForEach(Array(FoundationGroup.grouping(positions, line: \.line).enumerated()), id: \.element.id) { index, group in
                    if index > 0 { GroupSeparator() }
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        if group.isShared {
                            // A shared foundation (Legs) names itself once, then shows each side.
                            FoundationLabel(foundation: group.foundation)
                                .accessibilityAddTraits(.isHeader)
                            ForEach(group.items) { row($0) }
                        } else {
                            ForEach(group.items) { row($0) }
                        }
                    }
                    .padding(.vertical, Theme.Spacing.smd)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .progressCard()
    }

    /// The name column: wide enough for an indented "Squat side" beside the movement.
    private let nameColumnWidth: CGFloat = 112

    private func row(_ position: ChainPositionSummary) -> some View {
        // A fixed name column beside the movement at normal sizes; at accessibility sizes the name sits
        // above the movement instead, so neither is squeezed into a narrow wrapped column.
        let stacked = dynamicTypeSize.isAccessibilitySize
        let layout = stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: Theme.Spacing.md))
        return layout {
            // A side of a shared foundation indents its *label* only, inside the same name column, so the
            // movement column lines up down every row (Push, Pull, both sides of Legs, Core).
            Group {
                if position.line.isSideOfSharedFoundation {
                    Text(position.line.sideLabel)
                        .font(Theme.Typography.calloutMedium)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .padding(.leading, FoundationLabel.markColumn)
                } else {
                    FoundationLabel(foundation: position.line.foundation)
                }
            }
            .frame(width: stacked ? nil : nameColumnWidth, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                if let exercise = position.currentExercise {
                    Text(exercise.displayName)
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(subtitle(for: position))
                        .font(Theme.Typography.footnote)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Not started yet")
                        .font(Theme.Typography.calloutMedium)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
            .padding(.leading, stacked ? FoundationLabel.markColumn : 0)
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
            return "\(position.line.spokenName), not started yet."
        }
        return "\(position.line.spokenName), \(exercise.displayName), \(subtitle(for: position))."
    }
}

// MARK: - Progression map (US-SP05, free)

/// The progression map (US-SP05): a visual per-line ladder the user is climbing, from the entry
/// tier up the chain - to the Strength-Phase skill they will earn, on the ladders that end in one.
/// It marks the current frontier ("you're here") and shows the still-locked Strength-Phase rungs with
/// an "earn the Strength Phase to unlock" affordance - *previewable but never selectable*. Legs shows
/// its Squat and Hinge ladders together; Pull's ladder is always the horizontal (row) chain.
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
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            CardHeader(
                title: "The ladder you're climbing",
                detail: "Each foundation's path, from where you started up the ladder. \(lockedRungsSentence) This is the map, not a menu: the day's work is still chosen for you."
            )

            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                ForEach(FoundationGroup.grouping(map.ladders, line: \.line)) { group in
                    if group.isShared {
                        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                            FoundationLabel(foundation: group.foundation, style: .ladder)
                                .accessibilityAddTraits(.isHeader)
                            ForEach(group.items) { ladder in
                                LadderView(ladder: ladder, phase: phase)
                            }
                        }
                    } else {
                        ForEach(group.items) { ladder in
                            LadderView(ladder: ladder, phase: phase)
                        }
                    }
                }
            }
            .padding(.top, Theme.Spacing.sm)
        }
        .progressCard()
    }

    /// Names what this map still holds locked: rungs beyond the classics for a user held to the staple
    /// movements (ADR-0007), for whom the Strength Phase opens every movement, otherwise only the
    /// Strength-Phase skills.
    private var lockedRungsSentence: String {
        let locksBeyondStrengthSkills = map.ladders.contains { ladder in
            ladder.rungs.contains { $0.isLocked && !$0.isStrengthSkill }
        }
        return locksBeyondStrengthSkills
            ? "Rungs beyond the classics open when you earn the Strength Phase."
            : "Some climbs top out in a Strength-Phase skill you earn."
    }
}

/// One line's ladder: the line's name, then a rung per movement (entry first, top rung last).
private struct LadderView: View {
    let ladder: PatternLadder
    let phase: Phase

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Group {
                if ladder.line.isSideOfSharedFoundation {
                    TitleNoteRow(
                        title: ladder.line.sideLabel,
                        titleFont: Theme.Typography.headline,
                        note: headerNote,
                        noteColor: Theme.Colors.textSecondary,
                        noteFont: Theme.Typography.footnote.weight(.semibold)
                    )
                } else {
                    // The ladder's own line names itself with its mark, in its color.
                    TitleNoteRow(
                        title: ladder.line.sideLabel,
                        titleFont: FoundationLabel.ladderFont,
                        titleColor: ladder.line.foundation.tone.color,
                        note: headerNote,
                        noteColor: Theme.Colors.textSecondary,
                        noteFont: Theme.Typography.footnote.weight(.semibold),
                        leadingMark: ladder.line.foundation
                    )
                }
            }
            // The header names the line once for VoiceOver; each rung below reads its own state.
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(ladder.line.spokenName) ladder. \(headerNote).")

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                ForEach(Array(ladder.rungs.enumerated()), id: \.element.id) { index, rung in
                    LadderRungRow(
                        rung: rung,
                        tone: ladder.line.foundation.tone,
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
    /// The ladder's foundation color: the climbed part of the rail and its cleared marks.
    let tone: DayTone
    let isLast: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            LadderRail(
                marker: marker,
                connector: isLast ? nil : connectorColor
            )
            VStack(alignment: .leading, spacing: 1) {
                Text(rung.displayName)
                    .font(nameFont)
                    .foregroundStyle(nameColor)
                    .fixedSize(horizontal: false, vertical: true)
                Text(stateNote)
                    .font(stateNoteFont)
                    .foregroundStyle(stateNoteColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.bottom, isLast ? 0 : 14)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // No `.accessibilityAddTraits(.isButton)` and no gesture: a rung is a readout, never a control.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var marker: LadderMarker {
        switch rung.state {
        case .cleared: return .cleared(tone.color)
        case .current: return .current
        case .ahead: return rung.isLocked ? .locked : .ahead
        }
    }

    private var connectorColor: Color {
        // Cleared rungs sit on the climbed part of the ladder (the foundation's color); from the current
        // rung up the rail is still to climb.
        rung.state == .cleared ? tone.color : Theme.Colors.surface3
    }

    private var nameFont: ThemeFont {
        switch rung.state {
        case .current: return ThemeFont(Theme.Typography.FontName.displaySmall, size: 20, relativeTo: .title3)
        case .cleared: return Theme.Typography.headline.weight(.semibold)
        case .ahead: return Theme.Typography.body.weight(.medium)
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

    private var stateNoteFont: ThemeFont {
        switch rung.state {
        case .current: return Theme.Typography.footnote.weight(.heavy)
        case .cleared: return Theme.Typography.footnote.weight(.semibold)
        case .ahead: return Theme.Typography.footnote.weight(.medium)
        }
    }

    private var stateNoteColor: Color {
        if rung.state == .current { return Theme.Colors.sun }
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

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Your bests")
                .font(Theme.Typography.title)
                .foregroundStyle(Theme.Colors.textPrimary)
                .keepsWordsWhole("Your bests")
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 0) {
                let rows = self.rows
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    BestRow(value: row.value, label: row.label)
                    if index < rows.count - 1 { GroupSeparator() }
                }
            }
        }
        .progressCard()
    }

    private var rows: [(value: String, label: String)] {
        var rows: [(value: String, label: String)] = [
            ("\(bests.totalSessions)", CountWording.noun(for: bests.totalSessions, singular: "session logged", plural: "sessions logged")),
            ("\(bests.longestSessionMinutes) min", "longest session"),
            ("\(bests.mostSessionsInAWeek)", "best week"),
            ("\(bests.totalMinutesMoved) min", "total moved"),
        ]
        if let reps = bests.bestReps {
            rows.append((CountWording.phrase(reps.value, singular: "rep", plural: "reps"), "best set - \(reps.displayName)"))
        }
        if let hold = bests.bestHold {
            rows.append(("\(hold.value)s", "longest hold - \(hold.displayName)"))
        }
        return rows
    }
}

/// One best: what it is on the left, the number on the right in Bricolage; at accessibility sizes the
/// number sits under its name, so neither truncates.
private struct BestRow: View {
    let value: String
    let label: String

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Spacing.xs))
            : AnyLayout(HStackLayout(alignment: .center, spacing: Theme.Spacing.smd))
        layout {
            // The label reads as a sentence-case row title; VoiceOver keeps the words as written.
            Text(label.prefix(1).uppercased() + label.dropFirst())
                .font(Theme.Typography.body.weight(.medium))
                .foregroundStyle(Theme.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? nil : .infinity, alignment: .leading)
            Text(value)
                .font(ThemeFont(Theme.Typography.FontName.displaySmall, size: 24, relativeTo: .title2))
                .monospacedDigit()
                .foregroundStyle(Theme.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
        .padding(.vertical, Theme.Spacing.xs)
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
            HStack(spacing: Theme.Spacing.sm) {
                ScaledIcon(icon: .spark, size: 22, relativeTo: .headline)
                    .foregroundStyle(Theme.Colors.sun)
                Text("Deeper analytics".uppercased())
                    .overlineStyle()
                    .foregroundStyle(Theme.Colors.sun)
                    .accessibilityLabel("Deeper analytics")
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            .padding(.top, Theme.Spacing.sm)

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
/// week's numbers. For each foundation line the user has trained it shows the dated tier
/// advancement ("Standard Push-Up -> Diamond Push-Up, over 6 weeks") read straight from real history,
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
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            CardHeader(
                title: "Your strength journey",
                detail: "Not just this week - how far you've climbed over time, one foundation at a time."
            )

            if journey.isEmpty {
                Text("Train a foundation and your climb starts here - each tier you reach, with the date you first did it.")
                    .font(Theme.Typography.callout)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    ForEach(FoundationGroup.grouping(journey.chains, line: \.line)) { group in
                        if group.isShared {
                            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                                FoundationLabel(foundation: group.foundation, style: .ladder)
                                    .accessibilityAddTraits(.isHeader)
                                ForEach(group.items) { ChainJourneyView(chain: $0) }
                            }
                        } else {
                            ForEach(group.items) { ChainJourneyView(chain: $0) }
                        }
                    }
                }
                .padding(.top, Theme.Spacing.sm)
            }

            if let phaseProgress {
                GroupSeparator()
                    .padding(.vertical, Theme.Spacing.xs)
                PhaseEarningSummary(progress: phaseProgress, phase: phase)
            }
        }
        .progressCard()
    }
}

/// One line's dated climb: a headline advancement line (from -> to, over N weeks) when the user has
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
            Group {
                if chain.line.isSideOfSharedFoundation {
                    TitleNoteRow(
                        title: chain.line.sideLabel,
                        titleFont: Theme.Typography.headline,
                        note: headline,
                        noteColor: Theme.Colors.sun,
                        noteFont: Theme.Typography.footnote.weight(.semibold)
                    )
                } else {
                    TitleNoteRow(
                        title: chain.line.sideLabel,
                        titleFont: FoundationLabel.ladderFont,
                        titleColor: chain.line.foundation.tone.color,
                        note: headline,
                        noteColor: Theme.Colors.sun,
                        noteFont: Theme.Typography.footnote.weight(.semibold),
                        leadingMark: chain.line.foundation
                    )
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(chain.line.spokenName) journey. \(spokenHeadline)")

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                ForEach(Array(chain.milestones.enumerated()), id: \.element.id) { index, milestone in
                    MilestoneRow(
                        milestone: milestone,
                        dateText: dateFormatter.string(from: milestone.firstReachedAt),
                        tone: chain.line.foundation.tone,
                        isLast: index == chain.milestones.count - 1,
                        isCurrent: milestone.id == chain.currentMilestone?.id
                    )
                }
            }
        }
    }

    /// The seen advancement headline: "Standard Push-Up -> Diamond Push-Up, 6 weeks" when climbed, a
    /// gentle "just started" note on a single reached tier, and the rung the user is on when they have
    /// not worked it yet.
    private var headline: String {
        guard let current = chain.currentMilestone else { return "You're on \(chain.currentDisplayName)" }
        guard chain.hasAdvanced, let start = chain.startMilestone else { return "Getting started" }
        return "\(start.displayName) -> \(current.displayName)" + durationSuffix
    }

    private var durationSuffix: String {
        guard let weeks = chain.weeksClimbed else { return "" }
        if weeks <= 0 { return ", this week" }
        return ", " + CountWording.phrase(weeks, singular: "week", plural: "weeks")
    }

    private var spokenHeadline: String {
        guard let current = chain.currentMilestone else { return "You're on \(chain.currentDisplayName)." }
        guard chain.hasAdvanced, let start = chain.startMilestone else {
            return "Getting started at \(current.displayName)."
        }
        let span: String
        if let weeks = chain.weeksClimbed {
            span = weeks <= 0 ? "this week" : "over " + CountWording.phrase(weeks, singular: "week", plural: "weeks")
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
    let tone: DayTone
    let isLast: Bool
    let isCurrent: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            LadderRail(
                marker: isCurrent ? .current : .cleared(tone.color),
                connector: isLast ? nil : tone.color
            )
            VStack(alignment: .leading, spacing: 1) {
                Text(milestone.displayName)
                    .font(isCurrent ? ThemeFont(Theme.Typography.FontName.displaySmall, size: 20, relativeTo: .title3)
                                    : Theme.Typography.headline.weight(.semibold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(isCurrent ? "Reached \(dateText) - you're here" : "Reached \(dateText)")
                    .font(isCurrent ? Theme.Typography.footnote.weight(.heavy) : Theme.Typography.footnote.weight(.semibold))
                    .foregroundStyle(isCurrent ? Theme.Colors.sun : Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.bottom, isLast ? 0 : 14)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
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
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text(note)
                .font(Theme.Typography.footnote)
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
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Movement patterns")
                .font(Theme.Typography.title)
                .foregroundStyle(Theme.Colors.textPrimary)
                .keepsWordsWhole("Movement patterns")
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 2) {
                ForEach(shares) { share in
                    ProgressAnalyticsBar(
                        label: PatternLabels.name(for: share.pattern),
                        fraction: share.fraction,
                        trailing: "\(share.exerciseCount)"
                    )
                }
            }
        }
        .progressCard()
    }
}

/// Completed sets per week over the rolling window, as a bar chart (Swift Charts).
private struct WeeklyVolumeCard: View {
    let points: [WeeklyVolumePoint]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.smd) {
            CardHeader(title: "Weekly volume", detail: "Sets completed each week.")

            Chart(points) { point in
                BarMark(
                    x: .value("Week", point.weekStart, unit: .weekOfYear),
                    y: .value("Sets", point.setsCompleted)
                )
                .foregroundStyle(Theme.Colors.sun)
                .cornerRadius(6)
            }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .foregroundStyle(Theme.Colors.line)
                    AxisValueLabel()
                        .font(Theme.Typography.footnote.font(for: nil))
                        .foregroundStyle(Theme.Colors.text3)
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .weekOfYear)) { _ in
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day(), centered: true)
                        .font(Theme.Typography.footnote.weight(.semibold).font(for: nil))
                        .foregroundStyle(Theme.Colors.text2)
                }
            }
            .frame(height: 160)
            .accessibilityLabel("Weekly training volume")
            .accessibilityValue(accessibilityValue)
        }
        .progressCard()
    }

    private var accessibilityValue: String {
        let total = points.reduce(0) { $0 + $1.setsCompleted }
        let sets = CountWording.phrase(total, singular: "set", plural: "sets")
        let weeks = CountWording.phrase(points.count, singular: "week", plural: "weeks")
        return "\(sets) over \(weeks)."
    }
}

/// How sessions have felt - the too-easy / just-right / too-hard split behind Adaptive Overload.
private struct DifficultyMixCard: View {
    let mix: DifficultyMix

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.smd) {
            Text("How it's felt")
                .font(Theme.Typography.title)
                .foregroundStyle(Theme.Colors.textPrimary)
                .keepsWordsWhole("How it's felt")
                .fixedSize(horizontal: false, vertical: true)

            if mix.ratedCount == 0 {
                Text("Rate a few sessions and your calibration shows up here.")
                    .font(Theme.Typography.callout)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                segmentedBar
                WrappingRow(spacing: Theme.Spacing.md, lineSpacing: Theme.Spacing.xs) {
                    legend(label: "Too easy", count: mix.tooEasy, opacity: 0.35)
                    legend(label: "Just right", count: mix.justRight, opacity: 1.0)
                    legend(label: "Too hard", count: mix.tooHard, opacity: 0.6)
                }
                Text(calibrationNote)
                    .font(Theme.Typography.footnote)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .progressCard()
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
        .frame(height: 10)
    }

    private func segment(width: CGFloat, count: Int, opacity: Double) -> some View {
        let fraction = mix.ratedCount > 0 ? CGFloat(count) / CGFloat(mix.ratedCount) : 0
        return Capsule()
            .fill(Theme.Colors.sun.opacity(opacity))
            .frame(width: max(0, width * fraction))
    }

    private func legend(label: String, count: Int, opacity: Double) -> some View {
        HStack(spacing: Theme.Spacing.xs) {
            Circle()
                .fill(Theme.Colors.sun.opacity(opacity))
                .frame(width: 8, height: 8)
            Text("\(label) \(count)")
                .font(Theme.Typography.footnote.weight(.semibold))
                .foregroundStyle(Theme.Colors.textSecondary)
        }
    }

    /// A gentle, non-judgmental read of the calibration - never loss-framed.
    private var calibrationNote: String {
        if mix.justRight >= mix.tooEasy && mix.justRight >= mix.tooHard {
            return "Mostly dialed in - your sessions are landing right."
        }
        if mix.tooHard > mix.tooEasy {
            return "Running a little hard lately - your sessions are easing you back."
        }
        return "Plenty in the tank - your sessions are nudging you up."
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
            VStack(alignment: .leading, spacing: Theme.Spacing.smd) {
                HStack(alignment: .center, spacing: 14) {
                    DayMarkView(mark: .bubble, color: Theme.Colors.sun, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Premium".uppercased())
                            .overlineStyle()
                            .foregroundStyle(Theme.Colors.sun)
                        Text("Go deeper with Premium")
                            .font(ThemeFont(Theme.Typography.FontName.displaySmall, size: 20, relativeTo: .title3))
                            .foregroundStyle(Theme.Colors.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    IconView(icon: .chevr, size: 20)
                        .foregroundStyle(Theme.Colors.sun)
                }
                Text("Unlock pattern-by-pattern balance, your weekly training volume, and how your sessions have felt over time.")
                    .font(Theme.Typography.callout)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Your workouts are always free - Premium just adds the deeper view.")
                    .font(Theme.Typography.footnote)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(18)
            .frame(maxWidth: .infinity, minHeight: Theme.Spacing.minTouchTarget, alignment: .leading)
            .background(Theme.Colors.sunTint, in: RoundedRectangle(cornerRadius: Theme.Spacing.cardCornerRadius))
            .contentShape(RoundedRectangle(cornerRadius: Theme.Spacing.cardCornerRadius))
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
    /// Whether the one-time foundations note (ADR-0006) is up at the top of the card.
    var showsFoundationsNote = false
    var onShowFoundationsNote: () -> Void = {}
    var onDismissFoundationsNote: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            CardHeader(
                title: "Your climb to Strength",
                detail: "Strength is earned, not chosen. Keep showing up and keep clearing the foundations - here's where you stand."
            )

            if showsFoundationsNote {
                FoundationsUpdateNote(progress: progress, onDismiss: onDismissFoundationsNote)
                    .onAppear(perform: onShowFoundationsNote)
                    .padding(.top, Theme.Spacing.xs)
            }

            consistencySection
                .padding(.top, 6)
            GroupSeparator()
                .padding(.vertical, Theme.Spacing.xs)
            competenceSection
        }
        .progressCard()
    }

    // MARK: Consistency

    private var consistencySection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            TitleNoteRow(
                title: "Steady practice",
                titleFont: Theme.Typography.headline,
                note: "\(progress.weeksSustained) of \(progress.requiredWeeks) weeks",
                noteColor: Theme.Colors.sun,
                noteFont: Theme.Typography.headline
            )

            // One step per required week while that stays readable; a longer bar fills by share.
            if progress.requiredWeeks > 0 && progress.requiredWeeks <= 12 {
                StepBar(count: progress.requiredWeeks, filled: min(progress.weeksSustained, progress.requiredWeeks))
            } else {
                ShareBar(fraction: weeksFraction, fill: Theme.Colors.sun)
            }

            Text(consistencyNote)
                .font(Theme.Typography.footnote)
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(consistencyAccessibility)
    }

    private var weeksFraction: Double {
        guard progress.requiredWeeks > 0 else { return 0 }
        return min(1, Double(progress.weeksSustained) / Double(progress.requiredWeeks))
    }

    /// Ties the weeks bar to the second half of the consistency signal - the score that has to hold
    /// above the bar - stated as steady facts, never a warning. The phase is earned on Rep Today
    /// sessions alone, so this number counts sessions only and is named apart from the Consistency
    /// Score, which also counts Outside Activities.
    private var consistencyNote: String {
        let threshold = Int(progress.scoreThreshold.rounded())
        let score = Int(progress.currentScore.rounded())
        if progress.meetsScoreThreshold {
            return "Session consistency \(score), holding above \(threshold). Sustain it across \(progress.requiredWeeks) weeks."
        }
        return "Session consistency \(score), building toward \(threshold)+. That's the bar to sustain."
    }

    private var consistencyAccessibility: String {
        "Steady practice, \(progress.weeksSustained) of \(progress.requiredWeeks) weeks. \(consistencyNote)"
    }

    // MARK: Competence

    private var competenceSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            TitleNoteRow(
                title: "Foundations",
                titleFont: Theme.Typography.headline,
                note: "\(progress.clearedFoundationCount) of \(progress.foundationCount) cleared",
                noteColor: Theme.Colors.textPrimary,
                noteFont: Theme.Typography.headline
            )

            VStack(spacing: 0) {
                ForEach(progress.foundations) { foundation in
                    foundationRow(foundation)
                    // Legs is one foundation with two sides; each side shows its own tick, and the
                    // header above reads Cleared only when both are.
                    if foundation.lineCount > 1 {
                        ForEach(foundation.lines) { lineRow($0) }
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func foundationRow(_ foundation: PhaseProgress.FoundationProgress) -> some View {
        StatusRow(
            isCleared: foundation.isCleared,
            mark: foundation.foundation,
            title: foundation.foundation.displayName,
            titleColor: Theme.Colors.textPrimary,
            status: status(of: foundation)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(foundation.foundation.displayName), \(spokenStatus(of: foundation)).")
    }

    /// One side of a shared foundation, indented under its header.
    private func lineRow(_ line: PhaseProgress.LineProgress) -> some View {
        StatusRow(
            isCleared: line.isCleared,
            mark: nil,
            title: line.line.sideLabel,
            titleColor: Theme.Colors.textSecondary,
            status: line.isCleared ? "Cleared" : "In progress"
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(line.line.spokenName), \(line.isCleared ? "cleared" : "in progress").")
    }

    /// "Cleared" for a cleared foundation; "1 of 2" for a shared one that is part-way (Legs); else
    /// "In progress".
    private func status(of foundation: PhaseProgress.FoundationProgress) -> String {
        if foundation.isCleared { return "Cleared" }
        return foundation.lineCount > 1 ? "\(foundation.clearedLineCount) of \(foundation.lineCount)" : "In progress"
    }

    private func spokenStatus(of foundation: PhaseProgress.FoundationProgress) -> String {
        if foundation.isCleared { return "cleared" }
        return foundation.lineCount > 1
            ? "\(foundation.clearedLineCount) of \(foundation.lineCount) sides cleared"
            : "in progress"
    }
}

/// A line's title with a note beside it - or, when the note is too long for the row (a long headline, or
/// large text), under it - so the title never wraps into a sliver next to a wrapped note.
private struct TitleNoteRow: View {
    let title: String
    let titleFont: ThemeFont
    var titleColor: Color = Theme.Colors.textPrimary
    let note: String
    let noteColor: Color
    var noteFont: ThemeFont = Theme.Typography.footnote
    /// A foundation's mark before the title, in the title's color (a ladder's own line).
    var leadingMark: StrengthFoundation?

    @ScaledMetric(relativeTo: .title3) private var markSize: CGFloat = 26

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: Theme.Spacing.sm) {
                mark
                Text(title).font(titleFont).foregroundStyle(titleColor).lineLimit(1)
                Spacer(minLength: Theme.Spacing.sm)
                Text(note).font(noteFont).foregroundStyle(noteColor).lineLimit(1)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Theme.Spacing.sm) {
                    mark
                    Text(title).font(titleFont).foregroundStyle(titleColor)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(note).font(noteFont).foregroundStyle(noteColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var mark: some View {
        if let leadingMark {
            DayMarkView(mark: leadingMark.mark, color: titleColor, size: markSize)
                .padding(.trailing, 2)
        }
    }
}

/// A tick, a name and a status on one line - or, when large text leaves no room for all three, the
/// status under the name - so a status never wraps into a two-line column beside its name.
private struct StatusRow: View {
    let isCleared: Bool
    /// The foundation's mark, or `nil` for one side of a shared foundation, which indents under it.
    let mark: StrengthFoundation?
    let title: String
    let titleColor: Color
    let status: String

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Theme.Spacing.smd) {
                leading
                Text(title).font(titleFont).foregroundStyle(titleColor).lineLimit(1)
                Spacer(minLength: Theme.Spacing.sm)
                statusLabel.lineLimit(1)
            }
            HStack(alignment: .top, spacing: Theme.Spacing.smd) {
                leading
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(titleFont).foregroundStyle(titleColor)
                        .fixedSize(horizontal: false, vertical: true)
                    statusLabel
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
    }

    private var titleFont: ThemeFont {
        mark == nil ? Theme.Typography.body.weight(.medium) : Theme.Typography.body.weight(.semibold)
    }

    /// The foundation's mark in its color, or the same width left empty under it for a side.
    @ScaledMetric(relativeTo: .body) private var markSize: CGFloat = FoundationLabel.markSize

    @ViewBuilder
    private var leading: some View {
        if let mark {
            DayMarkView(mark: mark.mark, color: mark.tone.color, size: markSize)
        } else {
            Color.clear.frame(width: markSize, height: 1)
        }
    }

    /// A cleared line carries the success check in `legs`; anything else reads quietly in `text2`.
    private var statusLabel: some View {
        HStack(spacing: Theme.Spacing.xs) {
            if isCleared {
                ScaledIcon(icon: .check, size: 16, relativeTo: .footnote)
                    .foregroundStyle(Theme.Colors.legs)
            }
            Text(status)
                .font(Theme.Typography.callout.weight(.semibold))
                .foregroundStyle(isCleared ? Theme.Colors.legs : Theme.Colors.textSecondary)
        }
    }
}

// MARK: - Foundations note (ADR-0006, free)

/// The one-time note on the climb card that the foundations are now Push, Pull, Legs, and Core, with
/// where the user stands after recalculating from their full history (no grandfathering). Shown at
/// most once, to an install that predates the change while its user still has the climb card; dismissed with
/// "Got it". Identity-framed - it explains what is now looked at, never that anything was lost.
private struct FoundationsUpdateNote: View {
    let progress: PhaseProgress
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Your foundations are now Push, Pull, Legs, and Core")
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text(detail)
                .font(Theme.Typography.footnote)
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: onDismiss) {
                Text("Got it")
                    .font(Theme.Typography.button)
                    .capsuleLabelInset("Got it")
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 48)
            }
            .secondaryButtonStyle()
            .accessibilityHint("Dismisses this note")
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.sunTint, in: RoundedRectangle(cornerRadius: Theme.Spacing.tileCornerRadius))
        .accessibilityElement(children: .contain)
    }

    private var detail: String {
        "A line clears with four clean sets at the top of your rep range, at the reps you've earned. "
            + "Legs asks for both its Squat and Hinge sides, and Pull counts the row ladder. "
            + "We recalculated where you stand from your full history: \(standing)."
    }

    /// "2 of 4 cleared (Push, Core)" - or the honest "none cleared yet" - from the same
    /// `PhaseProgress` the rows below read.
    private var standing: String {
        let cleared = progress.foundations.filter(\.isCleared).map { $0.foundation.displayName }
        guard !cleared.isEmpty else { return "none of the \(progress.foundationCount) cleared yet" }
        return "\(cleared.count) of \(progress.foundationCount) cleared (\(cleared.joined(separator: ", ")))"
    }
}

// MARK: - Foundation grouping

/// Items regrouped by their foundation in display order (Push, Pull, Legs, Core), so a surface can
/// show a shared foundation's lines (Legs' Squat and Hinge) under one header and every other
/// foundation flat. The grouping comes from `StrengthFoundation`, so no surface keeps its own order.
private struct FoundationGroup<Item>: Identifiable {
    let foundation: StrengthFoundation
    let items: [Item]

    var id: StrengthFoundation { foundation }

    /// Whether the foundation has several lines (only Legs) and so earns its own header.
    var isShared: Bool { foundation.lines.count > 1 }

    static func grouping(_ items: [Item], line: (Item) -> FoundationLine) -> [FoundationGroup<Item>] {
        StrengthFoundation.displayOrder.compactMap { foundation in
            let members = items.filter { line($0).foundation == foundation }
            return members.isEmpty ? nil : FoundationGroup(foundation: foundation, items: members)
        }
    }
}

// MARK: - Shared bar + labels

/// A labeled horizontal share bar used by the pillar and pattern balance cards.
private struct ProgressAnalyticsBar: View {
    let label: String
    let fraction: Double
    let trailing: String

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                // No room for a label column beside the bar: the label and value share a line above it.
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    HStack(alignment: .firstTextBaseline) {
                        labelText
                        Spacer(minLength: Theme.Spacing.sm)
                        trailingText
                    }
                    ShareBar(fraction: fraction)
                }
                .padding(.vertical, Theme.Spacing.xs)
            } else {
                HStack(spacing: 10) {
                    labelText
                        .frame(width: 96, alignment: .leading)
                    ShareBar(fraction: fraction)
                    trailingText
                        .frame(width: 40, alignment: .trailing)
                }
                .frame(minHeight: 32)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label), \(trailing)")
    }

    private var labelText: some View {
        Text(label)
            .font(Theme.Typography.callout.weight(.semibold))
            .foregroundStyle(Theme.Colors.textPrimary)
    }

    private var trailingText: some View {
        Text(trailing)
            .font(Theme.Typography.callout.weight(.bold))
            .monospacedDigit()
            .foregroundStyle(Theme.Colors.textSecondary)
    }
}

// MARK: - Shared card parts

extension View {
    /// A Progress card: `surface1`, radius 24, 18 pt padding, full width.
    fileprivate func progressCard() -> some View {
        padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface()
    }
}

/// A card's title (Title, Bricolage 22) and its supporting line (Callout, `text2`).
private struct CardHeader: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(title)
                .font(Theme.Typography.title)
                .foregroundStyle(Theme.Colors.textPrimary)
                .keepsWordsWhole(title)
                .fixedSize(horizontal: false, vertical: true)
            Text(detail)
                .font(Theme.Typography.callout)
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A foundation named with its mark in its color: in a row (22 pt mark, Inter SemiBold) or heading a
/// ladder (26 pt mark, Bricolage 18 in the foundation's color).
private struct FoundationLabel: View {
    enum Style { case row, ladder }

    let foundation: StrengthFoundation
    var style: Style = .row

    /// The mark's size in a row, and the column a side of a shared foundation indents by under it.
    static let markSize: CGFloat = 22
    static let markColumn: CGFloat = markSize + Theme.Spacing.smd
    static let ladderFont = ThemeFont(Theme.Typography.FontName.displaySmall, size: 18, relativeTo: .title3)

    @ScaledMetric(relativeTo: .body) private var rowMark: CGFloat = FoundationLabel.markSize
    @ScaledMetric(relativeTo: .title3) private var ladderMark: CGFloat = 26

    var body: some View {
        HStack(spacing: style == .row ? Theme.Spacing.smd : 10) {
            DayMarkView(mark: foundation.mark, color: foundation.tone.color,
                        size: style == .row ? rowMark : ladderMark)
            Text(foundation.displayName)
                .font(style == .row ? Theme.Typography.body.weight(.semibold) : Self.ladderFont)
                .foregroundStyle(style == .row ? Theme.Colors.textPrimary : foundation.tone.color)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// A rung's marker on the ladder rail.
private enum LadderMarker {
    /// Climbed past: a filled circle in the foundation's color with a black check.
    case cleared(Color)
    /// Where the user is: a `sun` ring on black with a `sun`-tint halo.
    case current
    /// Still to climb and open.
    case ahead
    /// Still to climb, opening with the Strength Phase.
    case locked
}

/// The rail down the left of a ladder: a 28 pt marker, then a 3 pt connector down to the next rung.
private struct LadderRail: View {
    let marker: LadderMarker
    /// The connector's color, or `nil` on the top rung.
    let connector: Color?

    var body: some View {
        VStack(spacing: Theme.Spacing.xs) {
            markerView
            if let connector {
                RoundedRectangle(cornerRadius: 2)
                    .fill(connector)
                    .frame(width: 3)
                    .frame(minHeight: 14, maxHeight: .infinity)
            }
        }
        .frame(width: 28)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var markerView: some View {
        switch marker {
        case .cleared(let color):
            ZStack {
                Circle().fill(color)
                IconView(icon: .check, size: 16).foregroundStyle(Theme.Colors.onAccent)
            }
            .frame(width: 28, height: 28)
        case .current:
            ZStack {
                Circle().fill(Theme.Colors.sunTint).frame(width: 36, height: 36)
                Circle().fill(Theme.Colors.black)
                Circle().strokeBorder(Theme.Colors.sun, lineWidth: 4)
            }
            .frame(width: 28, height: 28)
        case .ahead:
            Circle()
                .strokeBorder(Theme.Colors.surface3, lineWidth: 2)
                .frame(width: 28, height: 28)
        case .locked:
            ZStack {
                Circle().fill(Theme.Colors.surface3)
                IconView(icon: .lock, size: 15).foregroundStyle(Theme.Colors.textSecondary)
            }
            .frame(width: 28, height: 28)
        }
    }
}

private extension StrengthFoundation {
    /// The foundation's color on Progress: each Training Day's own, and `sun` for Core.
    var tone: DayTone {
        switch self {
        case .push: return .push
        case .pull: return .pull
        case .legs: return .legs
        case .core: return .sun
        }
    }

    /// The foundation's day mark: the Training Day's shape, and the `sun` circle for Core.
    var mark: DayMark {
        switch self {
        case .push: return .push
        case .pull: return .pull
        case .legs: return .legs
        case .core: return .sun
        }
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
            (.strength, .push, "push_standard"),
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
