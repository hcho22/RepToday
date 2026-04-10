import SwiftUI

@Observable
final class AppState {
    var isOnboarded: Bool {
        didSet { UserDefaults.standard.set(isOnboarded, forKey: "isOnboarded") }
    }
    var selectedTab: Tab = .home
    var deepLink: DeepLink?

    enum Tab: Int, CaseIterable {
        case home, progress, challenges, profile
    }

    enum DeepLink: Equatable {
        case weeklyReport
        case streakSaver
    }

    init() {
        self.isOnboarded = UserDefaults.standard.bool(forKey: "isOnboarded")
    }

    func handleDeepLink(_ link: DeepLink) {
        switch link {
        case .weeklyReport:
            selectedTab = .progress
            deepLink = link
        case .streakSaver:
            selectedTab = .home
            deepLink = link
        }
    }
}
