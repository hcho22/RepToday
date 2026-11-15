import SwiftUI

/// The one-time Strength-Phase graduation reveal (US-SP06) - the moment the earned Strength Phase
/// becomes visible to the user who just crossed into it.
///
/// It is shown at most once, the first time the `PhaseEvaluator` reports the user has *earned* the
/// Strength Phase (sustained consistency plus cleared foundations). The copy is identity-framed and
/// honest: the milestone lands as **stewardship of a habit the user built**, never a gamified reward
/// or something withheld and now handed over. It never says "you unlocked" or "reward"; it says
/// "you're someone who moves - here's what you've earned." It names what actually changes now for this
/// user (ADR-0007): a beginner or intermediate user, held to the staple movements until now, gains every
/// movement beyond the classics as well as the Strength-Phase skills; an advanced user, who already had
/// every other movement, gains the Strength-Phase skills that finish the ladders that have them. It
/// points to the progression map on the Progress tab - the map, never a menu.
///
/// Presentation is owned by `RootView`, which layers this over the main tabs as its own overlay
/// (never a `.sheet`, so the entrance/exit can be stilled under Reduce Motion) and persists the
/// one-shot flag the moment it decides to show - so it never blocks the core loop and never re-fires.
/// Every color, font, and dimension comes from `Theme`; the dismiss control meets the 60pt
/// active-screen touch target; the surface is VoiceOver-modal and Dynamic-Type friendly.
struct StrengthGraduationRevealView: View {
    /// The graduating user's self-reported fitness level, which decides what the reveal says opens up.
    let level: FitnessLevel

    /// Dismisses the reveal and returns the user to the app.
    let onDismiss: () -> Void

    /// The points the reveal makes, each an honest statement of what the earned phase means and what
    /// changes now - never a reward, always the consequence of demonstrated behavior.
    private struct Point: Identifiable {
        let icon: AppIcon
        let title: String
        let detail: String

        var id: String { title }
    }

    /// Whether this user was held to the staple movements until now (ADR-0007).
    private var wasHeldToStaples: Bool {
        MovementAccess.isRestrictedToStaples(level: level, phase: .discipline)
    }

    private var points: [Point] {
        [
            Point(
                icon: .check,
                title: "You earned this",
                detail: "Weeks of showing up and clearing the foundations got you here. Strength is earned, not chosen - and you built it."
            ),
            wasHeldToStaples
                ? Point(
                    icon: .arrowup,
                    title: "Harder work is ready when you are",
                    detail: "Your sessions can now draw from every movement, not only the classics - including the harder skills you've been climbing toward. Rep Today still picks the day's work for you - it just has more room to vary and challenge you."
                )
                : Point(
                    icon: .arrowup,
                    title: "Harder work is ready when you are",
                    detail: "Your sessions can now reach the harder skills you've been climbing toward. Rep Today still picks the day's work for you - it just has more room to challenge you."
                ),
            wasHeldToStaples
                ? Point(
                    icon: .progress,
                    title: "More movements join your ladder",
                    detail: "The rungs beyond the classics are open, and so are the Strength-Phase movements that finish the Push, Legs, and Core ladders. They'll show up as you're ready for them."
                )
                : Point(
                    icon: .progress,
                    title: "New skills join your ladder",
                    detail: "The Strength-Phase movements that finish the Push, Legs, and Core ladders are unlocked. They'll show up as you're ready for them."
                ),
            Point(
                icon: .map,
                title: "See the whole climb",
                detail: "Open the progression map on the Progress tab to see every foundation's ladder, from where you started to the top rung."
            )
        ]
    }

    var body: some View {
        // A full-screen moment on black (P25): the Strength Phase mark, the headline in `sun`, what it
        // means, and one way out pinned below the scrolling body.
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    DayMarkView(mark: .climb, color: Theme.Colors.sun, size: 116)
                        .padding(.top, Theme.Spacing.xxl)

                    header

                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(points) { point in
                            IconPointRow(icon: point.icon, title: point.title, detail: point.detail, detailIsMarkdown: true)
                        }
                    }
                }
                .padding(.horizontal, Theme.Spacing.screenMargin)
                .padding(.bottom, Theme.Spacing.mlg)
                .frame(maxWidth: 560, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)

            dismissButton
                .padding(.horizontal, Theme.Spacing.screenMargin)
                .padding(.top, 10)
                .padding(.bottom, Theme.Spacing.sm)
                .frame(maxWidth: 560)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Colors.background.ignoresSafeArea())
        // Trap VoiceOver inside the reveal so the tabs underneath are not reachable until it is
        // dismissed - the modal semantics a system sheet would give for free.
        .accessibilityAddTraits(.isModal)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("You've earned the Strength Phase")
                .cappedDisplayFont(size: 42)
                .foregroundStyle(Theme.Colors.sun)
                .fixedSize(horizontal: false, vertical: true)
            Text("You're someone who moves - and it shows. Here's what you've built and what it opens up.")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private var dismissButton: some View {
        Button(action: onDismiss) {
            Text("Keep climbing")
                .font(Theme.Typography.button)
                .frame(maxWidth: .infinity)
                .frame(minHeight: Theme.Spacing.startButtonHeight)
        }
        .accentFilledButtonStyle()
        .accessibilityLabel("Keep climbing")
        .accessibilityHint("Dismisses this and returns to Rep Today")
    }
}

#Preview {
    ZStack {
        Theme.Colors.background.ignoresSafeArea()
        StrengthGraduationRevealView(level: .beginner, onDismiss: {})
    }
}
