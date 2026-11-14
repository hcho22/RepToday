import SwiftUI
import UIKit

/// The workout timer: one component for the exercise work window, a hold and the rest between sets.
///
/// Top to bottom, 8 pt apart: a label row, the numerals and a progress bar that fills as the time runs
/// out. Its look follows the countdown's state:
/// - **Running**: the day's color, 132 pt numerals, a 14 pt bar, the overline label ("TIME LEFT",
///   "HOLD").
/// - **Last seconds** (from 0:03): a hard cut to `sun`, 148 pt numerals that beat once a second (still
///   under Reduce Motion), a 20 pt bar and a filled "LAST 3 SECONDS" pill.
/// - **Paused**: `text3` numerals and bar, an outlined "PAUSED" pill.
/// - **Rest**: the `rest` color at 156 pt on the rest screen.
///
/// The numerals do not scale with Dynamic Type (they are already past the largest text style); the
/// label does. A narrow screen (375 pt) draws them at 108 pt, and ten minutes or more one step smaller
/// so five glyphs fit.
///
/// **VoiceOver:** the whole timer is one element whose label is "<name>, N seconds remaining", the shape
/// the session has always spoken, carrying `.updatesFrequently` so VoiceOver reads the time on demand
/// rather than announcing every tick. While VoiceOver runs it also announces the halfway point, ten
/// seconds and three seconds once each (`WorkoutTimerAnnouncer`).
struct WorkoutTimerView: View {
    enum Kind: Equatable {
        /// A rep-based work window.
        case work
        /// A timed hold; `target` ("4 × 0:20") sits at the right of the label row.
        case hold(target: String?)
        /// The rest between sets (or the switch-sides beat), always in `rest`.
        case rest
    }

    let kind: Kind
    let remaining: Int
    let total: Int
    /// The visible label ("Time left", "Hold", "Rest", "Switch sides"), set as an overline.
    let label: String
    /// What VoiceOver names before the time ("Work window", "Hold", "Rest", "Switch sides").
    let spokenName: String
    var tone: Color
    var isPaused = false
    /// Whether the countdown is live. An idle timer (before a hold starts) shows its full time and never
    /// enters the last-seconds state.
    var isRunning = true
    /// The rest screen's hero timer draws larger.
    var isHero = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var width: CGFloat = 402

    /// Whether the countdown is in its last three seconds.
    var isLastSeconds: Bool {
        isRunning && !isPaused && remaining > 0 && remaining <= Self.lastSecondsThreshold
    }

    static let lastSecondsThreshold = 3

