import SwiftUI

// MARK: - Trainer environment

private struct TrainerKey: EnvironmentKey {
    static let defaultValue: Trainer? = nil
}

extension EnvironmentValues {
    /// The Trainer whose pose art the session shows (US-TP06), set once by `ActiveSessionView` for the
    /// whole player and rest overlay. `nil` - no user, or an unresolved "other" answer before the
    /// one-time choice - shows the movement glyph, so no Trainer is ever guessed.
    var trainer: Trainer? {
        get { self[TrainerKey.self] }
        set { self[TrainerKey.self] = newValue }
    }
}

// MARK: - Exercise card

/// The exercise card (US-K01): the movement's Trainer start/end poses on the app's card color, in every
/// player state - the rep work window, a running or idle hold, a rep-based stretch - and, at a
/// flexible height, under the rest overlay's next-up preview (US-TP06/US-TP08).
///
/// The card belongs to the poses (ADR-0008): the countdown ring sits beside the exercise name instead,
/// so starting a window or a hold never changes what the card shows or its size.
struct ExerciseDemoView: View {
    let prescription: PrescribedExercise

    /// The card's height, or `nil` for a card that takes the height its container offers (the rest
    /// overlay shrinks it to fit a small phone, US-TP08).
    var height: CGFloat? = ExerciseDemoView.height

    /// Whether the no-art glyph fallback pulses - see `ExerciseIllustration.animatesGlyph`.
    var animatesGlyph: Bool = true

    /// The height of the exercise card in the player. One value for every state, so moving between
    /// them shifts nothing below the card.
    static let height: CGFloat = 220

    var body: some View {
        ExerciseIllustration(prescription: prescription, animatesGlyph: animatesGlyph)
            .padding(Theme.Spacing.sm)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(
                Theme.Colors.secondaryBackground,
                in: RoundedRectangle(cornerRadius: Theme.Spacing.cardCornerRadius)
            )
    }
}

// MARK: - Illustration

/// The movement illustration - the one source every host renders through (US-TP06), so the card and
/// the rest preview cannot show a movement two different ways.
///
/// It asks `TrainerPoseResolver` what the session's Trainer is drawn in for this movement and shows:
/// - a **pair**: start on the left, end on the right, equal squares, each aspect-fit to the full
///   untrimmed 600x600 canvas so the two poses share one frame and never jump;
/// - a **single pose**: that pose, the same size, centered;
/// - **no art** (or no Trainer yet): the per-`MovementPattern` SF-Symbol glyph, as before.
///
/// The art is static (no flipbook, cross-fade, or rep sync) and drawn as-is on both sides of a
/// per-side movement. To VoiceOver the whole illustration is one element (US-TP09) whose label names
/// the exercise and what the Trainer shows; the individual images are hidden.
struct ExerciseIllustration: View {
    let prescription: PrescribedExercise

    /// Whether the glyph fallback pulses. The idle card pulses it to read as "this is the demo"; a card
    /// under a running countdown or a rest preview keeps it still. Reduce Motion stills it regardless.
    var animatesGlyph: Bool = true

    var resolver: TrainerPoseResolver = .bundled

    @Environment(\.trainer) private var trainer
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let art = trainer.map { resolver.art(exerciseId: prescription.exercise.id, trainer: $0) } ?? .none
        GeometryReader { proxy in
            content(art, in: proxy.size)
                .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            TrainerPoseCopy.accessibilityLabel(exerciseName: prescription.exercise.displayName, art: art)
        )
    }

    /// The gap between the two poses of a pair.
    private static let poseSpacing: CGFloat = Theme.Spacing.sm

    @ViewBuilder
    private func content(_ art: TrainerPoseArt, in size: CGSize) -> some View {
        // One pose's square: half the width (less the gap) or the full height, whichever is smaller -
        // the same for a pair and a single pose, so a single pose is never bigger than a paired one.
        let side = max(0, min((size.width - Self.poseSpacing) / 2, size.height))
        switch art {
        case .pair(let start, let end):
            HStack(spacing: Self.poseSpacing) {
                pose(start, side: side)
                pose(end, side: side)
            }
        case .single(_, let name):
            pose(name, side: side)
        case .none:
            glyph(size: min(size.width, size.height))
        }
    }

    private func pose(_ name: String, side: CGFloat) -> some View {
        Image(name)
            .resizable()
            .interpolation(.high)
            .aspectRatio(1, contentMode: .fit)
            .frame(width: side, height: side)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private func glyph(size: CGFloat) -> some View {
        let base = Image(systemName: symbolName)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(Theme.Colors.accent)

        if reduceMotion || !animatesGlyph {
            base // static fallback - no animation against Reduce Motion, or where a still illustration is wanted
        } else {
            base.symbolEffect(.pulse, options: .repeating)
        }
    }

    /// A movement-appropriate SF Symbol so the fallback reads as the right kind of exercise.
    private var symbolName: String {
        switch prescription.exercise.movementPattern {
        case .push: return "figure.strengthtraining.traditional"
        case .squat: return "figure.cross.training"
        case .hinge: return "figure.strengthtraining.functional"
        case .core: return "figure.core.training"
        case .pull: return "figure.climbing"
        case .mobility: return "figure.flexibility"
        case .locomotion: return "figure.run"
        }
    }
}
