import SwiftUI

/// The canonical copy for the coach's analytics-driven action offer (US-AN02), in one place so the
/// card, the view model, and the tests that pin its honesty all read the same words.
///
/// The copy carries the story's load-bearing promise: the coach *narrates* the journey and *offers* a
/// bounded preference nudge - it never claims to have changed anything until the user accepts, and
/// even then it only leans what comes up first, never edits a session. The words "changed", "edited",
/// "swapped", "removed" and their kin are deliberately absent from the offer, and a test asserts it.
enum CoachAnalyticsInsightCopy {

    /// The insight + offer, naming the climbing pattern (when there is one), the stalled pattern, and
    /// how long it has been flat. The pattern clauses are exhaustive switches, so a new foundational
    /// pattern cannot be added without deciding how the coach says it out loud.
    static func offer(for offer: CoachAnalyticsInsightOffer) -> String {
        let stall = "your \(name(offer.stalledPattern)) has been flat \(weeksPhrase(offer.stalledWeeks))"
        let insight: String
        if let climbing = offer.climbingPattern {
            insight = "Your \(name(climbing)) is climbing, but \(stall)."
        } else {
            insight = "\(stall.prefix(1).uppercased() + stall.dropFirst())."
        }
        return insight
            + " Want me to lean your sessions toward \(name(offer.stalledPattern)) for a while? "
            + "It just nudges which movement comes up first - the app still builds every session, "
            + "and you can tell me to ease off any time."
    }

    /// The accept control, named for what it does - lean the program toward the stalled pattern.
    static func accept(for offer: CoachAnalyticsInsightOffer) -> String {
        "Lean into \(name(offer.stalledPattern))"
    }

    /// What accepting does, for VoiceOver. Names it as a preference nudge, never a workout change.
    static func acceptHint(for offer: CoachAnalyticsInsightOffer) -> String {
        "Biases your program toward \(name(offer.stalledPattern)); the app still builds every session"
    }

    /// The decline control. Declining dismisses the offer and changes nothing.
    static let decline = "Not now"

    /// What declining does, for VoiceOver.
    static let declineHint = "Dismisses this suggestion and changes nothing"

    /// A whole-week phrase, kept approximate so a coarse week count never reads as false precision.
    private static func weeksPhrase(_ weeks: Int) -> String {
        switch weeks {
        case ..<1: return "lately"
        case 1: return "about a week"
        default: return "about \(weeks) weeks"
        }
    }

    /// The plain, lowercase movement-pattern name used in coach copy, kept local so a wording tweak
    /// never touches the wire-stable `MovementPattern.rawValue`.
    private static func name(_ pattern: MovementPattern) -> String {
        switch pattern {
        case .push: return "push"
        case .squat: return "squat"
        case .hinge: return "hinge"
        case .core: return "core"
        case .pull: return "pull"
        case .mobility: return "mobility"
        case .locomotion: return "locomotion"
        }
    }
}

/// The coach's analytics-driven action offer, rendered as its own card at the end of the conversation
/// (US-AN02).
///
/// It is the whole of what the coach may do with an insight: narrate the journey, and offer a
/// bounded, preference-only nudge toward the stalled pattern. Accepting applies that nudge through the
/// US-AC07 policy path (never a workout edit); declining dismisses the card and changes nothing.
struct CoachAnalyticsInsightView: View {
    let offer: CoachAnalyticsInsightOffer
    let onAccept: () -> Void
    let onDecline: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .foregroundStyle(Theme.Colors.accent)
                    .accessibilityHidden(true)
                Text(CoachAnalyticsInsightCopy.offer(for: offer))
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Coach said: \(CoachAnalyticsInsightCopy.offer(for: offer))")

            // Stacked full-width, matching the coach's other in-flow decisions (US-AC04 / US-AC08), so
            // both affordances stay one-line and legible at every Dynamic Type size.
            VStack(spacing: Theme.Spacing.sm) {
                Button(action: onAccept) {
                    Text(CoachAnalyticsInsightCopy.accept(for: offer))
                        .font(Theme.Typography.button)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: Theme.Spacing.minTouchTarget)
                }
                .buttonStyle(.borderedProminent)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Spacing.cardCornerRadius))
                .accessibilityLabel(CoachAnalyticsInsightCopy.accept(for: offer))
                .accessibilityHint(CoachAnalyticsInsightCopy.acceptHint(for: offer))

                Button(action: onDecline) {
                    Text(CoachAnalyticsInsightCopy.decline)
                        .font(Theme.Typography.button)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: Theme.Spacing.minTouchTarget)
                }
                .accessibilityLabel(CoachAnalyticsInsightCopy.decline)
                .accessibilityHint(CoachAnalyticsInsightCopy.declineHint)
            }
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Spacing.cardCornerRadius))
    }
}

#if DEBUG
#Preview {
    ZStack {
        Theme.Colors.background.ignoresSafeArea()
        CoachAnalyticsInsightView(
            offer: CoachAnalyticsInsightOffer(stalledPattern: .hinge, stalledWeeks: 3, climbingPattern: .push),
            onAccept: {},
            onDecline: {}
        )
        .padding()
    }
}
#endif
