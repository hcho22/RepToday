import SwiftUI

/// The canonical copy for the coach data disclosure (US-AC04, updated for the Coach agent in M4,
/// US-CA07), in one place so the pre-use modal (`CoachDataDisclosureView`) and the Settings entry
/// (`SettingsView`) say the same thing and can never drift. Tests assert against these constants, so a
/// wording change is a single edit.
///
/// Since M4 the coach runs on Rep Today's servers and reads the user's training records there, so the
/// copy names plainly what reaches the model provider - including workout history and injury history -
/// and that the conversation is kept with the account. Bump `AppState.coachDataSharingDisclosureVersion`
/// whenever what it describes changes.
enum CoachDataDisclosureCopy {

    /// The modal's headline.
    static let title = "How the coach uses your data"

    /// The modal's opening line.
    static let intro = "Rep Today builds your daily sessions on your phone. The coach is different: it runs on "
        + "Rep Today's servers and asks an AI service to write its replies - so here's exactly what it uses."

    static let whatIsSentTitle = "What's sent to OpenAI"
    static let whatIsSent = "When you message the coach, Rep Today's server sends OpenAI, the AI service that "
        + "writes the replies, your message and your training records from your account: your recent sessions, "
        + "Outside Activities and Custom Workouts, your workout history and progress, the injury areas you've "
        + "flagged, your fitness level and Focus Areas, whether you're 18 or over, today's plan, and your "
        + "conversation with the coach. Your name, email, height and weight are never sent."

    static let leavesDeviceTitle = "What's saved"
    static let leavesDevice = "Your conversation with the coach and the Custom Workouts you accept are saved to "
        + "your Rep Today account, so the coach remembers you on any device. Deleting your account deletes them."

    static let notStoredTitle = "How it's handled"
    static let notStored = "Under its standard retention, OpenAI may keep messages and replies in abuse-monitoring "
        + "logs for up to 30 days. To help prevent abuse, a code derived from your account - never your name or "
        + "email - is sent with each message. Nothing the coach suggests changes your plan until you confirm it, "
        + "and it never gives medical advice."

    /// The primary control: an explicit acknowledgement. Tapping it is what opens the coach.
    static let acknowledge = "I understand"

    /// The secondary control: a clear, honest way to back out. Declining sends nothing; the disclosure
    /// is offered again the next time the user wants the coach.
    static let decline = "Not now"

    /// Shown in place of the chat after "Not now": nothing was sent.
    static let declined = "Nothing has been sent. The coach is ready when you are."
    static let review = "Review and continue"

    /// The Settings mirror: the same disclosure, condensed for the Privacy screen, and explicit that it is
    /// separate from the anonymous-telemetry control above it.
    static let settingsRowTitle = "How the coach uses your data"
    static let settingsFooter = "When you message the AI coach, Rep Today's server sends your message and your "
        + "training records - recent sessions, workout history, Outside Activities, Custom Workouts, flagged injury "
        + "areas, fitness level, Focus Areas, whether you're 18 or over and today's plan - to OpenAI to write the "
        + "reply. Your name, email, height and weight are never sent. OpenAI may keep messages and replies in "
        + "abuse-monitoring logs for up to 30 days. Your conversation and accepted Custom Workouts are saved to "
        + "your account and deleted with it. This is separate from the anonymous usage data above."
}

/// The versioned, pre-use consent disclosure for the AI coach (US-AC04).
///
/// Shown whenever a Premium user has not acknowledged the current contract, before any message can
/// be sent. It is a *consent* gesture, not just an FYI: the user must tap **I understand** for the
/// coach to become usable, and **Not now** backs out without sending anything. The actual send gate
/// lives in `CoachViewModel` (the send path refuses to run until consent is granted); this surface is
/// how the user reads the disclosure and makes that choice.
///
/// Presentation is owned by `CoachTabView`, which layers this over the (idle) chat surface and, on
/// acknowledgement, persists the current disclosure version on `AppState`. The same version survives
/// relaunch; account deletion or a changed contract requires acknowledgement again. Every color, font,
/// and dimension comes from `Theme`; the controls meet the 60pt active-surface touch target; the card
/// is VoiceOver-modal and Dynamic-Type friendly, and the caller stills the entrance under Reduce Motion.
struct CoachDataDisclosureView: View {
    /// Records acknowledgement of the current disclosure contract and opens the coach.
    let onAcknowledge: () -> Void

    /// Backs out without sending anything (the disclosure is offered again when the user wants the coach).
    let onDecline: () -> Void

    private struct Point: Identifiable {
        let id = UUID()
        let symbol: String
        let title: String
        let detail: String
    }

    private let points: [Point] = [
        Point(symbol: "paperplane", title: CoachDataDisclosureCopy.whatIsSentTitle, detail: CoachDataDisclosureCopy.whatIsSent),
        Point(symbol: "tray.full", title: CoachDataDisclosureCopy.leavesDeviceTitle, detail: CoachDataDisclosureCopy.leavesDevice),
        Point(symbol: "hand.raised", title: CoachDataDisclosureCopy.notStoredTitle, detail: CoachDataDisclosureCopy.notStored)
    ]

    var body: some View {
        ZStack {
            // The scrim behind the card. Hidden from VoiceOver so focus lives inside the modal; a tap
            // here is inert, keeping the two buttons the only ways out.
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

            buttons
                .padding(Theme.Spacing.lg)
        }
        .background(Theme.Colors.background)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Spacing.cardCornerRadius))
        .frame(maxWidth: 520)
        // Trap VoiceOver inside the disclosure so the coach underneath is not reachable until the user
        // has chosen - the modal semantics a system sheet would give for free.
        .accessibilityAddTraits(.isModal)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(CoachDataDisclosureCopy.title)
                .font(Theme.Typography.largeTitle)
                .foregroundStyle(Theme.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text(CoachDataDisclosureCopy.intro)
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
                Text(point.detail)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // One element per point so VoiceOver reads a whole fact at a time.
        .accessibilityElement(children: .combine)
    }

    private var buttons: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Button(action: onAcknowledge) {
                Text(CoachDataDisclosureCopy.acknowledge)
                    .font(Theme.Typography.button)
                    .frame(maxWidth: .infinity)
                    .frame(height: Theme.Spacing.workoutTouchTarget)
            }
            .accentFilledButtonStyle()
            .clipShape(RoundedRectangle(cornerRadius: Theme.Spacing.cardCornerRadius))
            .accessibilityLabel(CoachDataDisclosureCopy.acknowledge)
            .accessibilityHint("Agrees to send your messages to OpenAI and opens the coach")

            Button(action: onDecline) {
                Text(CoachDataDisclosureCopy.decline)
                    .font(Theme.Typography.button)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: Theme.Spacing.workoutTouchTarget)
            }
            .accessibilityLabel(CoachDataDisclosureCopy.decline)
            .accessibilityHint("Closes the coach without sending anything")
        }
    }
}

#Preview {
    ZStack {
        Theme.Colors.background.ignoresSafeArea()
        CoachDataDisclosureView(onAcknowledge: {}, onDecline: {})
    }
}
