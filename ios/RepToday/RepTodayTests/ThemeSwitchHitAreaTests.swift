import SwiftUI
import UIKit
import XCTest
@testable import RepToday

/// The theme switch draws a 52 x 32 track, but the area a finger can press is the switch's whole frame
/// (`ThemeToggleStyle` gives it a rectangular content shape), so that frame must be at least the 44 pt
/// minimum touch target at every text size.
@MainActor
final class ThemeSwitchHitAreaTests: XCTestCase {
    func testSwitchFrameMeetsTheMinimumTouchTarget() throws {
        for size in [DynamicTypeSize.large, .accessibility5] {
            var isOn = false
            let (host, _) = HostedSurface.host(
                ThemeSwitch(label: "Probe", isOn: Binding(get: { isOn }, set: { isOn = $0 }))
                    .dynamicTypeSize(size),
                size: CGSize(width: 375, height: 200)
            )
            let frame = try XCTUnwrap(AccessibilityTree.element(labeled: "Probe", in: host.view)).accessibilityFrame
            XCTAssertGreaterThanOrEqual(frame.height, Theme.Spacing.minTouchTarget, "switch frame \(frame) at \(size)")
            XCTAssertGreaterThanOrEqual(frame.width, Theme.Spacing.minTouchTarget, "switch frame \(frame) at \(size)")
        }
    }
}
