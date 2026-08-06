import XCTest
@testable import RepToday

/// US-T07 validation: the app-entry funnel events - `app_install`, `day7_return`, `day30_return` -
/// decided by `AppEntryTelemetry` off the identity `AppState` settles and an injected clock.
///
/// The suite drives the *real composition* `RepTodayApp.init()` performs rather than a hand-built
/// stand-in: it constructs `AppState` from a throwaway `UserDefaults` suite (exactly as the app does,
/// minus the wall clock) and feeds its `isFirstLaunch` / `firstLaunchAt` / `installWeek` into the
/// planner, relaunch after relaunch, advancing only the injected clock. So a regression in how
/// `AppState` resolves the three launch states surfaces here too, not only in `AppStateTests`.
///
/// No network: the planner returns values and never touches a sink, and the one dedup store it writes
/// is the same throwaway suite. FR-13 is not even in reach.
final class AppInstallEventTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "RepToday.AppInstallEventTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    // MARK: - The PRD validation walk

    /// The story's Validation Test, end to end: a first launch, then launches at days 3, 8, 12, 20,
    /// 33, 35, and 40. `app_install` fires once at first launch with the correct coarse `install_week`;
    /// `day7_return` fires once on the first open inside days 7-13 and never again; `day30_return`
    /// fires once inside days 30-36; no return event fires outside its window.
    func testTheInstallAndReturnWindowsAcrossASequenceOfLaunches() throws {
        let firstLaunch = Self.date(2026, 8, 4, hour: 9)

        // First launch: exactly one `app_install`, carrying the coarse week-start, and no return.
        let install = emit(at: firstLaunch)
        XCTAssertEqual(install.map(\.name), [.appInstall])
        let expectedWeek = ConsistencyScore.startOfWeek(firstLaunch, AppState.cohortCalendar)
        XCTAssertEqual(
            install.first?.properties["install_week"],
            .string(AppEntryTelemetry.installWeekString(expectedWeek))
        )

        // Day 3: too early for anything.
        XCTAssertEqual(emit(at: day(3, after: firstLaunch)), [])

        // Day 8: first open inside 7-13 emits `day7_return`, no properties, no `app_install`.
        let day8 = emit(at: day(8, after: firstLaunch))
        XCTAssertEqual(day8.map(\.name), [.day7Return])
        XCTAssertTrue(try XCTUnwrap(day8.first).properties.isEmpty)

        // Day 12: still inside 7-13, but emit-once has fired.
        XCTAssertEqual(emit(at: day(12, after: firstLaunch)), [])

        // Day 20: between the windows.
        XCTAssertEqual(emit(at: day(20, after: firstLaunch)), [])

        // Day 33: first open inside 30-36 emits `day30_return`, no properties.
        let day33 = emit(at: day(33, after: firstLaunch))
        XCTAssertEqual(day33.map(\.name), [.day30Return])
        XCTAssertTrue(try XCTUnwrap(day33.first).properties.isEmpty)

        // Day 35: still inside 30-36, deduped.
        XCTAssertEqual(emit(at: day(35, after: firstLaunch)), [])

        // Day 40: past the day-30 window.
        XCTAssertEqual(emit(at: day(40, after: firstLaunch)), [])
    }

    // MARK: - Window boundaries (inclusive 7-13 / 30-36)

    func testReturnWindowsAreInclusiveAtBothEnds() {
        let firstLaunch = Self.date(2026, 8, 4, hour: 9)
        _ = emit(at: firstLaunch) // stamp the origin

        // Day 6 is outside, day 7 is the first day inside.
        XCTAssertEqual(emit(at: day(6, after: firstLaunch)), [])
        XCTAssertEqual(emit(at: day(7, after: firstLaunch)).map(\.name), [.day7Return])

        // Day 13 would be inside, but day 7's window already fired; day 30 opens the next window.
        XCTAssertEqual(emit(at: day(13, after: firstLaunch)), [])
        XCTAssertEqual(emit(at: day(30, after: firstLaunch)).map(\.name), [.day30Return])

        // Day 36 is the last day inside the day-30 window; it too is deduped by now.
        XCTAssertEqual(emit(at: day(36, after: firstLaunch)), [])
    }

    /// A single launch that lands late in the day-7 window (skipping days 7-12 entirely) still emits
    /// `day7_return` once - the window is "any open during", not "the open on day 7 exactly".
    func testASingleLateOpenInsideTheWindowStillEmitsOnce() {
        let firstLaunch = Self.date(2026, 8, 4, hour: 9)
        _ = emit(at: firstLaunch)

        XCTAssertEqual(emit(at: day(13, after: firstLaunch)).map(\.name), [.day7Return])
        XCTAssertEqual(emit(at: day(13, after: firstLaunch)), [], "the window is emit-once")
    }

    /// Day 14 is one day past the day-7 window and must never emit it.
    func testDay14IsPastTheDay7Window() {
        let firstLaunch = Self.date(2026, 8, 4, hour: 9)
        _ = emit(at: firstLaunch)
        XCTAssertEqual(emit(at: day(14, after: firstLaunch)), [])
    }

    // MARK: - `app_install` fires at most once, and only on the first launch

    /// The failure indicator: `app_install` firing on a later launch. A relaunch resolves
    /// `isFirstLaunch == false`, so the planner never re-emits it.
    func testAppInstallNeverFiresOnARelaunch() {
        let firstLaunch = Self.date(2026, 8, 4, hour: 9)
        XCTAssertEqual(emit(at: firstLaunch).map(\.name), [.appInstall])

        // A relaunch the same week, still before any return window.
        XCTAssertEqual(emit(at: Self.date(2026, 8, 5, hour: 9)), [])
    }

    // MARK: - `install_week` is coarse, never a precise timestamp

    /// The other failure indicator: `install_week` being a precise timestamp. It is a `yyyy-MM-dd`
    /// week-start, so it names a day behind the (Tuesday) install and carries no time of day.
    func testInstallWeekIsACoarseWeekStartString() throws {
        let firstLaunch = Self.date(2026, 8, 4, hour: 9) // a Tuesday
        let install = try XCTUnwrap(emit(at: firstLaunch).first)

        guard case let .string(week)? = install.properties["install_week"] else {
            return XCTFail("install_week was not a string scalar")
        }
        // A bare date, no time component, and it is the Sunday the cohort week began (Pacific).
        XCTAssertEqual(week, "2026-08-02")
        XCTAssertFalse(week.contains(":"), "install_week must not carry a time of day")
        XCTAssertFalse(week.contains("T"), "install_week must not be an ISO timestamp")
    }

    /// The chosen encoding round-trips through the property-bag value type and the wire flattening as
    /// a plain JSON string, which is what US-T05 deferred to this story to confirm.
    func testInstallWeekRoundTripsThroughTheWireAsAPlainString() throws {
        let firstLaunch = Self.date(2026, 8, 4, hour: 9)
        let install = try XCTUnwrap(emit(at: firstLaunch).first)

        let wire = try AnalyticsWireBody.encode(install, installId: "install-42")
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: wire) as? [String: Any])
        let props = try XCTUnwrap(json["props"] as? [String: Any])
        XCTAssertEqual(props["install_week"] as? String, "2026-08-02")
        // Flattened to a bare scalar, not `AnalyticsValue`'s tagged in-process form.
        XCTAssertEqual(props.count, 1)
        let raw = try XCTUnwrap(String(data: wire, encoding: .utf8))
        XCTAssertFalse(raw.contains("\"type\""), "the tagged encoding leaked onto the wire")
    }

    // MARK: - The two US-T05 decisions

    /// **Unknown-origin install** (pre-existing: onboarded, no stored id, so `isFirstLaunch == false`
    /// and `firstLaunchAt == nil`): emits **nothing**, ever. No `app_install` - it is genuinely not a
    /// new install, and the upgrade date is not an honest cohort - and no return event, because there
    /// is no origin to window from. Asserted across a first open and both return windows.
    func testUnknownOriginInstallEmitsNothing() {
        defaults.set(true, forKey: "AppState.isOnboarded")
        let upgrade = Self.date(2026, 8, 4, hour: 9)

        // The upgrade open, and opens that would be inside each return window if there were an origin.
        for launch in [upgrade, day(8, after: upgrade), day(33, after: upgrade)] {
            let appState = AppState(userDefaults: defaults, now: { launch }, calendar: AppState.cohortCalendar)
            XCTAssertFalse(appState.isFirstLaunch)
            XCTAssertNil(appState.firstLaunchAt)
            XCTAssertEqual(
                AppEntryTelemetry.eventsForLaunch(
                    isFirstLaunch: appState.isFirstLaunch,
                    firstLaunchAt: appState.firstLaunchAt,
                    installWeek: appState.installWeek,
                    now: launch,
                    defaults: defaults
                ),
                [],
                "an install with no honest origin emitted an event"
            )
        }
    }

    /// **Re-minted identity** (onboarded, a usable `firstLaunchAt` survives, but the stored id is
    /// empty, so `AppState` re-mints only the id and reports `isFirstLaunch == false` with
    /// `installWeek` intact): emits **no** `app_install`, because keying off "this launch stamped an
    /// origin" and not "this launch minted an id" avoids double-counting one physical device. The
    /// surviving origin is still a real window origin, so return events do fire off it.
    func testReMintedIdentityEmitsNoAppInstallButStillWindowsReturnsOffTheSurvivingOrigin() {
        defaults.set(true, forKey: "AppState.isOnboarded")
        let origin = Self.date(2026, 7, 21, hour: 8)
        defaults.set(origin, forKey: "AppState.firstLaunchAt")
        defaults.set("", forKey: "AppState.installId")

        // A relaunch two weeks after the surviving origin: inside the day-7 window, id gets re-minted.
        let relaunch = day(9, after: origin)
        let appState = AppState(userDefaults: defaults, now: { relaunch }, calendar: AppState.cohortCalendar)
        XCTAssertFalse(appState.isFirstLaunch)
        XCTAssertEqual(appState.firstLaunchAt, origin)
        XCTAssertNotNil(appState.installWeek)

        let events = AppEntryTelemetry.eventsForLaunch(
            isFirstLaunch: appState.isFirstLaunch,
            firstLaunchAt: appState.firstLaunchAt,
            installWeek: appState.installWeek,
            now: relaunch,
            defaults: defaults
        )
        XCTAssertFalse(events.map(\.name).contains(.appInstall), "a re-minted id double-counted the install")
        XCTAssertEqual(events.map(\.name), [.day7Return], "the surviving origin is still a valid window origin")
    }

    // MARK: - Emission from a nil origin never fires a return

    func testNoReturnEventWhenFirstLaunchIsNil() {
        // Directly: a nil origin cannot produce a window, whatever the clock says.
        let now = Self.date(2026, 9, 1, hour: 12)
        XCTAssertEqual(
            AppEntryTelemetry.eventsForLaunch(
                isFirstLaunch: false, firstLaunchAt: nil, installWeek: nil, now: now, defaults: defaults
            ),
            []
        )
    }

    // MARK: - Helpers

    /// Runs one launch through the real `AppState` -> `AppEntryTelemetry` composition against the
    /// shared suite, returning the events that launch would emit. The suite persists across calls, so
    /// successive calls model relaunches: identity is stable, dedup accumulates, only `now` moves.
    private func emit(at now: Date) -> [AnalyticsEvent] {
        let appState = AppState(userDefaults: defaults, now: { now }, calendar: AppState.cohortCalendar)
        return AppEntryTelemetry.eventsForLaunch(
            isFirstLaunch: appState.isFirstLaunch,
            firstLaunchAt: appState.firstLaunchAt,
            installWeek: appState.installWeek,
            now: now,
            defaults: defaults
        )
    }

    private func day(_ n: Int, after start: Date) -> Date {
        start.addingTimeInterval(TimeInterval(n) * 86_400)
    }

    /// A fixed date built in the pinned cohort calendar, so the week-start math matches production's.
    private static func date(_ year: Int, _ month: Int, _ day: Int, hour: Int) -> Date {
        AppState.cohortCalendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }
}
