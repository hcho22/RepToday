import SwiftUI

/// The copy for the one-time Trainer choice (US-TP10) and the Settings row (US-TP11) - one source each.
enum TrainerChoiceCopy {
    static let title = "Choose your Trainer"
    static let message = "Your Trainer shows the start and end of each movement. You can switch any time in Settings."
    static let optionHint = "Shows this Trainer during your sessions"

    /// The Settings section and row title.
    static let settingsTitle = "Trainer"
    /// What the Settings row shows for a user who answered "other" and has not chosen yet (captain,
    /// Open Question 6) - a neutral value, never a guessed Trainer.
    static let notChosenValue = "Not chosen yet"
    static let settingsFooter = "Your Trainer demonstrates each movement during a session."
    /// Shown under the Settings row when a switch could not be saved (captain, Open Question 8).
    static let saveFailureMessage = "Couldn't save your Trainer. Your previous Trainer is still set - please try again."
}

/// The one-time Trainer choice for a user whose onboarding answer was "other" (US-TP10).
///
/// Exactly two options, one per Trainer, and no "decide later", skip, or dismiss-without-choosing path
/// (decision 15): choosing is the only way out. Each option shows that Trainer's start pose for the
/// current movement - its only pose when the start is missing, or the Trainer's name alone when it has
/// none (captain, Open Question 4) - so the user picks the demonstrator they are about to see.
///
/// Presentation is owned by `ActiveSessionView`, which layers this over the player in the style of the
/// US-CC13 explainer (an overlay, not a sheet, so Reduce Motion can still its entrance) and holds the
/// session on a user pause while it is up (captain, Open Question 3). Controls meet the 60pt
/// active-screen touch target; the card is VoiceOver-modal and scrolls under large Dynamic Type.
struct TrainerChoiceView: View {
    /// The movement the user is about to see, whose start pose previews each Trainer.
    let exerciseId: String
    var resolver: TrainerPoseResolver = .bundled
    let onChoose: (Trainer) -> Void

    var body: some View {
        ZStack {
            // Inert, VoiceOver-hidden scrim: choosing a Trainer is the one way out.
            Theme.Colors.textPrimary.opacity(0.35)
                .ignoresSafeArea()
                .accessibilityHidden(true)

            card
                .padding(Theme.Spacing.lg)
        }
    }

    private var card: some View {
        // Sized to its content when it fits, scrolling only when large Dynamic Type makes it taller
        // than the screen - so the common case is a compact card rather than a full-height one.
        ViewThatFits(in: .vertical) {
            content
            ScrollView { content }
        }
        .background(Theme.Colors.background)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Spacing.cardCornerRadius))
        .frame(maxWidth: 520)
        .accessibilityAddTraits(.isModal)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(TrainerChoiceCopy.title)
                    .font(Theme.Typography.largeTitle)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(TrainerChoiceCopy.message)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            HStack(alignment: .top, spacing: Theme.Spacing.md) {
                ForEach(Trainer.allCases) { trainer in
                    option(trainer)
                }
            }
        }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func option(_ trainer: Trainer) -> some View {
        let preview = resolver.art(exerciseId: exerciseId, trainer: trainer).previewAssetName
        return Button {
            onChoose(trainer)
        } label: {
            VStack(spacing: Theme.Spacing.sm) {
                if let preview {
                    Image(preview)
                        .resizable()
                        .aspectRatio(1, contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .accessibilityHidden(true)
                }
                Text(trainer.displayName)
                    .font(Theme.Typography.button)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Theme.Spacing.sm)
            .frame(maxWidth: .infinity, minHeight: Theme.Spacing.workoutTouchTarget)
            .background(
                Theme.Colors.secondaryBackground,
                in: RoundedRectangle(cornerRadius: Theme.Spacing.cardCornerRadius)
            )
            .contentShape(RoundedRectangle(cornerRadius: Theme.Spacing.cardCornerRadius))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(trainer.displayName)
        .accessibilityHint(TrainerChoiceCopy.optionHint)
    }
}

#Preview {
    ZStack {
        Theme.Colors.background.ignoresSafeArea()
        TrainerChoiceView(exerciseId: "hinge_glute_bridge", onChoose: { _ in })
    }
}
