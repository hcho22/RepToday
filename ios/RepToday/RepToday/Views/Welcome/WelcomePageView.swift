import SwiftUI

/// The Welcome Page (US-HO01, decision 19): the tap-through moment on every cold launch after
/// onboarding, before Today. A greeting with the user's name, today's Training Day or Rest Day, the
/// Cycle strip, and "Let's go".
///
/// It replaces the launch spinner: `RootView` builds the app shell behind it, so Today loads while the
/// user reads this page, and "Let's go" waits only until that shell is ready (`isReady`). Its entrance
/// is stilled under Reduce Motion.
struct WelcomePageView: View {
    @State private var viewModel: WelcomeViewModel
    /// Whether the app behind the page is ready to be revealed.
    let isReady: Bool
    let onContinue: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var hasAppeared = false

    init(viewModel: WelcomeViewModel, isReady: Bool, onContinue: @escaping () -> Void) {
        _viewModel = State(initialValue: viewModel)
        self.isReady = isReady
        self.onContinue = onContinue
    }

    var body: some View {
        ZStack {
            Theme.Colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                GeometryReader { viewport in
                    ScrollView {
                        content(markSize: viewport.size.height < 620 ? 96 : 140)
                            .padding(.horizontal, Theme.Spacing.screenMargin)
                            .padding(.vertical, Theme.Spacing.mlg)
                            .frame(maxWidth: .infinity, minHeight: viewport.size.height, alignment: .center)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                }

                letsGo
                    .padding(.horizontal, Theme.Spacing.screenMargin)
                    .padding(.bottom, Theme.Spacing.sm)
                    .padding(.top, 10)
            }
            .opacity(hasAppeared ? 1 : 0)
            .offset(y: hasAppeared || reduceMotion ? 0 : Theme.Spacing.md)
        }
        .task { await viewModel.load() }
        .onAppear {
            if reduceMotion {
                hasAppeared = true
            } else {
                withAnimation(.easeOut(duration: 0.35)) { hasAppeared = true }
            }
        }
    }

    /// The day's color: its Training Day's, `rest` for a Rest Day or a day off, `sun` before the plan is
    /// known.
    private var tone: DayTone {
        switch viewModel.plan {
        case let .train(day)?: return DayTone(day)
        case .rest?: return .rest
        case nil: return .sun
        }
    }

    private var mark: DayMark {
        switch viewModel.plan {
        case let .train(day)?: return DayMark(day)
        case .rest?: return .rest
        case nil: return .sun
        }
    }

    /// The page's words under the day's mark, which draws at `markSize` (140, or 96 on a short screen so
    /// the Cycle strip still clears "Let's go").
    private func content(markSize: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            Spacer(minLength: Theme.Spacing.mlg)

            // The day's mark, big; it steps aside at the accessibility text sizes so the words keep the
            // screen.
            if !dynamicTypeSize.isAccessibilitySize {
                DayMarkView(mark: mark, color: tone.color, size: markSize)
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(viewModel.greeting)
                    .font(Theme.Typography.body.weight(.medium))
                    .foregroundStyle(Theme.Colors.text2)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text("Today is")
                        .font(Theme.Typography.todayIs)
                        .foregroundStyle(Theme.Colors.text1)
                    Text(viewModel.dayTitle)
                        .cappedDisplayFont(Theme.Typography.FontName.displayLarge, size: 84)
                        .foregroundStyle(tone.color)
                        // One line at the ordinary sizes, fitted down a little on the narrowest phone;
                        // at the accessibility sizes it wraps at its cap instead.
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                        .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.75)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Today is \(viewModel.dayTitle)")
                .accessibilityAddTraits(.isHeader)

                Text(viewModel.dayDetail)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if !viewModel.steps.isEmpty {
                CycleStripView(steps: viewModel.steps)
            }

            Spacer(minLength: Theme.Spacing.sm)
        }
        // Holds the space while the plan loads, so nothing jumps when it lands.
        .opacity(viewModel.isLoaded ? 1 : 0)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: viewModel.isLoaded)
    }

    private var letsGo: some View {
        Button(action: onContinue) {
            ZStack {
                if isReady {
                    Text(WelcomeCopy.letsGo)
                        .font(Theme.Typography.startButton)
                } else {
                    ProgressView()
                        .tint(Theme.Colors.onAccent)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: Theme.Spacing.startButtonHeight)
        }
        .primaryButtonStyle(tone.color)
        .disabled(!isReady)
        .accessibilityLabel(WelcomeCopy.letsGo)
        .accessibilityHint(isReady ? "Opens Today" : "Getting today ready")
    }
}

// MARK: - Cycle strip

/// The Cycle strip (decision 19): the groups done this Cycle, today, and what is still to come, ending
/// with the Rest Day. A row of equal columns when every name fits in full, otherwise a list, so no name
/// is ever squeezed or cut off at any text size or screen width. Read by VoiceOver as one sentence.
struct CycleStripView: View {
    let steps: [CycleStep]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(WelcomeCopy.stripTitle.uppercased())
                .overlineStyle()
                .foregroundStyle(Theme.Colors.text2)

