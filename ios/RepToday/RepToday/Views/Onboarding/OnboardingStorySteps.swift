import SwiftUI

// The onboarding story: four value screens before the questions (`screens/F02*` in the design handoff).
// Each is an overline in `sun`, a Display headline with its key phrase in `sun`, one supporting sentence
// and one visual. `OnboardingView` owns the pager above them and the Back / Continue below them.

// MARK: - Copy

/// The words the story screens say, in one place for the views and the tests that look for them.
enum OnboardingStoryCopy {
    /// Story 1's headline as VoiceOver reads it, and the line the XCUITests wait on to know onboarding is up.
    static let welcomeHeadline = "Built for the time you actually have."
    static let whoHeadline = "Busy days still have room for you."
    static let howHeadline = "Nothing to pick. Nothing to plan. Just press play."
    static let disciplineHeadline = "First the discipline. The strength follows."
}

// MARK: - Scaffold

/// One story screen: the overline, headline and supporting sentence over the screen's visual.
private struct StoryScreen<Visual: View>: View {
    let overline: String
    let headline: StoryHeadline
    let detail: String
    @ViewBuilder let visual: Visual

    var body: some View {
        VStack(alignment: .leading, spacing: StoryMetrics.sectionSpacing) {
            VStack(alignment: .leading, spacing: 10) {
                Text(overline.uppercased())
                    .overlineStyle()
                    .foregroundStyle(Theme.Colors.sun)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(overline)
                headline
                Text(detail)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.text2)
                    .designLineHeight(24, relativeTo: .body)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            visual
        }
    }
}

private enum StoryMetrics {
    /// The gap between the header and the visual, and between a visual's cards.
    static let sectionSpacing: CGFloat = 18
}

/// A story headline: Display type with its key phrase in `sun`, read by VoiceOver as one heading.
///
/// The lines are balanced, as the mockups set them (`text-wrap: balance`): the text is laid out in the
/// narrowest width that still needs no more lines than the full width does, so a three-line headline
/// never ends on a lone word. From iOS 26 its lines are set at the mockup's leading (47 for 46 pt) rather
/// than the font's own, looser one; earlier systems have no way to tighten it and keep the font's. At the
/// largest text sizes on a narrow phone it steps down just enough for its longest word to fit a line,
/// so no word is ever broken across two.
private struct StoryHeadline: View {
    let lead: String
    let highlight: String
    var trail: String = ""
    /// Display size before Dynamic Type: 46, or 40 for the longest headline.
    var size: CGFloat = 46

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// The width the headline has to wrap in, measured once it is laid out.
    @State private var availableWidth: CGFloat = 0

    var body: some View {
        BalancedLines(minimumWidth: longestWordWidth(at: pointSize)) {
            (Text(lead) + Text(highlight).foregroundStyle(Theme.Colors.sun) + Text(trail))
                .font(Font.custom(Theme.Typography.FontName.display, fixedSize: pointSize))
                .tracking(Theme.Typography.displayTracking * pointSize)
                .foregroundStyle(Theme.Colors.text1)
                .modifier(ExactLineHeight(points: lineHeight, lift: glyphLift))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { availableWidth = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(lead + highlight + trail)
        .accessibilityAddTraits(.isHeader)
    }

    /// The display size for the text size in use (capped, as every headline is), stepped down if the
    /// longest word would not fit the width on one line.
    private var pointSize: CGFloat {
        let capped = Theme.Typography.cappedDisplaySize(size, relativeTo: .largeTitle, dynamicTypeSize: dynamicTypeSize)
        let widest = longestWordWidth(at: capped)
        guard availableWidth > 0, widest > availableWidth else { return capped }
        return max(size, (capped * availableWidth / widest).rounded(.down))
    }

    private func longestWordWidth(at pointSize: CGFloat) -> CGFloat {
        guard let font = UIFont(name: Theme.Typography.FontName.display, size: pointSize) else { return 0 }
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .kern: Theme.Typography.displayTracking * pointSize]
        return (lead + highlight + trail)
            .split(separator: " ")
            .map { ceil((String($0) as NSString).size(withAttributes: attributes).width) }
            .max() ?? 0
    }

    /// The mockup's line height, size + 1 pt, scaled with the type.
    private var lineHeight: CGFloat { (pointSize * (size + 1) / size).rounded() }

    /// Half of what that line height takes off the face's own, which the system takes off the bottom of
    /// each line: lifting the text by it sits the glyphs mid-line, where CSS line-height puts them.
    private var glyphLift: CGFloat {
        let natural = UIFont(name: Theme.Typography.FontName.display, size: pointSize)?.lineHeight ?? pointSize
        return max(0, (natural - lineHeight) / 2)
    }
}

/// Sets wrapped lines `points` apart where the system can (iOS 26), lifting the drawn text by `lift`
/// without moving its frame; a no-op before iOS 26, where the font's own line height stands.
private struct ExactLineHeight: ViewModifier {
    let points: CGFloat
    var lift: CGFloat = 0

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .lineHeight(.exact(points: points))
                .offset(y: -lift)
        } else {
            content
        }
    }
}