    var body: some View {
        let color = isPaused ? Theme.Colors.text3 : (isLastSeconds ? Theme.Colors.sun : tone)
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            labelRow
            numerals(color: color)
            bar(color: color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(spokenName), \(CountWording.phrase(remaining, singular: "second", plural: "seconds")) remaining")
        .accessibilityAddTraits(.updatesFrequently)
    }

    @ViewBuilder
    private var labelRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.smd) {
            if isPaused {
                pill("Paused", filled: false)
            } else if isLastSeconds {
                pill("Last 3 seconds", filled: true)
            } else {
                Text(label.uppercased())
                    .overlineStyle()
                    .foregroundStyle(Theme.Colors.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if case .hold(let target?) = kind {
                Text(target)
                    .font(Theme.Typography.calloutSemiBold)
                    .monospacedDigit()
                    .foregroundStyle(Theme.Colors.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func pill(_ text: String, filled: Bool) -> some View {
        Text(text.uppercased())
            .font(Theme.Typography.pill)
            .tracking(Theme.Typography.overlineTracking * 12)
            .foregroundStyle(filled ? Theme.Colors.onAccent : Theme.Colors.text1)
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(filled ? Theme.Colors.sun : Color.clear, in: Capsule())
            .overlay {
                if !filled { Capsule().strokeBorder(Theme.Colors.text1, lineWidth: 2) }
            }
    }

    private func numerals(color: Color) -> some View {
        let size = numeralSize
        return Text(ActiveSessionView.clockText(max(0, remaining)))
            .font(Theme.Typography.timer(size: size))
            .monospacedDigit()
            .tracking(Theme.Typography.timerTracking * size)
            .foregroundStyle(color)
            .lineLimit(1)
            .fixedSize()
            // The numerals' line box is the type's own (116 pt for 132): the font's generous ascent and
            // descent overhang it evenly, so the label and bar sit close, as in the design.
            .frame(height: size * Self.lineHeightRatio)
            .modifier(LastSecondsBeat(trigger: remaining, isActive: isLastSeconds && !reduceMotion))
    }

    private func bar(color: Color) -> some View {
        let elapsed = total > 0 ? min(1, max(0, 1 - Double(remaining) / Double(total))) : 0
        let height = isLastSeconds ? Theme.Spacing.timerBarLastHeight : Theme.Spacing.timerBarHeight
        return GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.Colors.surface3)
                Capsule()
                    .fill(color)
                    // The bar advances as a one-second linear change; Reduce Motion steps it. Scoped to
                    // the width alone, so the animation never reaches the screen the timer sits on (an
                    // implicit animation here kept the outgoing exercise screen alive behind the rest).
                    .animation(reduceMotion ? nil : .linear(duration: 1)) {
                        $0.frame(width: max(height, proxy.size.width * elapsed))
                    }
                    .opacity(elapsed > 0 ? 1 : 0)
            }
        }
        .frame(height: height)
    }

    /// The numerals' point size for the state, the screen width and the time's length.
    private var numeralSize: CGFloat {
        let narrow = width < 390
        if remaining >= 600 { return narrow ? 88 : 104 }
        if isLastSeconds { return narrow ? 120 : 148 }
        if isHero, kind == .rest { return narrow ? 128 : 156 }
        return narrow ? 108 : 132
    }

    /// The timer's line height as a share of its size (116 / 132).
    static let lineHeightRatio: CGFloat = 116.0 / 132.0
}

/// The last-seconds beat: the numerals swell to 106% and back over 180 ms each second.
private struct LastSecondsBeat: ViewModifier {
    let trigger: Int
    let isActive: Bool

    func body(content: Content) -> some View {
        if isActive {
            content.keyframeAnimator(initialValue: CGFloat(1), trigger: trigger) { view, scale in
                view.scaleEffect(scale, anchor: .leading)
            } keyframes: { _ in
                SpringKeyframe(1.06, duration: 0.09, spring: .init(response: 0.18, dampingRatio: 0.6))
                SpringKeyframe(1.0, duration: 0.09, spring: .init(response: 0.18, dampingRatio: 0.6))
            }
        } else {
            content
        }
    }
}

/// Announces a countdown's halfway point, ten seconds and three seconds to VoiceOver, each once per
/// countdown, and only while VoiceOver runs and the countdown is live. A countdown too short to reach a
/// mark from above (a 10-second window never announces "10 seconds") skips it.
struct WorkoutTimerAnnouncer {
    private var announced: Set<Int> = []
    private var lastTotal: Int?
    private var lastRemaining: Int?

    /// Call on every tick. Returns the sentence it announced, if any (for tests).
    @discardableResult
    mutating func tick(remaining: Int, total: Int, isLive: Bool, voiceOverRunning: Bool = UIAccessibility.isVoiceOverRunning) -> String? {
        // A new countdown - a different length, or the time climbing back up as the next set starts or
        // "+ More time" adds room - announces its marks afresh.
        if total != lastTotal || remaining > (lastRemaining ?? remaining) {
            announced = []
        }
        lastTotal = total
        lastRemaining = remaining
        guard isLive, voiceOverRunning, remaining > 0, total > 0 else { return nil }
        let marks = [(total / 2, "Halfway, \(CountWording.phrase(total / 2, singular: "second", plural: "seconds")) left"),
                     (10, "10 seconds left"),
                     (3, "3 seconds left")]
        for (mark, sentence) in marks where mark > 0 && mark < total && remaining <= mark && remaining > mark - 2 && !announced.contains(mark) {
            announced.insert(mark)
            UIAccessibility.post(notification: .announcement, argument: sentence)
            return sentence
        }
        return nil
    }
}
