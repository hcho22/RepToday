import SwiftUI

/// Placeholder root view for the clean rebuild.
///
/// US-A01 deliberately ships an empty shell that proves the project builds,
/// launches, and renders using the `Theme` design tokens. The real routing
/// (onboarding vs. main tabs, driven by AppState) replaces this in US-A05.
struct RootView: View {
    var body: some View {
        ZStack {
            Theme.Colors.background
                .ignoresSafeArea()

            VStack(spacing: Theme.Spacing.md) {
                Image(systemName: "figure.run")
                    .font(.system(size: 48, weight: .bold))
                    .foregroundStyle(Theme.Colors.accent)

                Text("FitSnack")
                    .font(Theme.Typography.largeTitle)
                    .foregroundStyle(Theme.Colors.textPrimary)

                Text("Project scaffold ready")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .padding(Theme.Spacing.lg)
        }
    }
}

#Preview {
    RootView()
}
