import SwiftUI

/// The one-time first-run explainer for the self-driving continuous-circuit player (US-CC13).
///
/// Shown at most once, the first time a user reaches the auto-advancing player, so the shift to a
/// hands-free flow lands as reassurance rather than surprise. It states the four things a first-time
/// user needs to trust the session: it drives itself, **+ More time** is always there, **Done** jumps
/// ahead, and tones mark each state change. The copy is identity-framed and never loss-framed - it
/// tells the user they are in control of a session that carries itself, not that a manual mode they
/// had is gone.
///
/// Presentation is owned by `ActiveSessionView`, which layers this over the (already-initializing)
/// player and persists the one-shot flag, so the explainer never blocks the session from starting.
/// Every color, font, and dimension comes from `Theme`; the controls meet the 60pt active-screen
/// touch target; the whole surface is VoiceOver-modal and Dynamic-Type friendly, and the caller
/// stills the entrance animation under Reduce Motion.
struct ContinuousCircuitExplainerView: View {
    /// Dismisses the explainer and lets the session play on.
    let onDismiss: () -> Void

    /// The four points, each a distinct state change the hands-free flow makes on its own.
    private struct Point: Identifiable {
        let id = UUID()
        let symbol: String
        let title: String
        let detail: String
    }

    private let points: [Point] = [
        Point(
            symbol: "figure.run",
            title: "It moves with you",
            detail: "Each set counts down and flows into the next on its own - no tapping between sets. Just follow along."
        ),
        Point(
            symbol: "plus.circle",
            title: "More time whenever you want it",
            detail: "Need a beat longer? **+ More time** is always there and never rushes you - it only ever gives you room."
        ),
        Point(
            symbol: "forward.end",
            title: "Done jumps you ahead",
            detail: "Finished early? Tap **Done** to move straight to what's next. You set the pace."
        ),
        Point(
            symbol: "speaker.wave.2",
            title: "Tones mark the moment",
            detail: "A quiet cue marks each change - start, halfway, rest - so you can look up from the screen and keep going by ear."
        )
    ]

    var body: some View {
        ZStack {
            // The scrim behind the card. Hidden from VoiceOver so focus lives inside the modal; a tap
            // here is deliberately inert, keeping "Got it" the one, unmistakable way out.
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
        // Trap VoiceOver inside the explainer so the player underneath is not reachable until it is
        // dismissed - the modal semantics a system sheet would give for free.
        .accessibilityAddTraits(.isModal)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text("Your session drives itself")
                .font(Theme.Typography.largeTitle)
                .foregroundStyle(Theme.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Press play with your body, not your thumbs. Here's how it carries you.")
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
        // One element per point so VoiceOver reads a whole point at a time; the markdown emphasis in
        // the detail is spoken as plain words, so it names "+ More time" / "Done" without symbols.
        .accessibilityElement(children: .combine)
    }

    private var dismissButton: some View {
        Button(action: onDismiss) {
            Text("Got it")
                .font(Theme.Typography.button)
                .frame(maxWidth: .infinity)
                .frame(height: Theme.Spacing.workoutTouchTarget)
        }
        .buttonStyle(.borderedProminent)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Spacing.cardCornerRadius))
        .accessibilityLabel("Got it")
        .accessibilityHint("Dismisses this introduction and starts your session")
    }
}

#Preview {
    ZStack {
        Theme.Colors.background.ignoresSafeArea()
        ContinuousCircuitExplainerView(onDismiss: {})
    }
}