extension View {
    /// Sets wrapped lines at a mockup's line height - `points` at the default text size, scaled with
    /// Dynamic Type relative to `style` - where the system can (iOS 26). Earlier systems keep the font's.
    func designLineHeight(_ points: CGFloat, relativeTo style: Font.TextStyle) -> some View {
        modifier(DesignLineHeight(points: points, style: style))
    }
}

private struct DesignLineHeight: ViewModifier {
    @ScaledMetric private var points: CGFloat

    init(points: CGFloat, style: Font.TextStyle) {
        _points = ScaledMetric(wrappedValue: points, relativeTo: style)
    }

    func body(content: Content) -> some View {
        content.modifier(ExactLineHeight(points: points.rounded()))
    }
}

/// Lays its one child out at the narrowest width that keeps it as short as at the full width offered:
/// balanced lines for wrapping text. The narrowing is measured on the child itself, so it agrees with
/// how SwiftUI will actually break the text. It never narrows below `minimumWidth` - the text's longest
/// word - where breaking that word could keep the same number of lines.
private struct BalancedLines: Layout {
    var minimumWidth: CGFloat = 0

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let child = subviews.first else { return .zero }
        let width = balancedWidth(of: child, within: proposal.width)
        let height = child.sizeThatFits(ProposedViewSize(width: width, height: nil)).height
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let child = subviews.first else { return }
        let width = balancedWidth(of: child, within: bounds.width)
        child.place(at: bounds.origin, proposal: ProposedViewSize(width: width, height: nil))
    }

    /// Binary-searches the narrowest width at which the child is no taller than at `available`.
    private func balancedWidth(of child: LayoutSubview, within available: CGFloat?) -> CGFloat {
        guard let available, available.isFinite, available > 0 else {
            return child.sizeThatFits(.unspecified).width
        }
        let fullHeight = child.sizeThatFits(ProposedViewSize(width: available, height: nil)).height
        var narrow = min(available, max(available / 2, minimumWidth))
        var wide = available
        // A whole point is finer than anyone can see; ten halvings get there from any phone width.
        while wide - narrow > 1 {
            let mid = (narrow + wide) / 2
            if child.sizeThatFits(ProposedViewSize(width: mid, height: nil)).height > fullHeight + 0.5 {
                narrow = mid
            } else {
                wide = mid
            }
        }
        return min(available, wide.rounded(.up))
    }
}

/// Lays its children out in one row, each as wide as its share of `weights` (the mockups' flex values).
private struct WeightedRow: Layout {
    let weights: [CGFloat]
    var spacing: CGFloat = 5
    var alignment: VerticalAlignment = .center

