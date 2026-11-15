import XCTest
import SwiftUI
import UIKit
@testable import RepToday

/// Reviewer-visible evidence that the Profile tab's rows line their titles up: the production
/// `ProfileTabView` (Account, Settings; the Coach has its own tab since M4) rendered at the default
/// text size and at the largest accessibility size, in light and dark, under
/// `artifacts/reports/profile-row-alignment/` - plus the
/// largest size on an iPhone SE, where nothing is squeezed to fit and every row stays reachable.
///
/// Every row's title starts at the same x, because every row's icon is the same square size. That is read
/// off the rendered rows themselves.
@MainActor
final class ProfileRowAlignmentEvidenceTests: XCTestCase {

    private var window: UIWindow?

    override func tearDown() {
        window = nil
        super.tearDown()
    }

    private func hostProfile(
        dynamicTypeSize: DynamicTypeSize, size: CGSize, style: UIUserInterfaceStyle = .dark,
        safeArea: UIEdgeInsets? = nil
    ) throws -> UIView {
        let (_, hostedWindow) = HostedSurface.host(
            ProfileTabView()
                .environment(\.services, ServiceContainer.mock())
                .environment(\.dynamicTypeSize, dynamicTypeSize),
            size: size,
            style: style,
            emulatingSafeArea: safeArea
        )
        window = hostedWindow
        return try XCTUnwrap(hostedWindow.rootViewController?.view)
    }

    private func captureProfile(
        dynamicTypeSize: DynamicTypeSize, style: UIUserInterfaceStyle, named fileName: String
    ) throws {
        let size = CGSize(width: 393, height: dynamicTypeSize.isAccessibilitySize ? 1100 : 852)
        let root = try hostProfile(dynamicTypeSize: dynamicTypeSize, size: size, style: style)

        for title in ["Account", "Settings"] {
            XCTAssertNotNil(AccessibilityTree.element(labeled: title, in: root),
                            "the Profile tab should offer the \(title) row; tree reads \(AccessibilityTree.labels(in: root))")
        }

        let image = HostedSurface.capture(root, size: size, afterScreenUpdates: true)
        try EvidenceOutput.write(image, named: fileName, for: EvidenceOutput.Story.profileRowAlignment)
    }

