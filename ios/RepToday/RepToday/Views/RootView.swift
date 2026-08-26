import SwiftUI
import UIKit

/// Top-level router for the app shell.
struct RootView: View {
    @Environment(\.services) private var services
    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Drives the one-time Strength-Phase graduation reveal (US-SP06). Set once, on app open, and only
    /// when the user has just earned the Strength Phase and has not yet been congratulated for it.
    @State private var showGraduation = false

    var body: some View {
        @Bindable var appState = appState

        ZStack {
            Group {
                if appState.isOnboarded {
                    MainTabsView(selectedTab: $appState.selectedTab)
                } else {
                    // The minimal v6 onboarding flow (US-I01). On completion it has already saved the
                    // user and seeded the cold-start policy, so the router only flips into the main app.
                    OnboardingView(services: services) {
                        appState.isOnboarded = true
                        appState.selectedTab = .home
                    }
                }
            }

            // The Strength-Phase graduation reveal (US-SP06) rides above the whole app shell as its own
            // overlay layer rather than a `.sheet`, so the entrance animation can be stilled under
            // Reduce Motion and the tabs underneath keep running - the reveal is purely celebratory and
            // never gates the core loop. Hosted here, at the router, because it must fire "on first app
            // open" regardless of which tab the user lands on, and this is the one surface that survives
            // tab teardown (the same reason the US-AD05 alert lives here).
            if showGraduation {
                StrengthGraduationRevealView(onDismiss: dismissGraduation)
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        // On app open, ask the deterministic `PhaseEvaluator` whether the user has just crossed into
        // the earned Strength Phase (computed from real logs, never the persisted `user.phase`), and
        // reveal the graduation once at the crossing. The persisted, ratcheting `lastCelebratedPhase`
        // is flipped the moment we decide to show it - not on dismissal - so a force-quit while it is
        // up can never bring it back on the next open, and it never re-fires after a relaunch.
        .task { await revealGraduationIfEarned() }
        // Debug-only, and inert unless the US-T06 probe launch argument is set: the HUD an
        // out-of-process XCUITest reads the telemetry-attempt count from. A Release build compiles
        // nothing here.
        .telemetryProbeHUD()
        // US-AD05: the post-deletion Apple-ID guidance. Hosted here, at the router, because account
        // deletion routes back to onboarding and tears down the Settings screen that triggered it -
        // so the alert has to live above that transition to survive it. Shown only when the deleted
        // account used Sign in with Apple (`AccountDeletionViewModel` arms the flag only in that case,
        // and only on a successful teardown). Option (a): on-device guidance, no token revoke.
        .alert("One more step", isPresented: $appState.showAppleSignOutGuidance) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
                appState.showAppleSignOutGuidance = false
            }
            Button("Done", role: .cancel) {
                appState.showAppleSignOutGuidance = false
            }
        } message: {
            Text(
                "Your Rep Today data is deleted. To also stop using your Apple ID with Rep Today, "
                + "open Settings, tap your name, then Sign-In & Security \u{2192} Sign in with Apple, "
                + "and choose Rep Today."
            )
        }
    }

    /// Reveal the Strength-Phase graduation (US-SP06) if - and only if - the user has just earned it
    /// and has not yet been congratulated. Computes the earned phase from real logs through the same
    /// `PhaseEvaluator` the gate uses, then flips the persisted one-shot flag the moment it decides to
    /// show, so the reveal fires exactly once at the crossing and never again (a force-quit while it is
    /// up cannot re-arm it, and it never re-fires on a later launch). A no-op during onboarding and for
    /// a user who has not earned Strength or has already seen it.
    @MainActor
    private func revealGraduationIfEarned() async {
        guard appState.isOnboarded, !appState.hasCelebratedStrengthGraduation else { return }

        let viewModel = StrengthGraduationViewModel(services: services)
        await viewModel.evaluate()
        guard viewModel.earnedStrength else { return }

        // Ratchet the celebrated phase before presenting, so the reveal can never re-fire even if the
        // user force-quits while it is up.
        appState.markStrengthGraduationCelebrated()
        if reduceMotion {
            showGraduation = true
        } else {
            withAnimation(.easeOut(duration: 0.25)) { showGraduation = true }
        }
    }

    /// Dismiss the graduation reveal, honoring Reduce Motion the same way the entrance does. The
    /// one-shot flag is already flipped (at presentation), so this only has to take the overlay down.
    private func dismissGraduation() {
        if reduceMotion {
            showGraduation = false
        } else {
            withAnimation(.easeIn(duration: 0.2)) { showGraduation = false }
        }
    }
}

private struct MainTabsView: View {
    @Environment(\.services) private var services
    @Binding var selectedTab: AppTab

