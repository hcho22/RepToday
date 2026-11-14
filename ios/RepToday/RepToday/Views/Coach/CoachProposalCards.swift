import SwiftUI

/// The copy for a Coach proposal card, one source for the card, VoiceOver and the tests.
enum CoachProposalCopy {
    static let confirm = "Confirm"
    static let decline = "Not now"
    static let undo = "Undo"
    static let applied = "Done"
    static let undone = "Undone"
    static let declined = "Not applied"

    static func title(_ action: CoachProposal.Action) -> String {
        switch action {
        case let .outsideActivity(type, minutes, _, _):
            return "Log a \(minutes)-minute \(type == .other ? "workout" : type.label.lowercased())"
        case .restChoice(.restToday):
            return "Rest today"
        case .restChoice(.trainAnyway):
            return "Train today"
        case let .todayLength(minutes):
            return "Make today \(minutes) minutes"
        case let .swapMovement(_, name):
            return "Swap out \(name)"
        case let .focusAreas(areas):
            return areas.isEmpty ? "Clear your Focus Areas" : "Focus on \(areas.map(\.label).joined(separator: ", "))"
        case let .reminder(hour, minute, _):
            return "Remind me at \(CoachReminderCopy.time(hour: hour, minute: minute))"
        case let .customWorkout(draft):
            return draft.title
        }
    }

    static func detail(_ action: CoachProposal.Action) -> String {
        switch action {
        case let .outsideActivity(type, _, distanceMeters, day):
            var parts = [day == .today ? "Today" : "Yesterday"]
            if let distanceMeters, distanceMeters > 0, type.hasDistance {
                parts.append(DistanceFormatting.short(meters: distanceMeters))
            }
            return parts.joined(separator: " · ") + ". " + OutsideActivityCopy.effect(of: type)
        case .restChoice(.restToday):
            return "Today becomes a rest day. Your next Training Day waits for you."
        case .restChoice(.trainAnyway):
            return "Builds your next Training Day instead of resting."
        case .todayLength:
            return "Today's session is rebuilt to fit the time."
        case .swapMovement:
            return "Rep Today picks the closest alternative for today's session."
        case .focusAreas:
            return "Focused movements get a little more attention on their days. Your Training Days stay the same."
        case let .reminder(_, _, weekdays):
            return "\(CoachReminderCopy.days(weekdays)). A notification on this iPhone - change or delete it in Settings."
        case let .customWorkout(draft):
            return draft.note
        }
    }

    /// The custom icon a proposal card leads with.
    static func icon(_ action: CoachProposal.Action) -> AppIcon {
        switch action {
        case let .outsideActivity(type, _, _, _): return type.icon
        case .restChoice(.restToday): return .calendar
        case .restChoice(.trainAnyway): return .spark
        case .todayLength: return .clock
        case .swapMovement: return .swap
        case .focusAreas: return .focus
        case .reminder: return .bell
        case .customWorkout: return .chart
        }
    }
}

/// One action the Coach proposed (US-CA03): what it does, and the user's choice. Nothing changes until
/// **Confirm**; afterwards the card says it is done and offers **Undo**. Drawn as DESIGN's proposal
/// card: `surface1`, radius 24, a 1 pt `line` outline, a `sun` icon, the title and one line of detail.
struct CoachProposalCard: View {
    let proposal: CoachProposal
    let isBusy: Bool
    let canUndo: Bool
    let error: String?
    let onConfirm: () -> Void
    let onDecline: () -> Void
    let onUndo: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                ScaledIcon(icon: CoachProposalCopy.icon(proposal.action), size: 22, relativeTo: .headline)
                    .foregroundStyle(Theme.Colors.accent)
                    .frame(minWidth: 28)
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text(CoachProposalCopy.title(proposal.action))
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(CoachProposalCopy.detail(proposal.action))
                        .font(Theme.Typography.callout)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)

            ProposalControls(
                status: proposal.status,
                confirmTitle: CoachProposalCopy.confirm,
                isBusy: isBusy,
                canUndo: canUndo,
                onConfirm: onConfirm,
                onDecline: onDecline,
                onUndo: onUndo
            )

            if let error {
                Text(error)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(outlined: true)
        .accessibilityElement(children: .contain)
    }
}

