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

/// The exercise card (US-K01), drawn as the Trainer stage: the movement's Trainer start/end poses on a
/// lit stage in the session's color, in every player state - the rep work window, a running or idle
/// hold, a rep-based stretch - and, at a flexible height, under the rest screen's next-up preview
/// (US-TP06/US-TP08).
///
/// The stage has a 28 pt radius and a radial glow, an ellipse 95% x 75% anchored at the bottom centre,
/// from the day's tint to `stageBase` at 78%. The card belongs to the poses (ADR-0008): the timer sits
/// below the movement name instead, so starting a window or a hold never changes what the card shows.
/// Only on a short screen does the player's card give up height (`fittedHeight`).
struct ExerciseDemoView: View {
    let prescription: PrescribedExercise

    /// The card's height, or `nil` for a card that takes the height its container offers (the rest
    /// screen shrinks it to fit a small phone, US-TP08).
    var height: CGFloat? = ExerciseDemoView.height

    /// Whether the no-art fallback mark pulses - see `ExerciseIllustration.animatesGlyph`.
    var animatesGlyph: Bool = true

    @Environment(\.dayTone) private var tone

    /// The tallest the exercise card grows in the player: two square poses side by side across the
    /// widest phone's column. One value for every state, so moving between them shifts nothing below
    /// the card wherever the column fits; a narrower column or a short screen fits it down.
    static let height: CGFloat = 200

    /// The smallest a card shrinks to on a short screen, in the player and the rest preview alike.
    static let minHeight: CGFloat = 100

    /// The player card's height with `room` points free for it: the full `height` when it fits,
    /// otherwise `room`, shrinking the poses with it - but never below `minHeight`, past which the
    /// player's column scrolls instead.
    static func fittedHeight(room: CGFloat) -> CGFloat {
        min(height, max(room, minHeight))
    }

    /// The height at which two square poses and their gap exactly fill `width`: the stage never draws
    /// taller than its poses need.
    static func naturalHeight(width: CGFloat) -> CGFloat {
        max(0, (width - ExerciseIllustration.poseSpacing) / 2)
    }

    var body: some View {
        ExerciseIllustration(prescription: prescription, animatesGlyph: animatesGlyph, showsPoseLabels: true)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(Self.stageBackground(tone), in: RoundedRectangle(cornerRadius: Theme.Spacing.stageCornerRadius))
            .clipShape(RoundedRectangle(cornerRadius: Theme.Spacing.stageCornerRadius))
    }

    /// The stage's lit background: an ellipse 95% x 75% anchored bottom centre, from the day's tint to
    /// `stageBase` at 78%.
    static func stageBackground(_ tone: DayTone) -> some ShapeStyle {
        EllipticalGradient(
            stops: [.init(color: tone.tint, location: 0), .init(color: Theme.Colors.stageBase, location: 0.78)],
            center: .bottom,
            startRadiusFraction: 0,
            endRadiusFraction: 1
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

    /// Shows only the start pose of a pair, filling the frame: a list thumbnail (a Custom Workout step)
    /// is too small for two poses side by side to read.
    var startPoseOnly: Bool = false

    /// Labels each pose START and END (HOLD for a hold's single pose) in its frame's empty top-left,
    /// and lights a floor glow under each figure: the Trainer stage's dressing. A thumbnail leaves it off.
    var showsPoseLabels: Bool = false

    var resolver: TrainerPoseResolver = .bundled

    @Environment(\.trainer) private var trainer
    @Environment(\.dayTone) private var tone
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let art = trainer.map { resolver.art(exerciseId: prescription.exercise.id, trainer: $0) } ?? .none
        GeometryReader { proxy in
            content(art, in: proxy.size)
                .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            isTextOnly
                ? "\(prescription.exercise.displayName), described in words, no picture"
                : TrainerPoseCopy.accessibilityLabel(exerciseName: prescription.exercise.displayName, art: art)
        )
    }

    /// A Custom Workout step that names no catalog movement (decision 27) is text only: the card shows
    /// its name rather than guessing a picture.
    private var isTextOnly: Bool { CustomWorkout.isTextOnly(exerciseId: prescription.exercise.id) }

    /// The gap between the two poses of a pair.
    static let poseSpacing: CGFloat = Theme.Spacing.sm

    @ViewBuilder
    private func content(_ art: TrainerPoseArt, in size: CGSize) -> some View {
        // One pose's square: half the width (less the gap) or the full height, whichever is smaller -
        // the same for a pair and a single pose, so a single pose is never bigger than a paired one.
        let side = max(0, min((size.width - Self.poseSpacing) / 2, size.height))
        if isTextOnly {
            Text(prescription.exercise.displayName)
                .font(Theme.Typography.title)
                .foregroundStyle(Theme.Colors.textPrimary)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.5)
                .padding(Theme.Spacing.md)
        } else {
            artContent(art, side: side, size: size)
        }
    }

