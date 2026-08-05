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
/// minted on first launch and kept only in `UserDefaults` - it is deliberately **not** derived
/// from the IDFA, `identifierForVendor`, the Sign in with Apple identifier, or an email, and it is
/// deliberately **not** stored in the Keychain: a Keychain item survives a plain uninstall with
/// no restore involved and would resurrect an identity the user believed they deleted.
/// `UserDefaults` is much weaker than that, which is the point - but it is not nothing:
/// `Library/Preferences` is included in iCloud and iTunes backups and in device-to-device
/// transfer, so the guarantee is that the id dies with the app *absent a backup restore*, and
/// one id can end up live on two devices after a migration. A plain reinstall is a new install
/// with a new id.
///
/// The clock, the calendar, and the id generator are injected (`now`, `calendar`,
/// `newInstallId`), so cohorting behaviour is pinnable in tests without reading the wall clock
/// or the device's locale inline.
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

    /// The anonymous per-install identifier: a random UUIDv4, minted on first launch and preserved
    /// by every relaunch that still finds it on disk. A missing or empty stored id is re-minted -
    /// the id is the half of the identity that gets replaced, while a recorded origin is the half
    /// that survives. Never an identity, never a device id.
    let installId: String

    /// When this install was first opened, or `nil` when that moment is genuinely unrecoverable.
    /// Written once and never moved again, so it is the stable origin the install cohort is
    /// measured from.
    ///
    /// It is `nil` for an install that already existed before this build shipped and has no origin
    /// recorded on disk: such a launch mints an id but has no honest first-launch date, and the
    /// upgrade date is not one. A plausible-looking date would eventually be read without its
    /// caveat and would cohort the install into the week it upgraded, so the unknown is modelled
    /// as an unknown and every consumer has to decide what to do with it. A recorded origin is
    /// never discarded, though - re-minting the id does not throw the origin away with it.
    let firstLaunchAt: Date?

    /// The most recent **cold** launch. `init` is the only thing that writes it, and `AppState` is
    /// constructed once per process, so a resume from the background does not move it - and iOS
    /// resumes a suspended app far more often than it cold-launches one, so this can lag real usage
    /// by days. It is a settable `var` matching `isOnboarded`/`selectedTab`, which means a
    /// foreground update *could* move it, but nothing wires one today and no story owns doing so;
    /// nothing reads the value either. Read it as "last cold launch" until that changes.
    var lastActiveAt: Date {
        didSet {
            userDefaults.set(lastActiveAt, forKey: Keys.lastActiveAt)
        }
    }

    /// The `lastActiveAt` the previous cold launch left behind, or `nil` when there was none.
    ///
    /// Nothing reads this today. It exists because `init` overwrites the persisted value with
    /// this launch's open time, so without a snapshot taken here the previous one is destroyed
    /// at construction and is unrecoverable for the life of the process - the app pays to write
    /// the value on every launch and would then keep nothing readable from it.
    let previousActiveAt: Date?

    /// True only for the launch that first opened this install. This is the one moment the fact
    /// is knowable - once `init` returns, a first launch and a relaunch look alike - so it is
    /// captured here for the `app_install` emission that lands in US-T07. It is true only when
    /// this launch stamped the origin itself: an install that existed before this build shipped,
    /// or one whose origin was already on disk, mints an id without this being true - that is a
    /// new identity, not a new install.
    let isFirstLaunch: Bool

    /// The coarse install cohort: the start of the week `firstLaunchAt` fell in, through the same
    /// `ConsistencyScore.startOfWeek(_:_:)` the Consistency Score uses - the same week *math*,
    /// handed a different calendar (see `cohortCalendar`). Deliberately a week boundary and never
    /// a precise install time, so the cohort carries no timing fingerprint. `nil` exactly when
    /// `firstLaunchAt` is.
    var installWeek: Date? {
        firstLaunchAt.map { ConsistencyScore.startOfWeek($0, calendar) }
    }

    /// The calendar the install cohort is bucketed in: Gregorian, Sunday-start, pinned to
    /// Pacific time. It is pinned rather than read from the device because `install_week` is
    /// grouped **across** users server-side, and a week boundary that follows each device's
    /// `firstWeekday` and time zone would put two installs from the same real week into
    /// different buckets. Pacific rather than UTC because a UTC boundary lands mid-Saturday
    /// afternoon Pacific and would push a Saturday-evening install into the following week.
    ///
    /// The on-device Consistency Score deliberately stays on `Calendar.current`: a user's own
    /// training week is their local week, and unifying the two would break one of them. Change
    /// this constant, not that one - US conventions are a "for now" choice, and this is the one
    /// place it moves.
    static let cohortCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 1
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles") ?? TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    @ObservationIgnored private let userDefaults: UserDefaults
    @ObservationIgnored private let calendar: Calendar

    init(
        userDefaults: UserDefaults = .standard,
        now: () -> Date = Date.init,
        calendar: Calendar = AppState.cohortCalendar,
        newInstallId: () -> String = { UUID().uuidString }
    ) {
        self.userDefaults = userDefaults
        self.calendar = calendar
        let wasOnboarded = userDefaults.bool(forKey: Keys.isOnboarded)
        isOnboarded = wasOnboarded

        let savedTab = userDefaults.string(forKey: Keys.selectedTab)
        selectedTab = savedTab.flatMap(AppTab.init(rawValue:)) ?? .home

        let openedAt = now()
        previousActiveAt = userDefaults.object(forKey: Keys.lastActiveAt) as? Date

        // The id and its origin are resolved together, but they are not all-or-nothing: a missing
        // or empty id is re-minted, while a stored origin is kept whenever there is one. An origin
        // that survived is still the week this install really began, and discarding it would
        // cohort the install against a week it did not install in - which is the thing the rule
        // exists to prevent, not something it should cause. The origin falls back to unknown only
        // when none is usable, and that unknown is recorded as a marker written beside the id, so
        // the three states (a first launch, an install with no usable origin, and a relaunch of
        // either) stay distinguishable across launches.
        let storedId = userDefaults.string(forKey: Keys.installId)
        let storedFirstLaunch = userDefaults.object(forKey: Keys.firstLaunchAt) as? Date
        let storedFirstLaunchUnknown = userDefaults.bool(forKey: Keys.firstLaunchUnknown)
        if let storedId, !storedId.isEmpty, storedFirstLaunch != nil || storedFirstLaunchUnknown {
            installId = storedId
            firstLaunchAt = storedFirstLaunch
            isFirstLaunch = false
        } else {
            // An install that is already onboarded but carries no id existed before this build
            // shipped: it is a new identity on an old install, so with no origin on disk its true
            // first launch is gone and the upgrade date is not a stand-in for it. The residual,
            // accepted rather than chased: someone who installed an earlier build and never
            // finished onboarding still reads as a fresh install here.
            let isPreExistingInstall = wasOnboarded
            installId = newInstallId()
            firstLaunchAt = storedFirstLaunch ?? (isPreExistingInstall ? nil : openedAt)
            isFirstLaunch = storedFirstLaunch == nil && !isPreExistingInstall
            userDefaults.set(installId, forKey: Keys.installId)
            if let firstLaunchAt {
                userDefaults.set(firstLaunchAt, forKey: Keys.firstLaunchAt)
                userDefaults.removeObject(forKey: Keys.firstLaunchUnknown)
            } else {
                userDefaults.removeObject(forKey: Keys.firstLaunchAt)
                userDefaults.set(true, forKey: Keys.firstLaunchUnknown)
            }
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
        static let firstLaunchUnknown = "AppState.firstLaunchUnknown"
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
