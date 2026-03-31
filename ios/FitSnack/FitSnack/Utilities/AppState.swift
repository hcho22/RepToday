import SwiftUI

@Observable
final class AppState {
    var isOnboarded: Bool {
        didSet { UserDefaults.standard.set(isOnboarded, forKey: "isOnboarded") }
    }
    var selectedTab: Tab = .home

    enum Tab: Int, CaseIterable {
        case home, progress, challenges, profile
    }

    init() {
        self.isOnboarded = UserDefaults.standard.bool(forKey: "isOnboarded")
    }
}