    /// Each column's width in `total`, for `count` children.
    func widths(for total: CGFloat, count: Int) -> [CGFloat] {
        let used = weights.prefix(count)
        let sum = used.reduce(0, +)
        let room = max(0, total - spacing * CGFloat(max(count - 1, 0)))
        return used.map { sum > 0 ? room * $0 / sum : 0 }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let total = proposal.width ?? 0
        let columns = widths(for: total, count: subviews.count)
        let height = zip(subviews, columns)
            .map { $0.sizeThatFits(ProposedViewSize(width: $1, height: nil)).height }
            .max() ?? 0
        return CGSize(width: total, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let columns = widths(for: bounds.width, count: subviews.count)
        var x = bounds.minX
        for (subview, width) in zip(subviews, columns) {
            let size = subview.sizeThatFits(ProposedViewSize(width: width, height: nil))
            let y: CGFloat
            switch alignment {
            case .top: y = bounds.minY
            case .bottom: y = bounds.maxY - size.height
            default: y = bounds.midY - size.height / 2
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(width: width, height: size.height))
            x += width + spacing
        }
    }
}

// MARK: - Shared pieces

/// One Trainer pose as the stages draw it: the art over its floor glow in `tone`, with the warm-white
/// outline that keeps the ink line off the black. Decorative: the words around it carry the screen.
private struct StoryTrainerPose: View {
    let assetName: String
    let side: CGFloat
    var tone: DayTone = .sun

    var body: some View {
        ZStack {
            Ellipse()
                .fill(EllipticalGradient(
                    colors: [tone.color.opacity(0.7), tone.color.opacity(0)],
                    center: .center, startRadiusFraction: 0, endRadiusFraction: 0.5
                ))
                .frame(width: side * 0.9, height: side * 0.13)
                .position(x: side / 2, y: side * 0.865)
            Image(assetName)
                .resizable()
                .interpolation(.high)
                .aspectRatio(1, contentMode: .fit)
                .frame(width: side, height: side)
                .shadow(color: Theme.Colors.artOutline, radius: 0, x: 1, y: 0)
                .shadow(color: Theme.Colors.artOutline, radius: 0, x: -1, y: 0)
                .shadow(color: Theme.Colors.artOutline, radius: 0, x: 0, y: 1)
                .shadow(color: Theme.Colors.artOutline, radius: 0, x: 0, y: -1)
        }
        .frame(width: side, height: side)
        .accessibilityHidden(true)
    }
}

/// Two poses side by side on a lit stage in `tone`, each at most `maxPose` and fitted down to a
/// narrower column, optionally labelled in the frame's top-left (START / END).
private struct StoryTrainerStage: View {
    let poses: [String]
    let maxPose: CGFloat
    var spacing: CGFloat = 0
    var labels: [String]? = nil
    var tone: DayTone = .sun

    var body: some View {
        GeometryReader { proxy in
            let side = min(maxPose, (proxy.size.width - spacing) / 2)
            HStack(spacing: spacing) {
                ForEach(Array(poses.enumerated()), id: \.offset) { index, name in
                    StoryTrainerPose(assetName: name, side: side, tone: tone)
                        .overlay(alignment: .topLeading) {
                            if let label = labels?[index] {
                                // Fixed at 11 pt like the exercise card's pose labels: it is chrome on art.
                                Text(label.uppercased())
                                    .font(ThemeFont(Theme.Typography.FontName.textBold, fixedSize: 11))
                                    .tracking(Theme.Typography.overlineTracking * 11)
                                    .foregroundStyle(Theme.Colors.text2)
                                    .padding(.leading, 12)
                                    .padding(.top, 10)
                            }
                        }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .frame(height: maxPose)
        .frame(maxWidth: .infinity)
        .background(ExerciseDemoView.stageBackground(tone), in: RoundedRectangle(cornerRadius: Theme.Spacing.stageCornerRadius))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Spacing.stageCornerRadius))
        .accessibilityHidden(true)
    }
}

/// A check mark beside a line of text, the check in `sun`.
private struct StoryCheckRow: View {
    let text: String
    @ScaledMetric(relativeTo: .callout) private var iconSize: CGFloat = 20

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            IconView(icon: .check, size: iconSize)
                .foregroundStyle(Theme.Colors.sun)
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 5 }
            Text(text)
                .font(Theme.Typography.calloutMedium)
                .foregroundStyle(Theme.Colors.text1)
                .designLineHeight(21, relativeTo: .callout)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A small `surface2` capsule holding a word, in `text2`.
private struct StoryTag: View {
    let text: String

