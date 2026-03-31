import SwiftUI

struct MainTabView: View {
    @Bindable var appState: AppState

    var body: some View {
        TabView(selection: $appState.selectedTab) {
            HomeView()
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }
                .tag(AppState.Tab.home)

            ProgressTabView()
                .tabItem {
                    Label("Progress", systemImage: "chart.bar.fill")
                }
                .tag(AppState.Tab.progress)

            ChallengesTabView()
                .tabItem {
                    Label("Challenges", systemImage: "trophy.fill")
                }
                .tag(AppState.Tab.challenges)

            ProfileTabView()
                .tabItem {
                    Label("Profile", systemImage: "person.fill")
                }
                .tag(AppState.Tab.profile)
        }
        .tint(AppColors.brand)
        .animation(.easeInOut(duration: 0.2), value: appState.selectedTab)
    }
}

#Preview {
    MainTabView(appState: AppState())
}
