import SwiftUI
import UIKit
import XCTest
@testable import RepToday

/// The Cycle strip's longest shape - five steps, one of them a day off - on the narrowest phone the app
/// supports (375pt wide, the Welcome Page's 24pt margins either side), at every text size up to the
/// largest non-accessibility one and the first accessibility one. The row is kept while every name fits
/// in full and gives way to the list when one would not, so no name is ever cut off. Each render is
/// captured for review under `artifacts/reports/US-HO01/`.
@MainActor
final class CycleStripLayoutEvidenceTests: XCTestCase {

    private let stripWidth: CGFloat = 375 - 2 * Theme.Spacing.lg

    private let fiveSteps = [
        CycleStep(.day(.push), .done),
        CycleStep(.day(.pull), .done),
        CycleStep(.rest, .done),
        CycleStep(.dayOff, .today),
        CycleStep(.day(.legs), .upcoming),
    ]

    private func height(of steps: [CycleStep], at size: DynamicTypeSize) -> CGFloat {
        let host = UIHostingController(rootView: CycleStripView(steps: steps).environment(\.dynamicTypeSize, size))
        return host.sizeThatFits(in: CGSize(width: stripWidth, height: .greatestFiniteMagnitude)).height
    }

    func testTheFiveStepStripKeepsTheRowWhileItFitsAndOtherwiseLists() throws {
        let sizes: [DynamicTypeSize] = [.xSmall, .small, .medium, .large, .xLarge, .xxLarge, .xxxLarge, .accessibility1]
        for size in sizes {
            let view = CycleStripView(steps: fiveSteps)
                .environment(\.dynamicTypeSize, size)
                .frame(width: stripWidth)
                .padding(Theme.Spacing.lg)
                .background(Theme.Colors.background)
            let canvas = CGSize(width: 375, height: height(of: fiveSteps, at: size) + 2 * Theme.Spacing.lg)
            let (_, window) = HostedSurface.host(view, size: canvas)
            let root = try XCTUnwrap(window.rootViewController?.view)
            XCTAssertEqual(
                AccessibilityTree.labels(in: root).first { $0.hasPrefix(WelcomeCopy.stripTitle) },
                "This cycle: Push, done. Pull, done. Rest, done. Day off, today. Legs, coming up.",
                "\(size)"
            )
            let image = HostedSurface.capture(root, size: canvas, afterScreenUpdates: true)
            try EvidenceOutput.write(image, named: "cycle-strip-five-steps-375-\(size).png", for: "US-HO01")
        }

        // At every size the strip is either one row of five or the list of five, never anything between
        // (a row squeezed onto a second line); where "Day off" no longer fits the row, the list takes over.
        for size in sizes {
            let row = height(of: [fiveSteps[3]], at: size)
            let five = height(of: fiveSteps, at: size)
            XCTAssertTrue(abs(five - row) < 0.5 || five > 2 * row, "\(size): \(five) against a row of \(row)")
        }
        XCTAssertGreaterThan(height(of: fiveSteps, at: .accessibility1), 2 * height(of: [fiveSteps[3]], at: .accessibility1))
    }
}
