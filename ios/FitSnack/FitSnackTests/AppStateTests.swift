import XCTest
@testable import FitSnack

final class AppStateTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "FitSnack.AppStateTests.\(UUID().uuidString)"
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
}
