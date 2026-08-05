import SwiftUI

/// Top-level router for the app shell.
struct RootView: View {
    @Environment(\.services) private var services
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState

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
        // Debug-only, and inert unless the US-T06 probe launch argument is set: the HUD an
        // out-of-process XCUITest reads the telemetry-attempt count from. A Release build compiles
        // nothing here.
        .telemetryProbeHUD()
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

                    NavigationLink {
                        SettingsView()
                    } label: {
                        HStack(spacing: Theme.Spacing.md) {
                            Image(systemName: "gearshape.fill")
                                .foregroundStyle(Theme.Colors.accent)
                            Text("Settings")
                                .font(Theme.Typography.headline)
                                .foregroundStyle(Theme.Colors.textPrimary)
                            Spacer(minLength: 0)
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
                    .accessibilityLabel("Settings")
                    .accessibilityHint("Privacy and anonymous usage data")
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.bottom, Theme.Spacing.xl)
                }
            }
        }
    }
}

private struct PlaceholderTabView: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        ZStack {
            Theme.Colors.background
                .ignoresSafeArea()

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
        }
    }
}

#Preview {
    RootView()
        .environment(\.services, ServiceContainer.mock())
        .environment(AppState.preview())
}
