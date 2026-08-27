import SwiftUI

/// The canonical copy for the coach's injury routing offer (US-AC08), in one place so the card, the
/// view model, and the tests that pin its honesty all read the same words.
///
/// The copy carries the story's load-bearing promise, which no prompt on a server can guarantee for us:
/// **the coach never says it has changed anything.** It says what it noticed, offers to take the user
/// to their own control, and states plainly that nothing has changed yet. The words "removed",
/// "swapped", "adjusted", "skipped" and their kin are deliberately absent, and a test asserts that.
enum CoachInjuryOfferCopy {

    /// The offer, naming the area the message sounded like it was about.
    ///
    /// The area clause is an exhaustive switch over `InjuryOption`, so a new protectable area cannot be
    /// added without deciding how the coach says it out loud.
    static func offer(for area: InjuryOption) -> String {
        "Sounds like \(clause(for: area)). Want to flag that? I can take you to \(destination) in "
            + "Settings - you'd switch it on yourself, and you can switch it back off any time. "
            + "I haven't changed anything about your workouts."
    }

    /// The destination is named by its own screen title, so the offer, the control it opens, and the
    /// Settings row that also reaches it all say the same thing.
    private static var destination: String { InjuryFlagsCopy.title }

    private static func clause(for area: InjuryOption) -> String {
        switch area {
        case .knees: return "your knees are bothering you"
        case .lowerBack: return "your lower back is bothering you"
        case .shoulders: return "your shoulders are bothering you"
        case .wrists: return "your wrists are bothering you"
        case .ankles: return "your ankles are bothering you"
        case .hips: return "your hips are bothering you"
        }
    }

    /// The accept control. Deliberately named for what the tap *does* - it opens a screen, and names
    /// that screen - so it can never be read as the flag having been set by tapping it.
    static var accept: String { "Open \(destination)" }

    /// What the accept control opens, for VoiceOver.
    static func acceptHint(for area: InjuryOption) -> String {
        "Opens \(destination) with \(area.label.lowercased()) ready for you to confirm"
    }

    /// The decline control. Declining dismisses the offer and changes nothing.
    static let decline = "Not now"

    /// What declining does, for VoiceOver.
    static let declineHint = "Dismisses this suggestion and changes nothing"
}

/// The coach's injury routing offer, rendered as its own card at the end of the conversation
/// (US-AC08).
///
/// It is the whole of what the coach may do with a health signal: notice it, say so, and offer a route
/// to the user's own injury control. It sets nothing. Both affordances are explicit - accepting opens
/// the control (where the user still has to confirm), declining dismisses the card and leaves
/// everything exactly as it was.
struct CoachInjuryOfferView: View {
    let area: InjuryOption
    let onAccept: () -> Void
    let onDecline: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                Image(systemName: "shield.lefthalf.filled")
                    .foregroundStyle(Theme.Colors.accent)
                    .accessibilityHidden(true)
                Text(CoachInjuryOfferCopy.offer(for: area))
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Coach said: \(CoachInjuryOfferCopy.offer(for: area))")

            // Stacked rather than side by side, the same treatment the coach's other in-flow decision
            // (the US-AC04 disclosure) uses: both affordances stay full width and one-line at every
            // Dynamic Type size, so neither reads as the cramped afterthought of the other.
            VStack(spacing: Theme.Spacing.sm) {
                Button(action: onAccept) {
                    Text(CoachInjuryOfferCopy.accept)
                        .font(Theme.Typography.button)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: Theme.Spacing.minTouchTarget)
                }
                .buttonStyle(.borderedProminent)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Spacing.cardCornerRadius))
                .accessibilityLabel(CoachInjuryOfferCopy.accept)
                .accessibilityHint(CoachInjuryOfferCopy.acceptHint(for: area))

                Button(action: onDecline) {
                    Text(CoachInjuryOfferCopy.decline)
                        .font(Theme.Typography.button)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: Theme.Spacing.minTouchTarget)
                }
                .accessibilityLabel(CoachInjuryOfferCopy.decline)
                .accessibilityHint(CoachInjuryOfferCopy.declineHint)
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
        CoachInjuryOfferView(area: .knees, onAccept: {}, onDecline: {})
            .padding()
    }
}
#endif
