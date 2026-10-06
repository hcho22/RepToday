import XCTest
import SwiftUI
import UIKit
@testable import RepToday

/// Reviewer-visible evidence that the Profile tab's rows line their titles up: the production
/// `ProfileTabView` (Account, Coach, Settings) rendered at the default text size and at the largest
/// accessibility size, in light and dark, under `artifacts/reports/profile-row-alignment/` - plus the
/// largest size on an iPhone SE, where the tab scrolls rather than squeezing anything to fit.
///
/// Every row's title starts at the same x because its glyph sits in a fixed-width column. That is read
/// off the rendered rows themselves, and the column only holds the promise while every glyph fits
/// inside it, which is pinned at every text size the icon renders at.
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

        for title in ["Account", "Coach", "Settings"] {
            XCTAssertNotNil(AccessibilityTree.element(labeled: title, in: root),
                            "the Profile tab should offer the \(title) row; tree reads \(AccessibilityTree.labels(in: root))")
        }

        let image = HostedSurface.capture(root, size: size, afterScreenUpdates: true)
        try EvidenceOutput.write(image, named: fileName, for: EvidenceOutput.Story.profileRowAlignment)
    }

    /// Renders the real `ProfileRowLabel` once per glyph, with and without a badge, at the Profile tab's
    /// row width on the narrowest phone (an iPhone SE), and reads where each title and the glyph, chevron
    /// and badge beside it land: every title starts at the same x, the glyph and chevron sit on the
    /// title's line even when the badge moves under it, and the badge never wraps. The bare label is
    /// hosted (not `ProfileTabView`) because a `NavigationLink`'s own accessibility label merges its row
    /// into one element, hiding the title's frame.
    private func assertRowsLineUp(at dynamicTypeSize: DynamicTypeSize) throws {
        let rows = ProfileRowIcon.allCases.flatMap { icon in
            [nil, "Premium"].map { badge in
                (icon: icon, badge: badge, title: badge == nil ? "\(icon) title" : "\(icon) badged title")
            }
        }
        let size = CGSize(width: 375, height: dynamicTypeSize.isAccessibilitySize ? 1600 : 852)
        let (_, hostedWindow) = HostedSurface.host(
            VStack(spacing: Theme.Spacing.sm) {
                ForEach(rows, id: \.title) { row in
                    ProfileRowLabel(icon: row.icon, title: row.title, badge: row.badge)
                }
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .environment(\.dynamicTypeSize, dynamicTypeSize),
            size: size
        )
        window = hostedWindow
        let root = try XCTUnwrap(hostedWindow.rootViewController?.view)
        let elements = AccessibilityTree.elements(in: root)
        let badgeLineHeight = UIFont.preferredFont(
            forTextStyle: .caption1,
            compatibleWith: UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(dynamicTypeSize))
        ).lineHeight

        var titleLeadingEdges: [(title: String, minX: CGFloat)] = []
        for row in rows {
            let title = try XCTUnwrap(elements.first { $0.accessibilityLabel == row.title },
                                      "no \(row.title) element; tree reads \(AccessibilityTree.labels(in: root))")
            let titleFrame = title.accessibilityFrame
            let rowGlyphs = elements.filter { other in
                other !== title
                    && other.accessibilityLabel != row.badge
                    && other.accessibilityFrame.maxY > titleFrame.minY
                    && other.accessibilityFrame.minY < titleFrame.maxY
            }
            let leading = rowGlyphs.filter { $0.accessibilityFrame.minX < titleFrame.minX }
            let trailing = rowGlyphs.filter { $0.accessibilityFrame.minX >= titleFrame.maxX }
            XCTAssertFalse(leading.isEmpty, "the \(row.icon.rawValue) glyph should lead the \(row.title) row")
            XCTAssertFalse(trailing.isEmpty, "a chevron should end the \(row.title) row")
            for glyph in leading {
                XCTAssertLessThanOrEqual(glyph.accessibilityFrame.maxX, titleFrame.minX,
                                         "the \(row.icon.rawValue) glyph overlaps the \(row.title) title at \(dynamicTypeSize)")
            }
            for glyph in leading + trailing {
                XCTAssertEqual(glyph.accessibilityFrame.midY, titleFrame.midY, accuracy: 0.5,
                               "\(glyph.accessibilityLabel ?? "a glyph") sits off the \(row.title) line at \(dynamicTypeSize)")
            }
            if let badge = row.badge {
                let pill = try XCTUnwrap(elements.filter { $0.accessibilityLabel == badge }
                    .min { abs($0.accessibilityFrame.midY - titleFrame.midY) < abs($1.accessibilityFrame.midY - titleFrame.midY) })
                XCTAssertLessThan(pill.accessibilityFrame.height, 1.5 * badgeLineHeight + 2 * Theme.Spacing.xs,
                                  "the \(badge) badge wraps onto a second line in the \(row.title) row at \(dynamicTypeSize)")
            }
            titleLeadingEdges.append((row.title, titleFrame.minX))
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

    /// The widest glyph any row uses fits the shared icon column at every text size the icon grows to,
    /// so no glyph spills toward its title and every title starts at the same x.
    func testEveryRowGlyphFitsTheIconColumnAtEveryTextSize() throws {
        let sizes: [UIContentSizeCategory] = [
            .extraSmall, .small, .medium, .large, .extraLarge, .extraExtraLarge, .extraExtraExtraLarge,
            .accessibilityMedium,
        ]
        XCTAssertEqual(DynamicTypeSize(sizes.last!), ProfileRowIcon.largestTextSize,
                       "the checked sizes should end at the icon's largest text size")
        for size in sizes {
            let traits = UITraitCollection(preferredContentSizeCategory: size)
            let column = UIFontMetrics(forTextStyle: .body).scaledValue(for: ProfileRowIcon.columnWidth,
                                                                        compatibleWith: traits)
            let font = UIFont.preferredFont(forTextStyle: .body, compatibleWith: traits)
            for icon in ProfileRowIcon.allCases {
                let glyph = try XCTUnwrap(UIImage(systemName: icon.rawValue,
                                                  withConfiguration: UIImage.SymbolConfiguration(font: font)))
                XCTAssertLessThanOrEqual(glyph.size.width, column,
                                         "\(icon.rawValue) is wider than the icon column at \(size.rawValue)")
            }
        }
    }

    /// On an iPhone SE (375x667 pt: a 20 pt status bar above, a 49 pt tab bar below) at the largest text
    /// size the Profile tab is taller than the screen. Nothing in it is squeezed to fit - every element
    /// keeps the height it has with unlimited room - and every element, the last row included, can be
    /// scrolled fully into view between the status bar and the tab bar.
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
        for title in ["Account", "Coach", "Settings"] {
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
