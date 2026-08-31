import SwiftUI

/// The canonical copy for the coach data disclosure (US-AC04), in one place so the pre-use modal
/// (`CoachDataDisclosureView`) and the Settings entry (`SettingsView`) say the same thing and can
/// never drift. Tests assert against these constants, so a wording change is a single edit.
///
/// The disclosure exists because the AI coach is the one honest break in Rep Today's on-device privacy
/// posture: everything else - your history, your sessions, the engine that builds them - stays on the
/// device, but a coach answer is written by OpenAI, so in the moment of a call your message *and* a
/// short summary of your training context leave the device. The copy names that plainly and up front,
/// never buried in fine print, and never dark-patterned into pretending it does not happen.
enum CoachDataDisclosureCopy {

    /// The modal's headline.
    static let title = "How the coach uses your messages"

    /// The modal's opening line: it frames the coach as the deliberate exception to on-device privacy.
    static let intro = "Rep Today builds every workout on your device. The coach is the one part that asks a "
        + "server for help - so here's exactly what leaves your phone when you chat with it."

    /// The three disclosure points, each a concrete fact about what happens to your content.
    static let whatIsSentTitle = "What's sent"
    static let whatIsSent = "When you send a question, your message and a short summary of your training - "
        + "your current movements, how consistent you've been, and your phase - go to OpenAI, the AI service that "
        + "writes the reply."

    static let leavesDeviceTitle = "It leaves your device - just for this"
    static let leavesDevice = "This is the one moment Rep Today sends your content off your phone. Your full "
        + "workout history and everything else stay on the device, as they always have."

    static let notStoredTitle = "How it's handled"
    static let notStored = "Rep Today's proxy doesn't store your message, training summary, or reply. Under "
        + "its standard retention, OpenAI may keep that content in abuse-monitoring logs for up to 30 days. "
        + "Rep Today doesn't send your name, email, or account identity with it."

    /// The primary control: an explicit acknowledgement. Tapping it is what opens the coach.
    static let acknowledge = "I understand"

    /// The secondary control: a clear, honest way to back out. Declining sends nothing and leaves the
    /// coach unused - the user can open it again later and will see this disclosure again.
    static let decline = "Not now"

    /// The Settings mirror: the same disclosure, condensed for the Privacy screen. It states the same
    /// facts and makes the separation from the anonymous-telemetry control above it explicit, so the two
    /// privacy choices are never confused for one.
    static let settingsRowTitle = "How the coach uses your data"
    static let settingsFooter = "When you chat with the AI coach, your message and a short training summary "
        + "are sent to OpenAI to answer. Rep Today's proxy doesn't store them. OpenAI may retain them and the "
        + "reply in abuse-monitoring logs for up to 30 days under standard retention. No Rep Today identity is "
        + "sent. This is separate from the anonymous usage data above."
}

/// The one-time, pre-use consent disclosure for the AI coach (US-AC04).
///
/// Shown the first time a Premium user opens the coach, before any message can be sent. It is a
/// *consent* gesture, not just an FYI: the user must tap **I understand** for the coach to become
/// usable, and **Not now** backs out without sending anything. The actual send gate lives in
/// `CoachViewModel` (the send path refuses to run until consent is granted); this surface is how the
/// user reads the disclosure and makes that choice.
///
/// Presentation is owned by `CoachView`, which layers this over the (idle) chat surface and, on
/// acknowledgement, persists the one-shot flag on `AppState` so it is shown at most once. Every color,
/// font, and dimension comes from `Theme`; the controls meet the 60pt active-surface touch target; the
/// card is VoiceOver-modal and Dynamic-Type friendly, and the caller stills the entrance under Reduce
/// Motion.
struct CoachDataDisclosureView: View {
    /// Records acknowledgement (opens the coach and persists the one-shot).
    let onAcknowledge: () -> Void

    /// Backs out without sending anything (dismisses the coach; the disclosure returns on a later open).
    let onDecline: () -> Void

    private struct Point: Identifiable {
        let id = UUID()
        let symbol: String
        let title: String
        let detail: String
    }

    private let points: [Point] = [
        Point(symbol: "paperplane", title: CoachDataDisclosureCopy.whatIsSentTitle, detail: CoachDataDisclosureCopy.whatIsSent),
        Point(symbol: "iphone.and.arrow.forward", title: CoachDataDisclosureCopy.leavesDeviceTitle, detail: CoachDataDisclosureCopy.leavesDevice),
        Point(symbol: "lock.slash", title: CoachDataDisclosureCopy.notStoredTitle, detail: CoachDataDisclosureCopy.notStored)
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
            .buttonStyle(.borderedProminent)
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
