import SwiftUI

/// The one-time first-run explainer for the self-driving continuous-circuit player (US-CC13).
///
/// Shown at most once, the first time a user reaches the auto-advancing player, so the shift to a
/// hands-free flow lands as reassurance rather than surprise. It states the four things a first-time
/// user needs to trust the session: it drives itself, **+ More time** is always there, each set's
/// countdown includes rest after the reps with **Done** to move on early, and tones mark each state
/// change. The copy is identity-framed and never loss-framed - it
/// tells the user they are in control of a session that carries itself, not that a manual mode they
/// had is gone.
///
/// Presentation is owned by `ActiveSessionView`, which layers this over the player *before* the session
/// starts and persists the one-shot flag; the button starts the session (ADR-0010), so the card never
/// pauses a running session and adds no tap of its own.
/// Every color, font, and dimension comes from `Theme`; the controls meet the 60pt active-screen
/// touch target; the whole surface is VoiceOver-modal and Dynamic-Type friendly, and the caller
/// stills the entrance animation under Reduce Motion.
struct ContinuousCircuitExplainerView: View {
    /// Dismisses the explainer and starts the session.
    let onDismiss: () -> Void

    /// The four points, each a distinct state change the hands-free flow makes on its own.
    private struct Point: Identifiable {
        let id = UUID()
        let icon: AppIcon
        let title: String
        let detail: String
    }

    private let points: [Point] = [
        Point(
            icon: .play,
            title: "It moves with you",
            detail: "Each set counts down and flows into the next on its own - no tapping between sets. Just follow along."
        ),
        Point(
            icon: .moretime,
            title: "More time whenever you want it",
            detail: "Need a beat longer? **+ More time** is always there and never rushes you - it only ever gives you room."
        ),
        Point(
            icon: .skip,
            title: "Rest is built into each set",
            detail: "Finish the reps, then recover until the clock ends. Ready sooner? Tap **Done** to move on early."
        ),
        Point(
            icon: .sound,
            title: "Tones mark the moment",
            detail: "A quiet cue marks each change - start, halfway, rest - so you can look up from the screen and keep going by ear."
        )
    ]

    var body: some View {
        // The overlay card over the scrim (`OverlayCard`). The scrim is hidden from VoiceOver so focus
        // lives inside the modal, and a tap on it is deliberately inert, keeping "Got it" the one,
        // unmistakable way out.
        OverlayCard {
            card
        }
    }

    private var card: some View {
        VStack(spacing: 0) {
            // Sized to its content when it fits, scrolling only when large Dynamic Type makes it taller
            // than the screen; "Got it" stays pinned below either way.
            ViewThatFits(in: .vertical) {
                pointList
                ScrollView { pointList }
            }

            dismissButton
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.bottom, Theme.Spacing.lg)
        }
        // `OverlayCard` traps VoiceOver inside the explainer, so the player underneath is not reachable
        // until it is dismissed - the modal semantics a system sheet would give for free.
    }

    private var pointList: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            header

            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                ForEach(points) { point in
                    pointRow(point)
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.top, Theme.Spacing.xl)
        .padding(.bottom, Theme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text("Your session drives itself")
                .cappedDisplayFont(size: 40)
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
            IconView(icon: point.icon, size: 26)
                .foregroundStyle(Theme.Colors.sun)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(point.title)
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(.init(point.detail))
                    .font(Theme.Typography.callout)
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
                .font(Theme.Typography.sessionSecondaryButton)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Spacing.sm)
                .frame(minHeight: Theme.Spacing.doneButtonHeight)
        }
        .accentFilledButtonStyle()
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