/// The controls every proposal card shares: Confirm / Not now while it waits, then its outcome and Undo.
private struct ProposalControls: View {
    let status: CoachProposal.Status
    let confirmTitle: String
    let isBusy: Bool
    let canUndo: Bool
    let onConfirm: () -> Void
    let onDecline: () -> Void
    let onUndo: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        switch status {
        case .proposed:
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(spacing: Theme.Spacing.sm))
                : AnyLayout(HStackLayout(spacing: Theme.Spacing.sm))
            layout {
                Button(action: onConfirm) {
                    Group {
                        if isBusy {
                            ProgressView().tint(Theme.Colors.onAccent)
                        } else {
                            Text(confirmTitle)
                        }
                    }
                    .font(Theme.Typography.button)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 48)
                }
                .accentFilledButtonStyle()
                .disabled(isBusy)
                .accessibilityLabel(confirmTitle)

                Button(action: onDecline) {
                    Text(CoachProposalCopy.decline)
                        .font(Theme.Typography.button)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 48)
                }
                .secondaryButtonStyle()
                .disabled(isBusy)
            }
        case .applied:
            HStack(spacing: Theme.Spacing.sm) {
                HStack(spacing: Theme.Spacing.sm) {
                    ScaledIcon(icon: .check, size: 20)
                        .foregroundStyle(Theme.Colors.legs)
                    Text(CoachProposalCopy.applied)
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Colors.legs)
                }
                .accessibilityElement(children: .combine)
                Spacer(minLength: Theme.Spacing.sm)
                if canUndo {
                    Button(action: onUndo) {
                        HStack(spacing: Theme.Spacing.xs) {
                            ScaledIcon(icon: .undo, size: 18)
                            Text(CoachProposalCopy.undo)
                                .font(Theme.Typography.headline)
                        }
                        .frame(minWidth: Theme.Spacing.minTouchTarget, minHeight: Theme.Spacing.minTouchTarget)
                    }
                    .outlineButtonStyle()
                    .disabled(isBusy)
                    .accessibilityLabel(CoachProposalCopy.undo)
                    .accessibilityHint("Puts it back the way it was")
                }
            }
        case .undone:
            outcome(CoachProposalCopy.undone, icon: .undo)
        case .declined:
            outcome(CoachProposalCopy.declined, icon: .close)
        }
    }

    /// An outcome line: one quiet `text2` line with its icon.
    private func outcome(_ text: String, icon: AppIcon) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            ScaledIcon(icon: icon, size: 16, relativeTo: .callout)
            Text(text)
                .font(Theme.Typography.calloutSemiBold)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(Theme.Colors.textSecondary)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Custom Workout card

/// A Custom Workout the Coach wrote (US-CA04): a proposal card with its steps. Catalog steps show the
/// Trainer's art; any other step is text only. Nothing plays until the user reviews and accepts it
/// (FR-11); once accepted the card offers **Play** and **Undo**.
struct CustomWorkoutCard: View {
    let draft: CustomWorkoutDraft
    let accepted: CustomWorkout?
    let status: CoachProposal.Status
    let library: [Exercise]
    let trainer: Trainer?
    let isBusy: Bool
    let canUndo: Bool
    let error: String?
    /// Opens the editor (`false`: the editor itself offers Accept and Accept and play).
    let onReview: (Bool) -> Void
    let onDecline: () -> Void
    let onPlay: (CustomWorkout) -> Void
    let onUndo: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// The steps as the player will prescribe them: the accepted (possibly edited) workout once there
    /// is one, else the Coach's draft.
    private var prescriptions: [PrescribedExercise] {
        let workout = accepted ?? CustomWorkout(draft: draft, messageId: nil, proposalId: nil, library: library, now: .distantPast)
        return workout.prescriptions(library: library)
    }