    var body: some View {
        TabView(selection: $selectedTab) {
            // The Ready Screen the app opens to (US-I01), with today's session already generated.
            // Epic J layers the duration chip and personalization surfaces onto this same view.
            ReadyView(services: services)
                .tag(AppTab.home)
                .tabItem {
                    Label("Today", systemImage: "house.fill")
                }

            // The reflection surface (US-M01): the calendar, the Consistency Score trend, and the
            // earned longest-run pride. US-M02 layers pillar balance, chain position, and bests on top.
            ProgressTabView(services: services)
                .tag(AppTab.progress)
                .tabItem {
                    Label("Progress", systemImage: "chart.line.uptrend.xyaxis")
                }

            // Still the placeholder it has always been (US-A05), with one real destination hung off
            // it: Settings, which US-T06 needed as a reachable home for the telemetry opt-out. The
            // broader Profile story replaces the placeholder around it, not the Settings screen.
            ProfileTabView()
                .tag(AppTab.profile)
                .tabItem {
                    Label("Profile", systemImage: "person.crop.circle.fill")
                }
        }
        // Request HealthKit share access once, up front (US-N03), at a calm moment rather than mid-loop.
        // Best-effort and non-blocking: the prompt only appears the first time (the request is idempotent
        // once answered), and the core loop never waits on it. `saveWorkoutLog` then writes each completed
        // session only when access was granted.
        .task {
            _ = try? await services.healthKitService.requestAuthorization()
        }
    }
}

/// The Profile tab: the existing placeholder, plus a navigation row to the real Settings screen.
///
/// The row is a plain, prominent list-style row rather than a toolbar gear, because the one control
/// behind it - the anonymous-usage-data opt-out - has to be *found* to be worth anything.
private struct ProfileTabView: View {
    @Environment(\.services) private var services

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Colors.background
                    .ignoresSafeArea()

                VStack(spacing: Theme.Spacing.lg) {
                    PlaceholderTabView(
                        icon: "person.crop.circle.fill",
                        title: "Profile",
                        subtitle: "Keep your movement basics current."
                    )

                    VStack(spacing: Theme.Spacing.md) {
                        // US-AC03: the premium gate + upsell entry point for the talking coach
                        // (US-AC02). A Premium subscriber navigates into `CoachView`; a free user's tap
                        // opens the existing paywall carrying the `coach_upsell` entry point. The gate
                        // is best-effort and never touches the core loop.
                        CoachEntryRow(services: services)

                        NavigationLink {
                            SettingsView()
                        } label: {
                            ProfileRowLabel(icon: "gearshape.fill", title: "Settings")
                        }
                        .accessibilityLabel("Settings")
                        .accessibilityHint("Privacy and anonymous usage data")
                    }
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.bottom, Theme.Spacing.xl)
                }
            }
        }
    }
}

/// A prominent list-style navigation row on the Profile tab: an icon, a title, an optional trailing
/// badge, and a chevron. Shared so the Coach and Settings rows stay visually identical (and so the
/// US-AC03 gate can reuse it for both the Premium and upsell states). Internal, not private, so the
/// coach entry row in its own file can render an identical row.
struct ProfileRowLabel: View {
    let icon: String
    let title: String
    /// An optional short trailing tag (e.g. "Premium" on the coach upsell row). `nil` renders no badge.
    var badge: String?

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: icon)
                .foregroundStyle(Theme.Colors.accent)
            Text(title)
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.textPrimary)
            Spacer(minLength: 0)
            if let badge {
                Text(badge)
                    .font(Theme.Typography.caption.weight(.semibold))
                    .foregroundStyle(Theme.Colors.accent)
                    .padding(.horizontal, Theme.Spacing.sm)
                    .padding(.vertical, Theme.Spacing.xs)
                    .background(
                        Theme.Colors.accent.opacity(0.12),
                        in: Capsule()
                    )
            }
            Image(systemName: "chevron.right")
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .padding(.horizontal, Theme.Spacing.md)
        // The standard 56pt control height, which already clears the 44pt target.
        .frame(height: Theme.Spacing.buttonHeight)
        .background(
            Theme.Colors.surface,
            in: RoundedRectangle(cornerRadius: Theme.Spacing.cardCornerRadius)
        )
    }
}

private struct PlaceholderTabView: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(Theme.Colors.accent)
                .frame(minWidth: Theme.Spacing.minTouchTarget, minHeight: Theme.Spacing.minTouchTarget)

            Text(title)
                .font(Theme.Typography.title)
                .foregroundStyle(Theme.Colors.textPrimary)

            Text(subtitle)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.Spacing.lg)
        }
        .padding(Theme.Spacing.lg)
        // Fills whatever it is given and centres inside it, which is what pins the Settings row
        // below it to the bottom of the tab. The enclosing screen owns the background.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    RootView()
        .environment(\.services, ServiceContainer.mock())
        .environment(AppState.preview())
}
