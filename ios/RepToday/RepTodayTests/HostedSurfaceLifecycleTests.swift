import XCTest
import SwiftUI
import UIKit
@testable import RepToday

/// `HostedSurface` owns the life of every window it hosts a surface in: they are taken off the app's
/// window scene when their test ends, rather than left hidden on it for the rest of the run.
///
/// A window that is only hidden stays on the scene for as long as anything holds it, and over a full run
/// hosted windows piled up that way (25 by the Today status-bar test, 69 by the end). Past a few hundred
/// a hosted view stopped re-rendering after its model finished loading, which is the empty accessibility
/// tree `StatusBarBackingEvidenceTests` once failed on.
@MainActor
final class HostedSurfaceLifecycleTests: XCTestCase {

    private static let screen = CGSize(width: 375, height: 667)

    private var sceneWindows: [UIWindow] {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
    }

    func testHostedWindowIsOnTheSceneUntilItIsDismantled() {
        let (_, window) = HostedSurface.host(Text("hosted"), size: Self.screen, settleFor: 0.1)
        XCTAssertTrue(sceneWindows.contains(window), "a hosted window must join the app's scene to be live")

        HostedSurface.dismantle(window)

        XCTAssertNil(window.windowScene, "a dismantled window is detached from its scene, not just hidden")
        XCTAssertFalse(sceneWindows.contains(window))
        XCTAssertTrue(window.isHidden)
        XCTAssertNil(window.rootViewController, "the hosted surface is released with the window")
    }

    func testDismantlingEveryHostedWindowLeavesTheSceneAsItWasFound() {
        let before = sceneWindows.count

        // Three looks at one screen, each left visible - what a suite that never clears its window does.
        for _ in 0..<3 {
            _ = HostedSurface.host(Text("hosted"), size: Self.screen, settleFor: 0.1)
        }
        XCTAssertEqual(sceneWindows.count, before + 3)

        HostedSurface.dismantleAllHostedWindows()

        XCTAssertEqual(sceneWindows.count, before, "every window host created is taken off the scene")
    }

    func testDismantlingTwiceIsHarmless() {
        let (_, window) = HostedSurface.host(Text("hosted"), size: Self.screen, settleFor: 0.1)
        HostedSurface.dismantle(window)
        HostedSurface.dismantle(window)
        HostedSurface.dismantleAllHostedWindows()
        XCTAssertNil(window.windowScene)
    }
}