    private var minutes: Int {
        (accepted ?? CustomWorkout(draft: draft, messageId: nil, proposalId: nil, library: library, now: .distantPast)).estimatedMinutes
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text("Custom Workout · about \(minutes) min")
                    .font(Theme.Typography.caption.weight(.semibold))
                    .foregroundStyle(Theme.Colors.accent)
                Text(accepted?.title ?? draft.title)
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if !draft.note.isEmpty {
                    Text(draft.note)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)

            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                ForEach(prescriptions) { prescription in
                    CustomWorkoutStepRow(prescription: prescription, trainer: trainer)
                }
            }

            controls

            if let error {
                Text(error)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Spacing.cardCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Spacing.cardCornerRadius)
                .stroke(Theme.Colors.accent.opacity(status == .proposed ? 0.5 : 0), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var controls: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: Theme.Spacing.sm))
            : AnyLayout(HStackLayout(spacing: Theme.Spacing.sm))
        switch status {
        case .proposed:
            VStack(spacing: Theme.Spacing.sm) {
                Button { onReview(false) } label: {
                    Text("Review and accept")
                        .font(Theme.Typography.button)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: Theme.Spacing.minTouchTarget)
                }
                .accentFilledButtonStyle()
                .clipShape(RoundedRectangle(cornerRadius: Theme.Spacing.cardCornerRadius))
                .disabled(isBusy)
                .accessibilityHint("Opens the workout so you can change it before accepting. Nothing plays until you accept.")

                Button(action: onDecline) {
                    Text(CoachProposalCopy.decline)
                        .font(Theme.Typography.button)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: Theme.Spacing.minTouchTarget)
                }
                .buttonStyle(.bordered)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Spacing.cardCornerRadius))
                .disabled(isBusy)
            }
        case .applied:
            layout {
                if let accepted {
                    Button { onPlay(accepted) } label: {
                        Label("Play", systemImage: "play.fill")
                            .font(Theme.Typography.button)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: Theme.Spacing.minTouchTarget)
                    }
                    .accentFilledButtonStyle()
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Spacing.cardCornerRadius))
                    .accessibilityLabel("Play \(accepted.title)")
                    .accessibilityHint("Starts it in the hands-free player. It counts like an Outside Activity.")
                }
                if canUndo {
                    Button(action: onUndo) {
                        Text(CoachProposalCopy.undo)
                            .font(Theme.Typography.button)
                            .foregroundStyle(Theme.Colors.textPrimary)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: Theme.Spacing.minTouchTarget)
                    }
                    .buttonStyle(.bordered)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Spacing.cardCornerRadius))
                    .disabled(isBusy)
                    .accessibilityHint("Removes this workout from your saved workouts")
                }
            }
        case .undone:
            Label(CoachProposalCopy.undone, systemImage: "arrow.uturn.backward")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
        case .declined:
            Label(CoachProposalCopy.declined, systemImage: "xmark")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
    }
}

/// One step of a Custom Workout: the Trainer's start pose for a catalog movement, or a text-only marker
/// for any other movement, then its name and target in the app's one prescription copy.
struct CustomWorkoutStepRow: View {
    let prescription: PrescribedExercise
    let trainer: Trainer?

    @ScaledMetric(relativeTo: .body) private var thumbnail: CGFloat = 56

    private var isTextOnly: Bool { CustomWorkout.isTextOnly(exerciseId: prescription.exercise.id) }

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            Group {
                if isTextOnly {
                    Image(systemName: "text.alignleft")
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Colors.textSecondary)
                } else {
                    ExerciseIllustration(prescription: prescription, animatesGlyph: false, startPoseOnly: true)
                        .environment(\.trainer, trainer)
                }
            }
            .frame(width: min(thumbnail, 72), height: min(thumbnail, 72))
            .background(Theme.Colors.background, in: RoundedRectangle(cornerRadius: Theme.Spacing.sm))
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(prescription.exercise.displayName)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(ActiveSessionView.targetText(prescription) + (isTextOnly ? " · text only" : ""))
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(prescription.exercise.displayName), \(ActiveSessionView.targetAccessibilityText(prescription))"
                + (isTextOnly ? ", text only, no picture" : "")
        )
    }
}