    var body: some View {
        Text(text)
            .font(Theme.Typography.storyCaption)
            .foregroundStyle(Theme.Colors.text2)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Theme.Colors.surface2, in: Capsule())
    }
}

// MARK: - Story 1: the promise (F02)

/// Story 1: built for the time you actually have. The session lengths, then both Trainers on a lit
/// stage. `OnboardingView` adds the sign-in link and the usage-data disclosure around it.
struct StoryWelcomeVisual: View {
    var body: some View {
        StoryScreen(
            overline: "Rep Today",
            headline: StoryHeadline(lead: "Built for the time you ", highlight: "actually have", trail: "."),
            detail: "Five minutes or sixty. Say how long you've got and a full bodyweight session is ready."
        ) {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                durationStrip
                Text("minutes. Pick one, press Start.")
                    .font(Theme.Typography.fieldLabel)
                    .foregroundStyle(Theme.Colors.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            StoryTrainerStage(
                poses: [
                    TrainerPoseResolver.assetName(exerciseId: "lunge_reverse", trainer: .male, pose: .end),
                    TrainerPoseResolver.assetName(exerciseId: "squat_bodyweight", trainer: .female, pose: .start),
                ],
                maxPose: 165
            )
        }
    }

    /// The session lengths as tiles, the shortest lit: a picture of the choice Today offers, not a control.
    private var durationStrip: some View {
        HStack(spacing: 6) {
            ForEach(Array(DefaultDurationLearning.chipValues.enumerated()), id: \.offset) { index, minutes in
                let isLit = index == 0
                Text("\(minutes)")
                    // Fixed: the tiles are a picture of the lengths, named whole to VoiceOver below.
                    .font(Font.custom(Theme.Typography.FontName.displaySmall, fixedSize: 20))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .foregroundStyle(isLit ? Theme.Colors.onAccent : Theme.Colors.text1)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(isLit ? Theme.Colors.sun : Theme.Colors.surface1,
                                in: RoundedRectangle(cornerRadius: 14))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Sessions from 5 to 60 minutes")
        .accessibilityAddTraits(.isImage)
    }
}

// MARK: - Story 2: who it's for (F02b)

struct StoryWhoStep: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.legibilityWeight) private var legibilityWeight
    /// The width the day's labels share, measured once the card is laid out.
    @State private var labelsWidth: CGFloat = 0

    private static let labelColumns = WeightedRow(weights: [9, 3, 5], alignment: .top)

    var body: some View {
        StoryScreen(
            overline: "Who it's for",
            headline: StoryHeadline(lead: "Busy days still have ", highlight: "room for you", trail: "."),
            detail: "You used to move, then life filled up. Rep Today fits the gaps you already have instead of asking for an hour you don't."
        ) {
            dayCard
            pointsCard
        }
    }

    /// One ordinary day as a bar: work, a short lit session, everything else.
    private var dayCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("One ordinary day".uppercased())
                .overlineStyle()
                .foregroundStyle(Theme.Colors.text2)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel("One ordinary day")

            WeightedRow(weights: [9, 1.2, 6]) {
                Capsule().fill(Theme.Colors.surface3).frame(height: 22)
                RoundedRectangle(cornerRadius: 11).fill(Theme.Colors.sun).frame(height: 34)
                Capsule().fill(Theme.Colors.surface3).frame(height: 22)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("A full day with one short session in it")
            .accessibilityAddTraits(.isImage)

            dayLabels
                .frame(maxWidth: .infinity, alignment: .leading)
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { labelsWidth = $0 }
                .accessibilityElement(children: .combine)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.surface1, in: RoundedRectangle(cornerRadius: Theme.Spacing.cardCornerRadius))
    }

