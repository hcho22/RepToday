import SwiftUI
import UIKit

/// Top-level router for the app shell.
struct RootView: View {
    @Environment(\.services) private var services
    @Environment(AppState.self) private var appState
    /// Keeps the device's data flowing to the account (M3). Optional so hosted test surfaces that build
    /// `RootView` without one still render; the app always provides it.
    @Environment(AccountSyncCoordinator.self) private var syncCoordinator: AccountSyncCoordinator?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Drives the one-time Strength-Phase graduation reveal (US-SP06): the graduating user's fitness
    /// level, which decides what the reveal says opens up, or `nil` while it is not shown. Set once, on
    /// app open, and only when the user has just earned the Strength Phase and has not yet been
    /// congratulated for it.
    @State private var graduationLevel: FitnessLevel?
    /// A graduation reveal decided on app open but held until the Welcome Page is dismissed, so the two
    /// never stack. Its one-shot flag flips only when it is actually shown.
    @State private var pendingGraduationLevel: FitnessLevel?
    @State private var appOpenReconciliationComplete = false

    var body: some View {
        @Bindable var appState = appState

        ZStack {
            Group {
                if appState.isOnboarded && appState.needsAccountSignIn {
                    // A user who onboarded before accounts signs in once before anything else (US-AU04).
                    // Their data is untouched until then, and moves to the account afterwards.
                    AccountRequiredView(auth: services.accountAuthService) { identity in
                        try linkAccount(identity)
                    }
                    .transition(.opacity)
                } else if appState.isOnboarded {
                    if appOpenReconciliationComplete {
                        // Built behind the Welcome Page on a cold launch, so Today loads while the user
                        // reads it (US-HO01).
                        MainTabsView(selectedTab: $appState.selectedTab, isRevealed: !appState.isWelcomePending)
                    } else if !appState.isWelcomePending {
                        // Only straight after onboarding, which lands on Today without a Welcome Page.
                        ProgressView()
                            .controlSize(.large)
                            .accessibilityLabel("Preparing today’s session")
                    }
                } else {
                    // The minimal v6 onboarding flow (US-I01), ending at "Save your plan" (US-AU02). On
                    // completion the signed-in account's plan is already on the phone, so the router links
                    // the account - before marking the user onboarded, so they are never mistaken for a
                    // pre-account user - and flips into the main app. A freshly onboarded user lands on
                    // Today: the Welcome Page is for cold launches.
                    OnboardingView(services: services) { identity in
                        try linkAccount(identity)
                        appOpenReconciliationComplete = false
                        appState.markWelcomeSeen()
                        appState.isOnboarded = true
                        appState.selectedTab = .home
                    }
                }
            }

            // The Welcome Page (US-HO01, decision 19) on every cold launch after onboarding. It replaces
            // the launch spinner: the app-open reconciliation and Today's load run behind it, and "Let's
            // go" waits only for the shell to be ready.
            if appState.isOnboarded && !appState.needsAccountSignIn && appState.isWelcomePending {
                WelcomePageView(
                    viewModel: WelcomeViewModel(services: services),
                    isReady: appOpenReconciliationComplete,
                    onContinue: dismissWelcome
                )
                .transition(.opacity)
                .zIndex(0.5)
            }

            // The Strength-Phase graduation reveal (US-SP06) rides above the whole app shell as its own
            // overlay layer rather than a `.sheet`, so the entrance animation can be stilled under
            // Reduce Motion and the tabs underneath keep running - the reveal is purely celebratory and
            // never gates the core loop. Hosted here, at the router, because it must fire "on first app
            // open" regardless of which tab the user lands on, and this is the one surface that survives
            // tab teardown (the same reason the US-AD05 alert lives here).
            if let graduationLevel {
                StrengthGraduationRevealView(level: graduationLevel, onDismiss: dismissGraduation)
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        // On app open, reconcile any earned-but-not-yet-persisted Strength transition, then reveal the
        // graduation once at the crossing. The persisted, ratcheting `lastCelebratedPhase` is flipped
        // the moment we decide to show it - not on dismissal - so a force-quit while it is up can never
        // bring it back on the next open, and it never re-fires after a relaunch.
        .task(id: appState.isOnboarded) { await prepareAppOpen() }
        .onChange(of: appState.isWelcomePending) { _, pending in
            if !pending { presentGraduationIfReady() }
        }
        .onChange(of: appState.needsAccountSignIn) { _, needed in
            if !needed { presentGraduationIfReady() }
        }
        // Debug-only, and inert unless the US-T06 probe launch argument is set: the HUD an
        // out-of-process XCUITest reads the telemetry-attempt count from. A Release build compiles
        // nothing here.
        .telemetryProbeHUD()
        // US-AD05: the post-deletion Apple-ID guidance, and (US-AU05) the note that the server is still
        // removing the sign-in when Clerk could not be reached. Hosted here, at the router, because
        // account deletion routes back to onboarding and tears down the Settings screen that triggered
        // it - so the alert has to live above that transition to survive it. The Apple guidance shows
        // only when the deleted account used Sign in with Apple (`AccountDeletionViewModel` arms the flag
        // only in that case, and only on a successful teardown). Option (a): on-device guidance, no
        // token revoke.
        .alert(
            Self.deletionNoticeTitle(appleGuidance: appState.showAppleSignOutGuidance),
            isPresented: Binding(
                get: { appState.showAppleSignOutGuidance || appState.showAccountDeletionUnderWay },
                set: { presented in
                    if !presented {
                        appState.showAppleSignOutGuidance = false
                        appState.showAccountDeletionUnderWay = false
                    }
                }
            )
        ) {
            if appState.showAppleSignOutGuidance {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                    appState.showAppleSignOutGuidance = false
                    appState.showAccountDeletionUnderWay = false
                }
            }
            Button("Done", role: .cancel) {
                appState.showAppleSignOutGuidance = false
                appState.showAccountDeletionUnderWay = false
            }
        } message: {
            Text(Self.deletionNoticeMessage(
                appleGuidance: appState.showAppleSignOutGuidance,
                deletionUnderWay: appState.showAccountDeletionUnderWay
            ))
        }
    }

    static func deletionNoticeTitle(appleGuidance: Bool) -> String {
        appleGuidance ? "One more step" : "Deletion under way"
    }

    /// What the post-deletion alert says: that the data is deleted, or - when the server has not
    /// confirmed the deletion complete - that it is gone from this phone and the account's deletion
    /// finishes on its own; and the Apple ID step when it applies.
    static func deletionNoticeMessage(appleGuidance: Bool, deletionUnderWay: Bool) -> String {
        var message = deletionUnderWay
            ? "Your Rep Today data is deleted from this phone. Your account is being deleted, and that finishes on its own - there's nothing more you need to do."
            : "Your Rep Today data is deleted."
        if appleGuidance {
            message += " To also stop using your Apple ID with Rep Today, "
                + "open Settings, tap your name, then Sign-In & Security \u{2192} Sign in with Apple, "
                + "and choose Rep Today."
        }
        return message
    }

    /// Reconcile the persisted earned phase before phase-dependent tabs are constructed, then reveal
    /// the Strength-Phase graduation (US-SP06) if the user has earned it and has not been congratulated.
    /// Reconciliation still runs after a past celebration because that presentation marker is never
    /// phase authority. The marker flips the moment the reveal is shown, so force-quitting cannot re-arm
    /// it. During onboarding there is no reconciliation, and an unearned or already-celebrated user sees
    /// no reveal.
    @MainActor
    private func prepareAppOpen() async {
        guard appState.isOnboarded else {
            appOpenReconciliationComplete = true
            return
        }

        let viewModel = StrengthGraduationViewModel(services: services)
        await viewModel.evaluate()
        guard appState.isOnboarded, !Task.isCancelled else { return }
        appOpenReconciliationComplete = true
        guard !appState.hasCelebratedStrengthGraduation, viewModel.earnedStrength,
              let level = viewModel.fitnessLevel else { return }
        pendingGraduationLevel = level
        presentGraduationIfReady()
    }

    /// Links the account the user just signed in to, through the sync coordinator when there is one.
    private func linkAccount(_ identity: AccountIdentity) throws {
        if let syncCoordinator {
            try syncCoordinator.linkAccount(identity)
        } else {
            try appState.linkAccount(identity)
        }
    }

    /// Shows a decided graduation reveal once nothing else is on top: the Welcome Page goes first.
    private func presentGraduationIfReady() {
        guard let level = pendingGraduationLevel, !appState.isWelcomePending, !appState.needsAccountSignIn else { return }
        pendingGraduationLevel = nil
        // Ratchet the celebrated phase as it is presented, so the reveal can never re-fire even if the
        // user force-quits while it is up.
        appState.markStrengthGraduationCelebrated()
        if reduceMotion {
            graduationLevel = level
        } else {
            withAnimation(.easeOut(duration: 0.25)) { graduationLevel = level }
        }
    }

    /// "Let's go" on the Welcome Page: reveal Today - always Today, whichever tab was last open. Any
    /// graduation reveal that was waiting follows (`onChange(of: isWelcomePending)`).
    private func dismissWelcome() {
        appState.selectedTab = .home
        if reduceMotion {
            appState.markWelcomeSeen()
        } else {
            withAnimation(.easeInOut(duration: 0.25)) { appState.markWelcomeSeen() }
        }
    }

    /// Dismiss the graduation reveal, honoring Reduce Motion the same way the entrance does. The
    /// one-shot flag is already flipped (at presentation), so this only has to take the overlay down.
    private func dismissGraduation() {
        if reduceMotion {
            graduationLevel = nil
        } else {
            withAnimation(.easeIn(duration: 0.2)) { graduationLevel = nil }
        }
    }
}

private struct MainTabsView: View {
    @Environment(\.services) private var services
    @Binding var selectedTab: AppTab
    /// False while the Welcome Page still covers the tabs, so nothing here prompts the user before
    /// they reach Today.
    let isRevealed: Bool

