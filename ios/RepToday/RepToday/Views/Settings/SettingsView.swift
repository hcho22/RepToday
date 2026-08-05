import SwiftUI

/// The app's Settings screen, pushed from the Profile tab.
///
/// It exists because US-T06 needs a reachable, clearly-labelled home for the anonymous-telemetry
/// opt-out, and burying that control would defeat the point of an opt-out. It is deliberately a real
/// sectioned Settings surface rather than an inline toggle on the Profile placeholder, so a later,
/// broader Profile/Settings story **extends** it - another `Section` - rather than replacing it.
/// Privacy is its only section today; nothing else about Profile changes here.
struct SettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState

        List {
            Section {
                Toggle(isOn: $appState.analyticsEnabled) {
                    Text(Self.toggleTitle)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.textPrimary)
                }
                .tint(Theme.Colors.accent)
                .frame(minHeight: Theme.Spacing.minTouchTarget)
                .accessibilityLabel(Self.toggleTitle)
                .accessibilityHint(Self.toggleHint)

                Link(destination: LegalLinks.privacyPolicy) {
                    HStack(spacing: Theme.Spacing.sm) {
                        Text("Privacy Policy")
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.Colors.accent)
                        Spacer(minLength: 0)
                        Image(systemName: "arrow.up.right.square")
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    .frame(minHeight: Theme.Spacing.minTouchTarget)
                }
                .accessibilityLabel("Privacy Policy")
                .accessibilityHint("Opens Rep Today's privacy policy in your browser")
            } header: {
                Text("Privacy")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            } footer: {
                Text(Self.explanation)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .listRowBackground(Theme.Colors.surface)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.Colors.background)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// The one label the toggle is known by - to a reader, to VoiceOver, and to the XCUITest suite
    /// that presses it - so the three cannot drift apart.
    static let toggleTitle = "Share anonymous usage data"

    /// What activating the switch *does*, which is what a VoiceOver hint is for. It deliberately
    /// does not restate `explanation`: that sentence is the section's footer, which VoiceOver reads
    /// once, and repeating it here would make the screen speak the whole paragraph twice in a row.
    /// State-neutral because the switch already vends its own on/off value.
    static let toggleHint = "Turns sharing anonymous usage data on or off"

    /// Honest and identity-framed, never dark-patterned: it says what is collected, what it is for,
    /// and what it is *not* tied to, without arguing the user out of turning it off.
    ///
    /// It renders as the Privacy section's **footer** - where iOS natively puts explanatory text,
    /// where VoiceOver reads it exactly once, and where it does not look like another tappable row.
    static let explanation = """
        Anonymous usage data helps us see whether Rep Today is working. It's counted against a \
        random per-install number - never your name, your email, or your device.
        """
}

#Preview {
    NavigationStack {
        SettingsView()
    }
    .environment(\.services, ServiceContainer.mock())
    .environment(AppState.preview(isOnboarded: true, selectedTab: .profile))
}
