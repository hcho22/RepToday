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

        XCTAssertEqual(defaults.string(forKey: "AppState.installId"), appState.installId)
        XCTAssertEqual(defaults.object(forKey: "AppState.firstLaunchAt") as? Date, launch)
        XCTAssertEqual(defaults.object(forKey: "AppState.lastActiveAt") as? Date, launch)
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
        XCTAssertEqual(defaults.object(forKey: "AppState.lastActiveAt") as? Date, relaunch)
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
    }

    func testInstallWeekIsTheCoarseWeekStartOfFirstLaunch() {
        // A Tuesday: the week start is behind it, so the precise install time is not recoverable.
        let launch = Self.date(2026, 8, 4, hour: 9)

        let appState = AppState(userDefaults: defaults, now: { launch }, calendar: Self.calendar)

        XCTAssertEqual(appState.installWeek, ConsistencyScore.startOfWeek(launch, Self.calendar))
        XCTAssertLessThan(appState.installWeek, launch)
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
}