    /// Under the bar in the mockup's columns, or stacked once a word would no longer fit its column.
    @ViewBuilder
    private var dayLabels: some View {
        if !labelsFitColumns {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                dayLabel("Work")
                sessionLabel
                dayLabel("Everything else")
            }
        } else {
            Self.labelColumns {
                dayLabel("Work")
                    .frame(maxWidth: .infinity, alignment: .leading)
                sessionLabel
                    .lineLimit(1)
                    .fixedSize()
                    .frame(maxWidth: .infinity, alignment: .center)
                dayLabel("Everything else")
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    /// Whether every word of the three labels fits its column on one line, so none breaks mid-word.
    private var labelsFitColumns: Bool {
        guard labelsWidth > 0 else { return !dynamicTypeSize.isAccessibilitySize }
        let columns = Self.labelColumns.widths(for: labelsWidth, count: 3)
        func widest(_ words: [String], _ font: ThemeFont) -> CGFloat {
            words.map { font.width(of: $0, size: dynamicTypeSize, weight: legibilityWeight) }.max() ?? 0
        }
        return widest(["Work"], Theme.Typography.storyCaption) <= columns[0]
            && widest(["10 min"], Theme.Typography.storyCaption.weight(.heavy)) <= columns[1]
            && widest(["Everything", "else"], Theme.Typography.storyCaption) <= columns[2]
    }

    private func dayLabel(_ text: String) -> some View {
        Text(text)
            .font(Theme.Typography.storyCaption)
            .foregroundStyle(Theme.Colors.text2)
            .designLineHeight(18, relativeTo: .footnote)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var sessionLabel: some View {
        Text("10 min")
            .font(Theme.Typography.storyCaption.weight(.heavy))
            .foregroundStyle(Theme.Colors.sun)
    }

    /// The female Trainer in the world's greatest stretch beside three checked promises; the Trainer sits
    /// above them at the accessibility sizes, where a column beside her would hold a word a line.
    private var pointsCard: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 6))
        return layout {
            StoryTrainerPose(
                assetName: TrainerPoseResolver.assetName(exerciseId: "mobility_worlds_greatest", trainer: .female, pose: .start),
                side: 128
            )
            VStack(alignment: .leading, spacing: 10) {
                StoryCheckRow(text: "Made for people who sit most of the day")
                StoryCheckRow(text: "No gym. No equipment. Any room.")
                StoryCheckRow(text: "Starts gentle, at a level you can win")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            EllipticalGradient(
                stops: [.init(color: Theme.Colors.sunTint, location: 0), .init(color: Theme.Colors.surface1, location: 0.7)],
                center: UnitPoint(x: 0.15, y: 1),
                startRadiusFraction: 0,
                endRadiusFraction: 1
            ),
            in: RoundedRectangle(cornerRadius: Theme.Spacing.cardCornerRadius)
        )
    }
}

// MARK: - Story 3: how it works (F02c)

struct StoryHowStep: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private static let otherAppSteps = ["Browse", "Compare", "Plan", "Decide", "Then start"]

    var body: some View {
        StoryScreen(
            overline: "How it works",
            headline: StoryHeadline(lead: "Nothing to pick. Nothing to plan. ", highlight: "Just press play.", size: 40),
            detail: "Today's session is already built, and your Trainer shows every movement while the timer carries you through."
        ) {
            otherAppsCard
            sessionCard
            StoryTrainerStage(
                poses: [
                    TrainerPoseResolver.assetName(exerciseId: "push_standard", trainer: .male, pose: .start),
                    TrainerPoseResolver.assetName(exerciseId: "push_standard", trainer: .male, pose: .end),
                ],
                maxPose: 150,
                spacing: Theme.Spacing.sm,
                labels: ["Start", "End"],
                tone: .push
            )
        }
    }

