import Foundation
import Observation

/// The top-level app routes controlled by `AppState`.
enum AppTab: String, CaseIterable, Identifiable {
    case home
    case progress
    case profile

    var id: String { rawValue }
}

/// Small, persisted app state for routing.
///
/// `isOnboarded` chooses between onboarding and the main tabs. `selectedTab` restores the
/// user's last main-tab context. This uses the Observation framework (`@Observable`).
@Observable
final class AppState {
    var isOnboarded: Bool {
        didSet {
            userDefaults.set(isOnboarded, forKey: Keys.isOnboarded)
        }
    }

    var selectedTab: AppTab {
        didSet {
            userDefaults.set(selectedTab.rawValue, forKey: Keys.selectedTab)
        }
    }

    @ObservationIgnored private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        isOnboarded = userDefaults.bool(forKey: Keys.isOnboarded)

        let savedTab = userDefaults.string(forKey: Keys.selectedTab)
        selectedTab = savedTab.flatMap(AppTab.init(rawValue:)) ?? .home
    }

    static func preview(isOnboarded: Bool = false, selectedTab: AppTab = .home) -> AppState {
        let appState = AppState(userDefaults: .preview)
        appState.isOnboarded = isOnboarded
        appState.selectedTab = selectedTab
        return appState
    }

    private enum Keys {
        static let isOnboarded = "AppState.isOnboarded"
        static let selectedTab = "AppState.selectedTab"
    }
}

private extension UserDefaults {
    static let preview: UserDefaults = {
        let defaults = UserDefaults(suiteName: "FitSnack.Preview") ?? .standard
        defaults.removePersistentDomain(forName: "FitSnack.Preview")
        return defaults
    }()
}