    /// Renders the Profile tab's rows (`SettingsValueRowLabel`, each with its own icon) in their group at
    /// the narrowest phone's width (an iPhone SE) and reads where each title lands: every title starts at
    /// the same x. The bare labels are hosted (not `ProfileTabView`) because a
    /// `NavigationLink`'s own accessibility label merges its row into one element, hiding the title's frame.
    private func assertRowsLineUp(at dynamicTypeSize: DynamicTypeSize) throws {
        let rows: [(icon: AppIcon, title: String)] = [(.profile, "Account title"), (.settings, "Settings title")]
        let size = CGSize(width: 375, height: dynamicTypeSize.isAccessibilitySize ? 1600 : 852)
        let (_, hostedWindow) = HostedSurface.host(
            RowGroup {
                VStack(spacing: 0) {
                    ForEach(rows, id: \.title) { row in
                        SettingsValueRowLabel(icon: row.icon, title: row.title)
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.screenMargin)
            .environment(\.dynamicTypeSize, dynamicTypeSize),
            size: size
        )
        window = hostedWindow
        let root = try XCTUnwrap(hostedWindow.rootViewController?.view)
        let elements = AccessibilityTree.elements(in: root)

        var titleLeadingEdges: [(title: String, minX: CGFloat)] = []
        for row in rows {
            let title = try XCTUnwrap(elements.first { $0.accessibilityLabel == row.title },
                                      "no \(row.title) element; tree reads \(AccessibilityTree.labels(in: root))")
            titleLeadingEdges.append((row.title, title.accessibilityFrame.minX))
        }

        let reference = try XCTUnwrap(titleLeadingEdges.first)
        for edge in titleLeadingEdges.dropFirst() {
            XCTAssertEqual(edge.minX, reference.minX, accuracy: 0.5,
                           "\(edge.title) starts at x \(edge.minX) but \(reference.title) at x \(reference.minX), at \(dynamicTypeSize)")
        }
    }

    func testEveryRowLinesUpOnItsTitleAtTheDefaultTextSize() throws {
        try assertRowsLineUp(at: .large)
    }

    func testEveryRowLinesUpOnItsTitleAtTheLargestTextSize() throws {
        try assertRowsLineUp(at: .accessibility5)
    }

    /// On an iPhone SE (375x667 pt: a 20 pt status bar above, a 49 pt tab bar below) at the largest text
    /// size nothing in the Profile tab is squeezed to fit - every element keeps the height it has with
    /// unlimited room - and every element, the last row included, sits (or scrolls) fully into view
    /// between the status bar and the tab bar. With two rows it fits the screen today; a row added later
    /// makes it scroll, and this still holds.
    private func assertProfileScrollsOnAnIPhoneSE(style: UIUserInterfaceStyle, named name: String) throws {
        let screen = CGSize(width: 375, height: 667)
        let insets = UIEdgeInsets(top: 20, left: 0, bottom: 49, right: 0)
        let visible = CGRect(origin: .zero, size: screen).inset(by: insets).insetBy(dx: -0.5, dy: -0.5)

        let unlimited = try hostProfile(dynamicTypeSize: .accessibility5, size: CGSize(width: screen.width, height: 2400),
                                        style: style)
        let natural = AccessibilityTree.elements(in: unlimited).map { ($0.accessibilityLabel, $0.accessibilityFrame.height) }

        let root = try hostProfile(dynamicTypeSize: .accessibility5, size: screen, style: style, safeArea: insets)
        let elements = AccessibilityTree.elements(in: root)
        XCTAssertEqual(elements.map(\.accessibilityLabel), natural.map(\.0),
                       "the iPhone SE tab should carry the same elements as the unlimited one")
        for title in ["Account", "Settings"] {
            XCTAssertTrue(elements.contains { $0.accessibilityLabel == title }, "the Profile tab should offer the \(title) row")
        }
        for (element, (label, height)) in zip(elements, natural) {
            XCTAssertEqual(element.accessibilityFrame.height, height, accuracy: 0.5,
                           "\(label ?? "an element") is squeezed on an iPhone SE")
        }
        try EvidenceOutput.write(HostedSurface.capture(root, size: screen, afterScreenUpdates: true),
                                 named: "\(name)-top.png", for: EvidenceOutput.Story.profileRowAlignment)

        let scrollView = firstScrollView(in: root)
        for (index, element) in elements.enumerated() {
            if !visible.contains(element.accessibilityFrame), let scrollView {
                scrollView.scrollRectToVisible(scrollView.convert(element.accessibilityFrame, from: nil), animated: false)
                HostedSurface.pump(for: 0.3)
            }
            let frame = AccessibilityTree.elements(in: root)[index].accessibilityFrame
            XCTAssertTrue(visible.contains(frame),
                          "\(element.accessibilityLabel ?? "an element") at \(frame) cannot be brought into view on an iPhone SE")
        }
        try EvidenceOutput.write(HostedSurface.capture(root, size: screen, afterScreenUpdates: true),
                                 named: "\(name)-scrolled.png", for: EvidenceOutput.Story.profileRowAlignment)
    }

    private func firstScrollView(in view: UIView) -> UIScrollView? {
        if let scrollView = view as? UIScrollView { return scrollView }
        return view.subviews.lazy.compactMap { self.firstScrollView(in: $0) }.first
    }

    func testProfileScrollsOnAnIPhoneSEAtTheLargestTextLight() throws {
        try assertProfileScrollsOnAnIPhoneSE(style: .light, named: "profile-se-ax5-light")
    }

    func testProfileScrollsOnAnIPhoneSEAtTheLargestTextDark() throws {
        try assertProfileScrollsOnAnIPhoneSE(style: .dark, named: "profile-se-ax5-dark")
    }

    func testProfileRowsDefaultTextLight() throws {
        try captureProfile(dynamicTypeSize: .large, style: .light, named: "profile-default-light.png")
    }

    func testProfileRowsDefaultTextDark() throws {
        try captureProfile(dynamicTypeSize: .large, style: .dark, named: "profile-default-dark.png")
    }

    func testProfileRowsLargestTextLight() throws {
        try captureProfile(dynamicTypeSize: .accessibility5, style: .light, named: "profile-ax5-light.png")
    }

    func testProfileRowsLargestTextDark() throws {
        try captureProfile(dynamicTypeSize: .accessibility5, style: .dark, named: "profile-ax5-dark.png")
    }
}
