import SwiftUI

/// The one-time Strength-Phase graduation reveal (US-SP06) - the moment the earned Strength Phase
/// becomes visible to the user who just crossed into it.
///
/// It is shown at most once, the first time the `PhaseEvaluator` reports the user has *earned* the
/// Strength Phase (sustained consistency plus cleared foundations). The copy is identity-framed and
/// honest: the milestone lands as **stewardship of a habit the user built**, never a gamified reward
/// or something withheld and now handed over. It never says "you unlocked" or "reward"; it says
/// "you're someone who moves - here's what you've earned." It names what actually changes now
/// (harder work is available; new Strength-Phase skills join the ladder) and points to the
/// progression map on the Progress tab - the map, never a menu.
///
/// Presentation is owned by `RootView`, which layers this over the main tabs as its own overlay
/// (never a `.sheet`, so the entrance/exit can be stilled under Reduce Motion) and persists the
/// one-shot flag the moment it decides to show - so it never blocks the core loop and never re-fires.
/// Every color, font, and dimension comes from `Theme`; the dismiss control meets the 60pt
/// active-screen touch target; the surface is VoiceOver-modal and Dynamic-Type friendly.
struct StrengthGraduationRevealView: View {
    /// Dismisses the reveal and returns the user to the app.
    let onDismiss: () -> Void

    /// The points the reveal makes, each an honest statement of what the earned phase means and what
    /// changes now - never a reward, always the consequence of demonstrated behavior.
    private struct Point: Identifiable {
        let id = UUID()
        let symbol: String
        let title: String
        let detail: String
    }

    private let points: [Point] = [
        Point(
            symbol: "figure.strengthtraining.traditional",
            title: "You earned this",
            detail: "Weeks of showing up and clearing the foundations got you here. Strength is earned, not chosen - and you built it."
        ),
        Point(
            symbol: "arrow.up.forward",
            title: "Harder work is ready when you are",
            detail: "Your sessions can now reach the harder skills you've been climbing toward. The engine still picks the day's work for you - it just has more room to challenge you."
        ),
        Point(
            symbol: "figure.stairs",
            title: "New skills join your ladder",
            detail: "The Strength-Phase movements at the top of each foundation are unlocked. They'll show up as you're ready for them."
        ),
        Point(
            symbol: "map",
            title: "See the whole climb",
            detail: "Open the progression map on the Progress tab to see every foundation's ladder, from where you started to the skill at the top."
        )
    ]

    var body: some View {
        ZStack {
            // The scrim behind the card. Hidden from VoiceOver so focus lives inside the modal; a tap
            // here is deliberately inert, keeping the dismiss button the one, unmistakable way out.
            Theme.Colors.textPrimary.opacity(0.35)
                .ignoresSafeArea()
                .accessibilityHidden(true)

            card
                .padding(Theme.Spacing.lg)
        }
    }

    private var card: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    header

                    VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                        ForEach(points) { point in
                            pointRow(point)
                        }
                    }
                }
                .padding(Theme.Spacing.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            dismissButton
                .padding(Theme.Spacing.lg)
        }
        .background(Theme.Colors.background)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Spacing.cardCornerRadius))
        .frame(maxWidth: 520)
        // Trap VoiceOver inside the reveal so the tabs underneath are not reachable until it is
        // dismissed - the modal semantics a system sheet would give for free.
        .accessibilityAddTraits(.isModal)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text("You've earned the Strength Phase")
                .font(Theme.Typography.largeTitle)
                .foregroundStyle(Theme.Colors.textPrimary)
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

    private func pointRow(_ point: Point) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            Image(systemName: point.symbol)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(Theme.Colors.accent)
                .frame(width: 32)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(point.title)
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(.init(point.detail))
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // One element per point so VoiceOver reads a whole point at a time.
        .accessibilityElement(children: .combine)
    }

    private var dismissButton: some View {
        Button(action: onDismiss) {
            Text("Keep climbing")
                .font(Theme.Typography.button)
                .frame(maxWidth: .infinity)
                .frame(height: Theme.Spacing.workoutTouchTarget)
        }
        .buttonStyle(.borderedProminent)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Spacing.cardCornerRadius))
        .accessibilityLabel("Keep climbing")
        .accessibilityHint("Dismisses this and returns to Rep Today")
    }
}

#Preview {
    ZStack {
        Theme.Colors.background.ignoresSafeArea()
        StrengthGraduationRevealView(onDismiss: {})
    }
}
