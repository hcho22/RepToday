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

    // MARK: - Opt-out consent flag (US-T06)

    /// The trap this flag is most likely to fall into: `bool(forKey:)` answers `false` for a key
    /// that was never written, so a naive read would ship every fresh install opted **out** while
    /// the code read as if it defaulted to on. Absence must resolve to the shipped default.
    func testAFreshInstallIsOptedIn() {
        XCTAssertNil(defaults.object(forKey: AppState.analyticsEnabledKey), "precondition: never written")

        XCTAssertTrue(AppState.isAnalyticsEnabled(in: defaults))
        XCTAssertTrue(AppState(userDefaults: defaults).analyticsEnabled)
    }

    func testTurningTelemetryOffPersistsAndSurvivesRelaunch() {
        let appState = AppState(userDefaults: defaults)
        appState.analyticsEnabled = false

        XCTAssertEqual(defaults.object(forKey: AppState.analyticsEnabledKey) as? Bool, false)
        XCTAssertFalse(AppState.isAnalyticsEnabled(in: defaults))
        XCTAssertFalse(AppState(userDefaults: defaults).analyticsEnabled, "the choice did not survive a relaunch")
    }

    func testTurningTelemetryBackOnPersistsToo() {
        let appState = AppState(userDefaults: defaults)
        appState.analyticsEnabled = false
        appState.analyticsEnabled = true

        XCTAssertTrue(AppState.isAnalyticsEnabled(in: defaults))
        XCTAssertTrue(AppState(userDefaults: defaults).analyticsEnabled)
    }

    /// The XCUITest launch argument `-AppState.analyticsEnabled NO` lands in `UserDefaults`' argument
    /// domain as a **string**, not a `Bool`. That is the shape the out-of-process gate depends on, so
    /// it is asserted here rather than only exercised end to end: an `object(forKey:) as? Bool` read
    /// would miss it entirely and leave the app emitting under a test that believes it is silent.
    func testALaunchArgumentStringClosesTheGate() {
        for stringValue in ["NO", "0", "false"] {
            defaults.set(stringValue, forKey: AppState.analyticsEnabledKey)
            XCTAssertFalse(
                AppState.isAnalyticsEnabled(in: defaults),
                "\"\(stringValue)\" in the argument domain must read as opted out"
            )
            XCTAssertFalse(AppState(userDefaults: defaults).analyticsEnabled)
        }

        for stringValue in ["YES", "1", "true"] {
            defaults.set(stringValue, forKey: AppState.analyticsEnabledKey)
            XCTAssertTrue(
                AppState.isAnalyticsEnabled(in: defaults),
                "\"\(stringValue)\" in the argument domain must read as opted in"
            )
        }
    }

    /// The gate the transport actually holds reads `UserDefaults.standard` fresh on every call, so a
    /// change takes effect on the next event rather than the next launch. Asserted against `.standard`
    /// because that is the store production reads; the key is cleaned up either way.
    func testTheAnalyticsGateFollowsTheStandardStoreWithoutBeingRebuilt() {
        let standard = UserDefaults.standard
        let original = standard.object(forKey: AppState.analyticsEnabledKey)
        defer {
            if let original {
                standard.set(original, forKey: AppState.analyticsEnabledKey)
            } else {
                standard.removeObject(forKey: AppState.analyticsEnabledKey)
            }
        }

        let gate = AppState.analyticsGate()

        standard.removeObject(forKey: AppState.analyticsEnabledKey)
        XCTAssertTrue(gate(), "an install that never answered is opted in")

        standard.set(false, forKey: AppState.analyticsEnabledKey)
        XCTAssertFalse(gate(), "the same closure did not see the change; the gate was captured, not re-read")

        standard.set(true, forKey: AppState.analyticsEnabledKey)
        XCTAssertTrue(gate())
    }

    /// The writer and the reader must be bound to the *same* store, not to two that agree today.
    ///
    /// This is the only configuration that can fail, and the reason nothing else here catches it:
    /// every other test drives one store on both sides. If the gate re-read `.standard` while an
    /// `AppState` persisted the flag somewhere else - an app-group suite for a widget, say - the
    /// Settings toggle would keep rendering and persisting correctly while the transport read a key
    /// nobody writes, resolved it as absent, answered the shipped default `true`, and emitted for a
    /// user who had opted out. So the gate is asked to disagree with `.standard` on purpose.
    func testTheGateFollowsTheStoreItsAppStateWrites() {
        let standard = UserDefaults.standard
        let original = standard.object(forKey: AppState.analyticsEnabledKey)
        defer {
            if let original {
                standard.set(original, forKey: AppState.analyticsEnabledKey)
            } else {
                standard.removeObject(forKey: AppState.analyticsEnabledKey)
            }
        }

        let appState = AppState(userDefaults: defaults)
        let gate = appState.analyticsGate

        // The two stores are pinned to opposite answers, so following the wrong one is visible.
        standard.set(true, forKey: AppState.analyticsEnabledKey)
        appState.analyticsEnabled = false
        XCTAssertFalse(
            gate(),
            "the gate read a store this AppState does not write; an opted-out user would still emit"
        )

        standard.set(false, forKey: AppState.analyticsEnabledKey)
        appState.analyticsEnabled = true
        XCTAssertTrue(gate(), "the gate did not follow its own store back on")

        // And it is still re-read per call rather than captured, on whichever store it is bound to.
        defaults.set(false, forKey: AppState.analyticsEnabledKey)
        XCTAssertFalse(gate(), "the same closure did not see the change; the gate was captured")
    }

    /// The opt-out gates emission and nothing else. Turning it off must not clear the install
    /// identifier: that would put the install into the re-minted-identity state US-T07 has to decide
    /// about, which US-T06 is explicitly forbidden from reaching.
    func testTurningTelemetryOffLeavesTheInstallIdentityAlone() {
        let launch = Self.date(2026, 8, 4, hour: 9)
        let appState = AppState(userDefaults: defaults, now: { launch }, calendar: Self.calendar)
        let originalId = appState.installId

        appState.analyticsEnabled = false

        XCTAssertEqual(appState.installId, originalId)
        XCTAssertEqual(defaults.string(forKey: "AppState.installId"), originalId)
        XCTAssertEqual(appState.firstLaunchAt, launch)

        let relaunched = AppState(userDefaults: defaults, now: { launch }, calendar: Self.calendar)
        XCTAssertEqual(relaunched.installId, originalId, "opting out re-minted the identifier")
        XCTAssertFalse(relaunched.analyticsEnabled)
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