    init(selectedTab: Binding<AppTab>, isRevealed: Bool) {
        _selectedTab = selectedTab
        self.isRevealed = isRevealed
        // Inactive tabs in `text3` (DESIGN "Tab bar"); the active one takes the `sun` tint below.
        UITabBar.appearance().unselectedItemTintColor = UIColor(Theme.Colors.text3)
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            // The Ready Screen the app opens to (US-I01), with today's session already generated.
            // Epic J layers the duration chip and personalization surfaces onto this same view.
            ReadyView(services: services)
                .tag(AppTab.home)
                .tabItem {
                    Label { Text("Today") } icon: { AppIcon.today.fixedImage }
                }

            // The Coach (M4, US-CA06, decision 28): the premium agent, full screen, with its persistent
            // conversation, quick actions and Custom Workout cards. Free users see a preview and the
            // paywall; the tab itself never gates the core loop.
            CoachTabView(services: services)
                .tag(AppTab.coach)
                .tabItem {
                    Label { Text("Coach") } icon: { AppIcon.coach.fixedImage }
                }

            // The reflection surface (US-M01): the calendar, the Consistency Score trend, and the
            // earned longest-run pride. US-M02 layers pillar balance, chain position, and bests on top.
            ProgressTabView(services: services)
                .tag(AppTab.progress)
                .tabItem {
                    Label { Text("Progress") } icon: { AppIcon.progress.fixedImage }
                }

            // Still the placeholder it has always been (US-A05), with one real destination hung off
            // it: Settings, which US-T06 needed as a reachable home for the telemetry opt-out. The
            // broader Profile story replaces the placeholder around it, not the Settings screen.
            ProfileTabView()
                .tag(AppTab.profile)
                .tabItem {
                    Label { Text("Profile") } icon: { AppIcon.profile.fixedImage }
                }
        }
        // The tab bar (DESIGN "Tab bar"): the custom icons, `sun` for the active tab, `text3` for the rest,
        // on `surface1`. The system bar keeps its own accessibility and large content viewer.
        .tint(Theme.Colors.sun)
        // Request HealthKit share access once, up front (US-N03), at a calm moment rather than mid-loop.
        // Best-effort and non-blocking: the prompt only appears the first time (the request is idempotent
        // once answered), and the core loop never waits on it. `saveWorkoutLog` then writes each completed
        // session only when access was granted.
        .task(id: isRevealed) {
            guard isRevealed else { return }
            _ = try? await services.healthKitService.requestAuthorization()
        }
    }
}