    /// What most workout apps ask before anything starts, as quiet tags.
    private var otherAppsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Most workout apps".uppercased())
                .overlineStyle()
                .foregroundStyle(Theme.Colors.text2)
                .fixedSize(horizontal: false, vertical: true)
            FlowLayout(spacing: 6, lineSpacing: 6) {
                ForEach(Self.otherAppSteps, id: \.self) { StoryTag(text: $0) }
            }
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.surface1, in: RoundedRectangle(cornerRadius: Theme.Spacing.cardCornerRadius))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Most workout apps: \(Self.otherAppSteps.joined(separator: ", "))")
    }

    /// Rep Today's answer: today's Push Day, ready to play.
    private var sessionCard: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Spacing.smd))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 14))
        return layout {
            IconView(icon: .play, size: 30)
                .foregroundStyle(Theme.Colors.onAccent)
                .frame(width: 64, height: 64)
                .background(Theme.Colors.push, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text("Rep Today".uppercased())
                    .overlineStyle()
                    .foregroundStyle(Theme.Colors.push)
                    .accessibilityLabel("Rep Today")
                Text("Push Day: 10 min")
                    .cappedDisplayFont(size: 24, relativeTo: .title2)
                    .foregroundStyle(Theme.Colors.text1)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Built for today. Plays itself, hands-free.")
                    .font(Theme.Typography.storyDetail)
                    .foregroundStyle(Theme.Colors.text2)
                    .designLineHeight(20, relativeTo: .subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.pushTint, in: RoundedRectangle(cornerRadius: Theme.Spacing.cardCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Spacing.cardCornerRadius)
                .strokeBorder(Theme.Colors.push, lineWidth: 2)
        )
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Story 4: discipline first, strength earned (F02d)

struct StoryDisciplineStep: View {
    var body: some View {
        StoryScreen(
            overline: "What you build",
            headline: StoryHeadline(lead: "First the discipline. ", highlight: "The strength follows."),
            detail: "Other apps sell intensity. Rep Today builds the habit first, then lets your sessions earn their way up."
        ) {
            HStack(alignment: .center, spacing: Theme.Spacing.md) {
                DayMarkView(mark: .climb, color: Theme.Colors.sun, size: 84)
                FlowLayout(spacing: Theme.Spacing.sm, lineSpacing: Theme.Spacing.sm) {
                    ForEach(["Streaks", "Points", "Badges"], id: \.self) { word in
                        Text(word)
                            .font(Theme.Typography.fieldLabel.weight(.bold))
                            .strikethrough()
                            .foregroundStyle(Theme.Colors.text2)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .overlay(Capsule().strokeBorder(Theme.Colors.surface3, lineWidth: 2))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Not in Rep Today: streaks, points, badges")
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                TimelineRow(
                    marker: .done, connector: Theme.Colors.sun,
                    title: "Show up", detail: "Five minutes counts. That's the whole game."
                )
                TimelineRow(
                    marker: .current, connector: Theme.Colors.surface3,
                    title: "Hold a steady practice", detail: "One Consistency Score. Miss a day and nothing breaks."
                )
                TimelineRow(
                    marker: .locked, connector: nil,
                    title: "Earn the Strength Phase", detail: "Harder movements open once the foundations are yours."
                )
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.Colors.surface1, in: RoundedRectangle(cornerRadius: Theme.Spacing.cardCornerRadius))
        }
    }
}

/// One stage of the path: its marker, a rail down to the next stage, and its title over a line.
private struct TimelineRow: View {
    enum Marker { case done, current, locked }

    let marker: Marker
    /// The rail to the next row, or `nil` on the last.
    let connector: Color?
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: Theme.Spacing.xs) {
                markerView
                if let connector {
                    Capsule()
                        .fill(connector)
                        .frame(width: 3)
                        .frame(minHeight: 12, maxHeight: .infinity)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.Typography.storyStageTitle)
                    .foregroundStyle(Theme.Colors.text1)
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail)
                    .font(Theme.Typography.storyDetail)
                    .foregroundStyle(Theme.Colors.text2)
                    .designLineHeight(20, relativeTo: .subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 14)
        }
        // The row takes its text's height and the rail stretches to it, never into spare page height.
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var markerView: some View {
        switch marker {
        case .done:
            IconView(icon: .check, size: 17)
                .foregroundStyle(Theme.Colors.onAccent)
                .frame(width: 30, height: 30)
                .background(Theme.Colors.sun, in: Circle())
        case .current:
            Circle()
                .strokeBorder(Theme.Colors.sun, lineWidth: 5)
                .background(Theme.Colors.black, in: Circle())
                .frame(width: 30, height: 30)
        case .locked:
            IconView(icon: .lock, size: 16)
                .foregroundStyle(Theme.Colors.text2)
                .frame(width: 30, height: 30)
                .background(Theme.Colors.surface3, in: Circle())
        }
    }
}
