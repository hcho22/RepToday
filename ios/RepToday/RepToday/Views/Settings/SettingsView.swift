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
    @Environment(\.services) private var services

    /// The account-deletion flow's view model (US-AD01/US-AD04/US-AD05). Built lazily on first use
    /// from the environment (services + `AppState`), which a `@State` default cannot capture at init.
    @State private var deletion: AccountDeletionViewModel?

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

            // US-AC04: the coach data disclosure, mirrored into Settings so the same facts are
            // documented where a user looks for privacy choices. It is deliberately its **own** section,
            // separate from the telemetry opt-out above - it is informational (the consent gesture is
            // the one-time acknowledgement at first coach use, and using the coach at all is the opt-in),
            // and it neither reads nor writes the telemetry flag. The footer states the same disclosure
            // the pre-use modal shows.
            Section {
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .foregroundStyle(Theme.Colors.textSecondary)
                    Text(CoachDataDisclosureCopy.settingsRowTitle)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Spacer(minLength: 0)
                }
                .frame(minHeight: Theme.Spacing.minTouchTarget)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(CoachDataDisclosureCopy.settingsRowTitle)
            } header: {
                Text("AI Coach")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            } footer: {
                Text(CoachDataDisclosureCopy.settingsFooter)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .listRowBackground(Theme.Colors.surface)

            // US-AD01: the mandatory account-deletion path (App Store Guideline 5.1.1(v)). A
            // destructive, clearly-labelled row in its own section, so it is findable in one tap from
            // the Profile tab's Settings and never mistaken for a benign control.
            Section {
                Button(role: .destructive) {
                    let model = deletionModel()
                    Task { await model.deleteAccountTapped() }
                } label: {
                    HStack(spacing: Theme.Spacing.sm) {
                        Image(systemName: "trash")
                        Text(Self.deleteAccountTitle)
                            .font(Theme.Typography.body)
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(Theme.Colors.danger)
                    .frame(minHeight: Theme.Spacing.minTouchTarget)
                }
                .accessibilityLabel(Self.deleteAccountTitle)
                .accessibilityHint("Permanently deletes your profile and workout history")
            } header: {
                Text("Account")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            } footer: {
                Text(Self.deleteAccountFooter)
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
        // US-AD04: the confirmation naming exactly what is destroyed. The destructive button carries
        // `role: .destructive` so it renders red and is *not* the default; `.cancel` is. The message
        // names the Apple sign-in link only when this account used it (US-AD05), resolved before the
        // alert is presented.
        .alert(
            "Delete your account?",
            isPresented: Binding(
                get: { deletion?.isConfirmationPresented ?? false },
                set: { deletion?.isConfirmationPresented = $0 }
            )
        ) {
            Button("Delete Account", role: .destructive) {
                if let deletion { Task { await deletion.confirmDeletion() } }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(deletion?.usedAppleCredential == true ? Self.confirmMessageApple : Self.confirmMessageLocal)
        }
        // An honest failure surface: if the teardown throws, the routing reset (its last step) never
        // ran, so the user is still here and onboarded. Tell them deletion did not complete rather than
        // letting the confirmation dismiss silently. The teardown is idempotent, so "Try Again" is safe.
        .alert(
            "Couldn't delete your account",
            isPresented: Binding(
                get: { deletion?.isFailureAlertPresented ?? false },
                set: { deletion?.isFailureAlertPresented = $0 }
            )
        ) {
            Button("Try Again") {
                if let deletion { Task { await deletion.confirmDeletion() } }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(Self.deleteFailureMessage)
        }
    }

    /// Builds the deletion view model on first use and caches it. `@State` cannot capture the
    /// environment at init, so it is created here from the live `services` and `AppState`.
    private func deletionModel() -> AccountDeletionViewModel {
        if let deletion { return deletion }
        let model = AccountDeletionViewModel(
            accountDeletionService: services.accountDeletionService,
            authService: services.authService,
            appState: appState
        )
        deletion = model
        return model
    }

    /// The one label the Delete Account control is known by - to a reader, to VoiceOver, and to the
    /// XCUITest that presses it (US-AD01) - so they cannot drift apart.
    static let deleteAccountTitle = "Delete Account"

    /// The section footer. Stays generic - it does not assert a Sign in with Apple link, which a
    /// local-only account does not have; the confirmation alert names that only when it applies.
    static let deleteAccountFooter = """
        Permanently deletes your profile and workout history from this device and iCloud. This \
        can't be undone.
        """

    /// The confirmation body for an account that used Sign in with Apple (US-AD04/US-AD05): it names
    /// the Apple link among what is destroyed.
    static let confirmMessageApple = """
        This permanently deletes your profile, your workout history, and your Sign in with Apple \
        link on this device. This can't be undone.
        """

    /// The failure body shown when the teardown throws. Honest about what happened - the teardown
    /// deletes durable records first and saves each step, so a late-step throw may already have
    /// removed some data; it does not claim anything is still intact - and points at the safe next
    /// action, since the teardown is idempotent and a retry completes it.
    static let deleteFailureMessage = """
        Something went wrong and your account may not be fully deleted. Please try again.
        """

    /// The confirmation body for the local-only account (never signed in with Apple): identical, minus
    /// the Apple link it does not have.
    static let confirmMessageLocal = """
        This permanently deletes your profile and your workout history on this device. This can't \
        be undone.
        """

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