            ViewThatFits(in: .horizontal) {
                EqualColumnsLayout(spacing: Theme.Spacing.xs) {
                    ForEach(steps) { step in
                        CycleStepView(step: step, isCompact: true)
                    }
                }
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    ForEach(steps) { step in
                        CycleStepView(step: step, isCompact: false)
                    }
                }
            }
        }
        .padding(.vertical, 18)
        .padding(.horizontal, Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        "\(WelcomeCopy.stripTitle): " + steps.map(\.accessibilityLabel).joined(separator: ". ") + "."
    }
}

/// The strip's row: one column per step, all as wide as the widest step needs. Its ideal width is the
/// width that shows every name in full, so `ViewThatFits` picks the list whenever the row cannot.
private struct EqualColumnsLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard !subviews.isEmpty else { return .zero }
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let ideal = (sizes.map(\.width).max() ?? 0) * CGFloat(subviews.count) + spacing * CGFloat(subviews.count - 1)
        let width = proposal.width.map { $0.isFinite ? max($0, ideal) : ideal } ?? ideal
        return CGSize(width: width, height: sizes.map(\.height).max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard !subviews.isEmpty else { return }
        let column = (bounds.width - spacing * CGFloat(subviews.count - 1)) / CGFloat(subviews.count)
        for (index, subview) in subviews.enumerated() {
            let x = bounds.minX + CGFloat(index) * (column + spacing)
            subview.place(at: CGPoint(x: x, y: bounds.minY), proposal: ProposedViewSize(width: column, height: bounds.height))
        }
    }
}

/// One step of the strip (DESIGN "Cycle strip"): its day mark - filled in the day's color for done and
/// today, outlined in it for what is to come - and the step's name, in the day's color for today, `text2`
/// for what is still to come. Today carries a "TODAY" pill; a done step's mark carries a check and a
/// "Done" line.
private struct CycleStepView: View {
    let step: CycleStep
    /// A column in the row (ordinary sizes) rather than a line in the list (accessibility sizes).
    let isCompact: Bool

    @ScaledMetric(relativeTo: .headline) private var markerSize: CGFloat = 44

    var body: some View {
        let layout = isCompact
            ? AnyLayout(VStackLayout(spacing: 6))
            : AnyLayout(HStackLayout(spacing: Theme.Spacing.smd))
        layout {
            marker
            Text(step.title)
                .font(step.status == .today ? Theme.Typography.calloutSemiBold.weight(.bold) : Theme.Typography.calloutSemiBold)
                .foregroundStyle(titleColor)
                .lineLimit(1)
            badge
        }
        .frame(maxWidth: isCompact ? .infinity : nil, alignment: isCompact ? .center : .leading)
    }

    /// The line under the name: the "TODAY" pill, "Done", or an empty line of the same height so the
    /// columns stay level.
    @ViewBuilder
    private var badge: some View {
        switch step.status {
        case .today:
            Text("Today".uppercased())
                .font(Theme.Typography.todayPill)
                .tracking(0.8)
                .foregroundStyle(Theme.Colors.onAccent)
                .lineLimit(1)
                .padding(.horizontal, Theme.Spacing.sm)
                .padding(.vertical, 1)
                .background(tone.color, in: Capsule())
        case .done:
            Text("Done")
                .font(ThemeFont(Theme.Typography.FontName.textSemiBold, size: 11, relativeTo: .caption2))
                .foregroundStyle(Theme.Colors.text3)
                .lineLimit(1)
        case .upcoming:
            if isCompact {
                Text(" ")
                    .font(ThemeFont(Theme.Typography.FontName.textSemiBold, size: 11, relativeTo: .caption2))
                    .accessibilityHidden(true)
            }
        }
    }

    private var titleColor: Color {
        switch step.status {
        case .today: return tone.color
        case .done: return Theme.Colors.text1
        case .upcoming: return Theme.Colors.text2
        }
    }

    private var marker: some View {
        ZStack {
            DayMarkView(
                mark: mark,
                filled: step.status != .upcoming,
                color: tone.color,
                size: markerSize
            )
            if step.status == .done {
                IconView(icon: .check, size: markerSize * 0.5)
                    .foregroundStyle(Theme.Colors.onAccent)
                    .offset(y: mark == .push || mark == .pull ? markerSize * 0.1 : 0)
            }
        }
        .frame(width: markerSize, height: markerSize)
    }

    private var mark: DayMark {
        switch step.kind {
        case .day(let day): return DayMark(day)
        case .rest: return .rest
        case .dayOff: return .sun
        }
    }

    private var tone: DayTone {
        switch step.kind {
        case .day(let day): return DayTone(day)
        case .rest: return .rest
        case .dayOff: return .sun
        }
    }
}
