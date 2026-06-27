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
                OnboardingPlaceholderView {
                    appState.isOnboarded = true
                    appState.selectedTab = .home
                }
            }
        }
    }
}

private struct OnboardingPlaceholderView: View {
    let completeOnboarding: () -> Void

    var body: some View {
        ZStack {
            Theme.Colors.background
                .ignoresSafeArea()

            VStack(spacing: Theme.Spacing.lg) {
                Image(systemName: "figure.run")
                    .font(.system(size: 48, weight: .bold))
                    .foregroundStyle(Theme.Colors.accent)

                VStack(spacing: Theme.Spacing.sm) {
                    Text("FitSnack")
                        .font(Theme.Typography.largeTitle)
                        .foregroundStyle(Theme.Colors.textPrimary)

                    Text("A few minutes is enough.")
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }

                Button(action: completeOnboarding) {
                    Text("Start")
                        .font(Theme.Typography.button)
                        .frame(maxWidth: .infinity)
                        .frame(height: Theme.Spacing.buttonHeight)
                }
                .buttonStyle(.borderedProminent)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Spacing.cardCornerRadius))
                .padding(.top, Theme.Spacing.sm)
            }
            .padding(Theme.Spacing.lg)
        }
    }
}

private struct MainTabsView: View {
    @Binding var selectedTab: AppTab

    var body: some View {
        TabView(selection: $selectedTab) {
            PlaceholderTabView(
                icon: "house.fill",
                title: "Today",
                subtitle: "A short session is ready when you are."
            )
            .tag(AppTab.home)
            .tabItem {
                Label("Today", systemImage: "house.fill")
            }

            PlaceholderTabView(
                icon: "chart.line.uptrend.xyaxis",
                title: "Progress",
                subtitle: "Every show-up counts."
            )
            .tag(AppTab.progress)
            .tabItem {
                Label("Progress", systemImage: "chart.line.uptrend.xyaxis")
            }

            PlaceholderTabView(
                icon: "person.crop.circle.fill",
                title: "Profile",
                subtitle: "Keep your movement basics current."
            )
            .tag(AppTab.profile)
            .tabItem {
                Label("Profile", systemImage: "person.crop.circle.fill")
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