    @ViewBuilder
    private func artContent(_ art: TrainerPoseArt, side: CGFloat, size: CGSize) -> some View {
        switch art {
        case .pair(let start, _) where startPoseOnly:
            pose(start, side: min(size.width, size.height), label: nil)
        case .pair(let start, let end):
            HStack(spacing: Self.poseSpacing) {
                pose(start, side: side, label: "Start")
                pose(end, side: side, label: "End")
            }
        case .single(_, let name):
            pose(name, side: startPoseOnly ? min(size.width, size.height) : side,
                 label: prescription.exercise.isHold ? "Hold" : nil)
        case .none:
            glyph(size: min(size.width, size.height))
        }
    }

    /// One square pose, shown whole (`.fit`, never cropped or stretched). On the stage it sits over a
    /// floor glow - an ellipse across 5-95% of the frame's width and 80-93% of its height, the day's
    /// color at 70% fading to clear, under feet the art places at 87% - with its overline label in the
    /// frame's empty top-left. A 1 pt warm-white outline (four 1 pt shadows) keeps the ink line off the
    /// black.
    private func pose(_ name: String, side: CGFloat, label: String?) -> some View {
        ZStack(alignment: .topLeading) {
            if showsPoseLabels {
                Ellipse()
                    .fill(EllipticalGradient(
                        colors: [tone.color.opacity(0.7), tone.color.opacity(0)],
                        center: .center, startRadiusFraction: 0, endRadiusFraction: 0.5
                    ))
                    .frame(width: side * 0.9, height: side * 0.13)
                    .position(x: side / 2, y: side * 0.865)
            }
            Image(name)
                .resizable()
                .interpolation(.high)
                .aspectRatio(1, contentMode: .fit)
                .frame(width: side, height: side)
                .shadow(color: Theme.Colors.artOutline, radius: 0, x: 1, y: 0)
                .shadow(color: Theme.Colors.artOutline, radius: 0, x: -1, y: 0)
                .shadow(color: Theme.Colors.artOutline, radius: 0, x: 0, y: 1)
                .shadow(color: Theme.Colors.artOutline, radius: 0, x: 0, y: -1)
            if showsPoseLabels, let label {
                // Fixed at 11 pt: the label sits inside the art's square, which does not grow with text.
                Text(label.uppercased())
                    .font(Font.custom(Theme.Typography.FontName.textBold, fixedSize: 11))
                    .tracking(Theme.Typography.overlineTracking * 11)
                    .foregroundStyle(Theme.Colors.text2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .padding(.leading, 12)
                    .padding(.top, 10)
            }
        }
        .frame(width: side, height: side)
        .accessibilityHidden(true)
    }

    /// The no-art fallback: the movement's day mark in the session's color, pulsing gently on an idle
    /// card (never under Reduce Motion).
    @ViewBuilder
    private func glyph(size: CGFloat) -> some View {
        let base = DayMarkView(mark: mark, filled: true, color: tone.color, size: size * 0.45)

        if reduceMotion || !animatesGlyph {
            base // static fallback - no animation against Reduce Motion, or where a still illustration is wanted
        } else {
            base.phaseAnimator([1.0, 0.55]) { view, opacity in
                view.opacity(opacity)
            } animation: { _ in .easeInOut(duration: 0.9) }
        }
    }

    /// The day mark that stands for the movement's pattern, so the fallback reads as the right kind of
    /// exercise: the dome for push, the arch for pull, the steps for legs, the circle for core, the
    /// crescent for mobility and the climb for locomotion.
    private var mark: DayMark {
        switch prescription.exercise.movementPattern {
        case .push: return .push
        case .pull: return .pull
        case .squat, .hinge: return .legs
        case .core: return .sun
        case .mobility: return .rest
        case .locomotion: return .climb
        }
    }
}