/// The Profile tab: its header, plus navigation rows to Account and the real Settings screen. (The Coach
/// has its own tab since M4.)
///
/// Settings is a plain, prominent row rather than a toolbar gear, because the one control behind it - the
/// anonymous-usage-data opt-out - has to be *found* to be worth anything.
struct ProfileTabView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    ProfileHeader(title: "Profile", subtitle: "Keep your movement basics current.")

                    RowGroup {
                        VStack(spacing: 0) {
                            NavigationLink {
                                AccountView()
                            } label: {
                                SettingsValueRowLabel(icon: .profile, title: "Account")
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Account")
                            .accessibilityHint("Your account and what is saved to it")

                            GroupSeparator()

                            NavigationLink {
                                SettingsView()
                            } label: {
                                SettingsValueRowLabel(icon: .settings, title: "Settings")
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Settings")
                            .accessibilityHint("Privacy and anonymous usage data")
                        }
                        .padding(.vertical, Theme.Spacing.xs)
                    }
                }
                .padding(.horizontal, Theme.Spacing.screenMargin)
                .padding(.top, Theme.Spacing.lg)
                .padding(.bottom, Theme.Spacing.xl)
            }
            .scrollBounceBehavior(.basedOnSize)
            .background(Theme.Colors.background.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .statusBarBacking()
        }
    }
}

/// The Profile tab's header: the `sun` disc with the profile icon, the screen title in Display M and its
/// subtitle. At accessibility text sizes the title moves under the disc so it keeps the full width.
private struct ProfileHeader: View {
    let title: String
    let subtitle: String

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Spacing.md))
            : AnyLayout(HStackLayout(alignment: .center, spacing: Theme.Spacing.mlg))
        layout {
            ZStack {
                Circle().fill(Theme.Colors.sun)
                IconView(icon: .profile, size: 40)
                    .foregroundStyle(Theme.Colors.onAccent)
            }
            .frame(width: 84, height: 84)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(title)
                    .cappedDisplayFont(size: 44)
                    .foregroundStyle(Theme.Colors.text1)
                    .fixedSize(horizontal: false, vertical: true)
                Text(subtitle)
                    .font(Theme.Typography.callout)
                    .foregroundStyle(Theme.Colors.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

#Preview {
    RootView()
        .environment(\.services, ServiceContainer.mock())
        .environment(AppState.preview())
}
