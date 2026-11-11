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
                        content
                            .padding(.horizontal, Theme.Spacing.lg)
                            .padding(.vertical, Theme.Spacing.xl)
                            .frame(maxWidth: .infinity, minHeight: viewport.size.height, alignment: .center)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                }

                letsGo
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.bottom, Theme.Spacing.md)
                    .padding(.top, Theme.Spacing.sm)
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

    private var content: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text(viewModel.greeting)
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text("Today is")
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.textSecondary)
                    Text(viewModel.dayTitle)
                        .font(Theme.Typography.largeTitle)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Today is \(viewModel.dayTitle)")
                .accessibilityAddTraits(.isHeader)

                Text(viewModel.dayDetail)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if !viewModel.steps.isEmpty {
                CycleStripView(steps: viewModel.steps)
            }
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
                        .font(Theme.Typography.button)
                } else {
                    ProgressView()
                        .tint(Theme.Colors.onAccent)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: Theme.Spacing.buttonHeight)
        }
        .accentFilledButtonStyle()
        .clipShape(RoundedRectangle(cornerRadius: Theme.Spacing.cardCornerRadius))
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
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(WelcomeCopy.stripTitle)
                .font(Theme.Typography.caption.weight(.semibold))
                .foregroundStyle(Theme.Colors.textSecondary)
                .textCase(.uppercase)

            ViewThatFits(in: .horizontal) {
                EqualColumnsLayout(spacing: Theme.Spacing.sm) {
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
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Spacing.cardCornerRadius))
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

/// One step of the strip: a marker (done, today, coming up) and the step's name.
private struct CycleStepView: View {
    let step: CycleStep
    /// A column in the row (ordinary sizes) rather than a line in the list (accessibility sizes).
    let isCompact: Bool

    @ScaledMetric(relativeTo: .headline) private var markerSize: CGFloat = 36

    var body: some View {
        let layout = isCompact
            ? AnyLayout(VStackLayout(spacing: Theme.Spacing.xs))
            : AnyLayout(HStackLayout(spacing: Theme.Spacing.sm))
        layout {
            marker
            Text(step.title)
                .font(step.status == .today ? Theme.Typography.headline : Theme.Typography.body)
                .foregroundStyle(step.status == .upcoming ? Theme.Colors.textSecondary : Theme.Colors.textPrimary)
                .lineLimit(1)
        }
        .frame(maxWidth: isCompact ? .infinity : nil, alignment: isCompact ? .center : .leading)
    }

    @ViewBuilder
    private var marker: some View {
        switch step.status {
        case .done:
            Image(systemName: "checkmark")
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.onAccent)
                .frame(width: markerSize, height: markerSize)
                .background(Theme.Colors.accentFill, in: Circle())
        case .today:
            Image(systemName: symbol)
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.accent)
                .frame(width: markerSize, height: markerSize)
                .background(Theme.Colors.accentBadgeFill, in: Circle())
                .overlay(Circle().stroke(Theme.Colors.accent, lineWidth: 2))
        case .upcoming:
            Image(systemName: symbol)
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.textSecondary)
                .frame(width: markerSize, height: markerSize)
                .overlay(Circle().stroke(Theme.Colors.textSecondary.opacity(0.5), lineWidth: 1.5))
        }
    }

    private var symbol: String {
        switch step.kind {
        case .day(.push): return "figure.strengthtraining.functional"
        case .day(.pull): return "figure.rower"
        case .day(.legs): return "figure.step.training"
        case .rest: return "moon.zzz"
        case .dayOff: return "sun.max"
        }
    }
}
