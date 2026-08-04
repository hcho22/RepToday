import Foundation
import Observation

/// The top-level app routes controlled by `AppState`.
enum AppTab: String, CaseIterable, Identifiable {
    case home
    case progress
    case profile

    var id: String { rawValue }
}

/// Small, persisted app state for routing and anonymous install identity.
///
/// `isOnboarded` chooses between onboarding and the main tabs. `selectedTab` restores the
/// user's last main-tab context. This uses the Observation framework (`@Observable`).
///
/// It is also the home of the anonymous per-install identity the funnel is cohorted by
/// (US-T05): `installId`, `firstLaunchAt`, and `lastActiveAt`. `installId` is a random UUIDv4
/// minted once, on first launch, and kept only in `UserDefaults` - it is deliberately **not**
/// derived from the IDFA, `identifierForVendor`, the Sign in with Apple identifier, or an email,
/// and it is deliberately **not** stored in the Keychain: a Keychain-persisted id survives an
/// uninstall and would resurrect an identity the user believed they deleted. Dying with the app
/// is the point, so a reinstall is a new install with a new id and a new `firstLaunchAt`.
///
/// The clock and the id generator are injected (`now`, `newInstallId`), so first-launch and
/// return-window behaviour is pinnable in tests without reading the wall clock inline.
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

    /// The anonymous per-install identifier: a random UUIDv4, minted on first launch and
    /// preserved by every relaunch of that install. Never an identity, never a device id.
    let installId: String

    /// When this install was first opened. Written once and never moved again, so it is the
    /// stable origin the install cohort and the return windows are measured from.
    let firstLaunchAt: Date

    /// The most recent open. Rewritten on every launch, and settable so a later foreground can
    /// move it.
    var lastActiveAt: Date {
        didSet {
            userDefaults.set(lastActiveAt, forKey: Keys.lastActiveAt)
        }
    }

    /// True only for the launch that minted this install's identity. This is the one moment the
    /// fact is knowable - once `init` returns, a first launch and a relaunch look alike - so it
    /// is captured here for the `app_install` emission that lands in US-T07.
    let isFirstLaunch: Bool

    /// The coarse install cohort: the start of the week `firstLaunchAt` fell in, via the same
    /// `ConsistencyScore.startOfWeek(_:_:)` the Consistency Score uses. Deliberately a week
    /// boundary and never a precise install time, so the cohort carries no timing fingerprint.
    var installWeek: Date {
        ConsistencyScore.startOfWeek(firstLaunchAt, calendar)
    }

    @ObservationIgnored private let userDefaults: UserDefaults
    @ObservationIgnored private let calendar: Calendar

    init(
        userDefaults: UserDefaults = .standard,
        now: () -> Date = Date.init,
        calendar: Calendar = .current,
        newInstallId: () -> String = { UUID().uuidString }
    ) {
        self.userDefaults = userDefaults
        self.calendar = calendar
        isOnboarded = userDefaults.bool(forKey: Keys.isOnboarded)

        let savedTab = userDefaults.string(forKey: Keys.selectedTab)
        selectedTab = savedTab.flatMap(AppTab.init(rawValue:)) ?? .home

        let openedAt = now()

        // The id and its origin are read as a pair: a half-written identity would cohort an
        // install against a week it did not install in, so anything short of both being present
        // is treated as a first launch and re-minted together.
        let storedId = userDefaults.string(forKey: Keys.installId)
        let storedFirstLaunch = userDefaults.object(forKey: Keys.firstLaunchAt) as? Date
        if let storedId, !storedId.isEmpty, let storedFirstLaunch {
            installId = storedId
            firstLaunchAt = storedFirstLaunch
            isFirstLaunch = false
        } else {
            installId = newInstallId()
            firstLaunchAt = openedAt
            isFirstLaunch = true
            userDefaults.set(installId, forKey: Keys.installId)
            userDefaults.set(firstLaunchAt, forKey: Keys.firstLaunchAt)
        }

        // `didSet` does not fire during `init`, so this launch's open time is written through.
        lastActiveAt = openedAt
        userDefaults.set(openedAt, forKey: Keys.lastActiveAt)
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
        static let installId = "AppState.installId"
        static let firstLaunchAt = "AppState.firstLaunchAt"
        static let lastActiveAt = "AppState.lastActiveAt"
    }
}

private extension UserDefaults {
    static let preview: UserDefaults = {
        let defaults = UserDefaults(suiteName: "RepToday.Preview") ?? .standard
        defaults.removePersistentDomain(forName: "RepToday.Preview")
        return defaults
    }()
}
