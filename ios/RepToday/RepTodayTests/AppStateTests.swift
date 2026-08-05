import XCTest
#if canImport(UIKit)
import UIKit
#endif
@testable import RepToday

final class AppStateTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "RepToday.AppStateTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testDefaultsRouteToOnboardingAndHomeTab() {
        let appState = AppState(userDefaults: defaults)

        XCTAssertFalse(appState.isOnboarded)
        XCTAssertEqual(appState.selectedTab, .home)
    }

    func testStatePersistsToUserDefaults() {
        let appState = AppState(userDefaults: defaults)
        appState.isOnboarded = true
        appState.selectedTab = .progress

        let reloaded = AppState(userDefaults: defaults)
        XCTAssertTrue(reloaded.isOnboarded)
        XCTAssertEqual(reloaded.selectedTab, .progress)
    }

    func testInvalidPersistedTabFallsBackToHome() {
        defaults.set("missing-tab", forKey: "AppState.selectedTab")

        let appState = AppState(userDefaults: defaults)

        XCTAssertEqual(appState.selectedTab, .home)
    }

    // MARK: - Anonymous install identity (US-T05)

    func testFirstLaunchMintsInstallIdentityAndStamps() {
        let launch = Self.date(2026, 8, 4, hour: 9)

        let appState = AppState(userDefaults: defaults, now: { launch }, calendar: Self.calendar)

        XCTAssertTrue(appState.isFirstLaunch)
        XCTAssertNotNil(UUID(uuidString: appState.installId), "the identifier is a UUIDv4")
        XCTAssertEqual(appState.firstLaunchAt, launch)
        XCTAssertEqual(appState.lastActiveAt, launch)
        XCTAssertNil(appState.previousActiveAt, "there is no launch before the first one")

        XCTAssertEqual(defaults.string(forKey: "AppState.installId"), appState.installId)
        XCTAssertEqual(defaults.object(forKey: "AppState.firstLaunchAt") as? Date, launch)
        XCTAssertEqual(defaults.object(forKey: "AppState.lastActiveAt") as? Date, launch)
        XCTAssertFalse(defaults.bool(forKey: "AppState.firstLaunchUnknown"))
    }

    func testRelaunchPreservesIdentityAndMovesOnlyLastActive() {
        let firstLaunch = Self.date(2026, 8, 4, hour: 9)
        let relaunch = Self.date(2026, 8, 11, hour: 18)

        let original = AppState(userDefaults: defaults, now: { firstLaunch }, calendar: Self.calendar)
        let reloaded = AppState(userDefaults: defaults, now: { relaunch }, calendar: Self.calendar)

        XCTAssertFalse(reloaded.isFirstLaunch)
        XCTAssertEqual(reloaded.installId, original.installId)
        XCTAssertEqual(reloaded.firstLaunchAt, firstLaunch)
        XCTAssertEqual(reloaded.lastActiveAt, relaunch)
        XCTAssertEqual(reloaded.previousActiveAt, firstLaunch, "the launch before this one is still readable")
        XCTAssertEqual(defaults.object(forKey: "AppState.lastActiveAt") as? Date, relaunch)
    }

    /// An install that already existed when this build shipped: it has no stored `installId`, but
    /// it is onboarded, so its first launch happened before anything recorded one. It gets an id
    /// without being counted as a new install, and no fabricated origin date.
    func testAPreExistingInstallMintsAnIdWithoutBecomingANewInstall() {
        defaults.set(true, forKey: "AppState.isOnboarded")
        let upgrade = Self.date(2026, 8, 4, hour: 9)

        let appState = AppState(userDefaults: defaults, now: { upgrade }, calendar: Self.calendar)

        XCTAssertFalse(appState.isFirstLaunch, "an upgrade is not an install")
        XCTAssertNotNil(UUID(uuidString: appState.installId))
        XCTAssertNil(appState.firstLaunchAt, "the true first launch is unrecoverable, not the upgrade date")
        XCTAssertNil(appState.installWeek)
        XCTAssertEqual(appState.lastActiveAt, upgrade)
        XCTAssertNil(defaults.object(forKey: "AppState.firstLaunchAt"))
        XCTAssertTrue(defaults.bool(forKey: "AppState.firstLaunchUnknown"))
    }

    /// The upgraded shape - an id with no origin - is exactly what the half-written-pair rule
    /// re-mints, so it only stays stable because the unknown is persisted as its own marker.
    func testAPreExistingInstallKeepsItsIdentityAcrossRelaunches() {
        defaults.set(true, forKey: "AppState.isOnboarded")
        let upgrade = Self.date(2026, 8, 4, hour: 9)
        let relaunch = Self.date(2026, 8, 11, hour: 18)

        let upgraded = AppState(userDefaults: defaults, now: { upgrade }, calendar: Self.calendar)
        let reloaded = AppState(userDefaults: defaults, now: { relaunch }, calendar: Self.calendar)

        XCTAssertEqual(reloaded.installId, upgraded.installId)
        XCTAssertFalse(reloaded.isFirstLaunch)
        XCTAssertNil(reloaded.firstLaunchAt, "an unknown origin is never backfilled by a later launch")
        XCTAssertEqual(reloaded.previousActiveAt, upgrade)
    }

    /// The reinstall leg of the PRD's validation test: an uninstall takes `UserDefaults` with it,
    /// which a wiped suite reproduces exactly. Nothing may survive it - a surviving identifier
    /// would mean it was persisted somewhere (the Keychain) that outlives the app.
    func testReinstallProducesANewIdentityAndANewFirstLaunch() {
        let firstInstall = Self.date(2026, 8, 4, hour: 9)
        let secondInstall = Self.date(2026, 9, 1, hour: 7)

        let original = AppState(userDefaults: defaults, now: { firstInstall }, calendar: Self.calendar)
        defaults.removePersistentDomain(forName: suiteName)
        let reinstalled = AppState(userDefaults: defaults, now: { secondInstall }, calendar: Self.calendar)

        XCTAssertTrue(reinstalled.isFirstLaunch)
        XCTAssertNotEqual(reinstalled.installId, original.installId)
        XCTAssertEqual(reinstalled.firstLaunchAt, secondInstall)
    }

    func testAHalfWrittenIdentityIsReMintedAsAWholePair() {
        defaults.set("orphaned-id", forKey: "AppState.installId")
        let launch = Self.date(2026, 8, 4, hour: 9)

        let appState = AppState(userDefaults: defaults, now: { launch }, calendar: Self.calendar)

        XCTAssertTrue(appState.isFirstLaunch)
        XCTAssertNotEqual(appState.installId, "orphaned-id")
        XCTAssertEqual(appState.firstLaunchAt, launch)
        XCTAssertFalse(defaults.bool(forKey: "AppState.firstLaunchUnknown"), "a stamped origin is not an unknown one")
    }

    /// The narrower rule: re-minting a missing identifier never throws away an origin that
    /// survived. A recorded origin is the week this install really began, so cohorting against it
    /// is right - only the id needs replacing.
    func testAMissingIdentifierIsReMintedWithoutDiscardingAStoredOrigin() {
        defaults.set(true, forKey: "AppState.isOnboarded")
        let origin = Self.date(2026, 7, 21, hour: 8)
        defaults.set(origin, forKey: "AppState.firstLaunchAt")
        defaults.set("", forKey: "AppState.installId")
        let launch = Self.date(2026, 8, 4, hour: 9)

        let appState = AppState(userDefaults: defaults, now: { launch }, calendar: Self.calendar)

        XCTAssertFalse(appState.installId.isEmpty)
        XCTAssertNotNil(UUID(uuidString: appState.installId))
        XCTAssertFalse(appState.isFirstLaunch, "an origin was already on disk, so this is not one")
        XCTAssertEqual(appState.firstLaunchAt, origin, "a known origin is kept, not downgraded to unknown")
        XCTAssertEqual(appState.installWeek, ConsistencyScore.startOfWeek(origin, Self.calendar))
        XCTAssertEqual(defaults.object(forKey: "AppState.firstLaunchAt") as? Date, origin)
        XCTAssertNil(
            defaults.object(forKey: "AppState.firstLaunchUnknown"),
            "the unknown marker records that no usable origin exists, and one does"
        )
    }

    func testInstallWeekIsTheCoarseWeekStartOfFirstLaunch() throws {
        // A Tuesday: the week start is behind it, so the precise install time is not recoverable.
        let launch = Self.date(2026, 8, 4, hour: 9)

        let appState = AppState(userDefaults: defaults, now: { launch }, calendar: Self.calendar)

        let installWeek = try XCTUnwrap(appState.installWeek)
        XCTAssertEqual(installWeek, ConsistencyScore.startOfWeek(launch, Self.calendar))
        XCTAssertLessThan(installWeek, launch)
    }

    /// `install_week` is grouped across users server-side, so it is bucketed in one pinned
    /// calendar rather than in whatever week the device happens to keep.
    func testInstallWeekUsesThePinnedCohortCalendarRatherThanDeviceSettings() throws {
        // Saturday evening in Pacific time, which is already Sunday in UTC.
        let launch = Self.pacificDate(2026, 8, 8, hour: 21)

        // No calendar argument: this is the production default.
        let appState = AppState(userDefaults: defaults, now: { launch })

        let installWeek = try XCTUnwrap(appState.installWeek)
        XCTAssertEqual(installWeek, ConsistencyScore.startOfWeek(launch, AppState.cohortCalendar))
        XCTAssertEqual(installWeek, Self.pacificDate(2026, 8, 2, hour: 0), "the Sunday that week began")
        XCTAssertNotEqual(
            installWeek,
            ConsistencyScore.startOfWeek(launch, Self.calendar),
            "a device-shaped calendar would bucket this install a week later"
        )
    }

    func testCohortCalendarIsPinnedRatherThanReadFromTheDevice() {
        XCTAssertEqual(AppState.cohortCalendar.identifier, .gregorian)
        XCTAssertEqual(AppState.cohortCalendar.firstWeekday, 1, "Sunday-start, the US convention")
        XCTAssertEqual(AppState.cohortCalendar.timeZone, TimeZone(identifier: "America/Los_Angeles"))
    }

    func testInstallWeekIsStableAcrossLaunchesLaterInTheSameWeek() {
        let firstLaunch = Self.date(2026, 8, 4, hour: 9)
        let laterSameWeek = Self.date(2026, 8, 7, hour: 22)

        let original = AppState(userDefaults: defaults, now: { firstLaunch }, calendar: Self.calendar)
        let reloaded = AppState(userDefaults: defaults, now: { laterSameWeek }, calendar: Self.calendar)

        XCTAssertEqual(reloaded.installWeek, original.installWeek)
    }

    func testInstallIdentifierIsNotDerivedFromTheDeviceOrVendor() {
        let appState = AppState(userDefaults: defaults, now: { Self.date(2026, 8, 4, hour: 9) }, calendar: Self.calendar)

        #if canImport(UIKit)
        XCTAssertNotEqual(appState.installId, UIDevice.current.identifierForVendor?.uuidString)
        #endif
        // Two installs on the same device differ, which no device-derived value could.
        defaults.removePersistentDomain(forName: suiteName)
        let other = AppState(userDefaults: defaults, now: { Self.date(2026, 8, 4, hour: 9) }, calendar: Self.calendar)
        XCTAssertNotEqual(other.installId, appState.installId)
    }

    // MARK: - Helpers

    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private static func date(_ year: Int, _ month: Int, _ day: Int, hour: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private static func pacificDate(_ year: Int, _ month: Int, _ day: Int, hour: Int) -> Date {
        AppState.cohortCalendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }
}
