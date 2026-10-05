import XCTest
import SwiftUI
import UIKit
@testable import RepToday

/// Reviewer-visible evidence that the Profile tab's rows line their titles up: the production
/// `ProfileTabView` (Account, Coach, Settings) rendered at the default text size and at the largest
/// accessibility size, in light and dark, under `artifacts/reports/profile-row-alignment/`.
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

    private func captureProfile(
        dynamicTypeSize: DynamicTypeSize, style: UIUserInterfaceStyle, named fileName: String
    ) throws {
        let services = ServiceContainer.mock()
        let size = CGSize(width: 393, height: dynamicTypeSize.isAccessibilitySize ? 1100 : 852)
        let (_, hostedWindow) = HostedSurface.host(
            ProfileTabView()
                .environment(\.services, services)
                .environment(\.dynamicTypeSize, dynamicTypeSize),
            size: size,
            style: style
        )
        window = hostedWindow
        let root = try XCTUnwrap(hostedWindow.rootViewController?.view)

        for title in ["Account", "Coach", "Settings"] {
            XCTAssertNotNil(AccessibilityTree.element(labeled: title, in: root),
                            "the Profile tab should offer the \(title) row; tree reads \(AccessibilityTree.labels(in: root))")
        }

        let image = HostedSurface.capture(root, size: size, afterScreenUpdates: true)
        try EvidenceOutput.write(image, named: fileName, for: EvidenceOutput.Story.profileRowAlignment)
    }

    /// Renders the real `ProfileRowLabel` once per glyph, with and without a badge, and reads where each
    /// title lands. The bare label is hosted (not `ProfileTabView`) because a `NavigationLink`'s own
    /// accessibility label merges its row into one element, hiding the title's frame.
    private func assertRowTitlesAlign(at dynamicTypeSize: DynamicTypeSize) throws {
        let rows = ProfileRowIcon.allCases.flatMap { icon in
            [nil, "Premium"].map { badge in
                (icon: icon, badge: badge, title: badge == nil ? "\(icon) title" : "\(icon) badged title")
            }
        }
        let size = CGSize(width: 393, height: dynamicTypeSize.isAccessibilitySize ? 1600 : 852)
        let (_, hostedWindow) = HostedSurface.host(
            VStack(spacing: Theme.Spacing.sm) {
                ForEach(rows, id: \.title) { row in
                    ProfileRowLabel(icon: row.icon, title: row.title, badge: row.badge)
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
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
            let titleFrame = title.accessibilityFrame
            let leading = elements.filter { other in
                other !== title
                    && other.accessibilityFrame.minX < titleFrame.minX
                    && other.accessibilityFrame.maxY > titleFrame.minY
                    && other.accessibilityFrame.minY < titleFrame.maxY
            }
            XCTAssertFalse(leading.isEmpty, "the \(row.icon.rawValue) glyph should lead the \(row.title) row")
            for glyph in leading {
                XCTAssertLessThanOrEqual(glyph.accessibilityFrame.maxX, titleFrame.minX,
                                         "the \(row.icon.rawValue) glyph overlaps the \(row.title) title at \(dynamicTypeSize)")
            }
            titleLeadingEdges.append((row.title, titleFrame.minX))
        }

        let reference = try XCTUnwrap(titleLeadingEdges.first)
        for edge in titleLeadingEdges.dropFirst() {
            XCTAssertEqual(edge.minX, reference.minX, accuracy: 0.5,
                           "\(edge.title) starts at x \(edge.minX) but \(reference.title) at x \(reference.minX), at \(dynamicTypeSize)")
        }
    }

    func testEveryRowTitleStartsAtTheSameXAtTheDefaultTextSize() throws {
        try assertRowTitlesAlign(at: .large)
    }

    func testEveryRowTitleStartsAtTheSameXAtTheLargestTextSize() throws {
        try assertRowTitlesAlign(at: .accessibility5)
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
