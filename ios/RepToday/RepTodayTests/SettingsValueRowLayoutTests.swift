import SwiftUI
import UIKit
import XCTest
@testable import RepToday

/// The Settings rows that show a value (`SettingsValueRowLabel`: Trainer, Reminders, Focus Areas) in an
/// inset-grouped list on the narrowest phone the app supports (375pt wide), at every text size. No word is
/// ever broken in half, the title and the value never overlap, and at the accessibility sizes the value
/// sits under the title rather than beside it.
@MainActor
final class SettingsValueRowLayoutTests: XCTestCase {

    private struct Row {
        let systemImage: String
        let title: String
        let value: String
        var valueLineLimit: Int?
        var trailingSystemImage: String?
    }

    /// A navigation row's disclosure chevron. The list merges a link into one element, hiding the frames
    /// read here, so a navigation row is hosted bare with this glyph standing in for the list's.
    private static let disclosure = "chevron.right"

    private let rows: [Row] = Trainer.allCases.map(\.displayName).map {
        Row(systemImage: "figure.strengthtraining.functional", title: TrainerChoiceCopy.settingsTitle, value: $0,
            trailingSystemImage: "chevron.up.chevron.down")
    } + [
        Row(systemImage: "figure.strengthtraining.functional", title: TrainerChoiceCopy.settingsTitle,
            value: TrainerChoiceCopy.notChosenValue, trailingSystemImage: "chevron.up.chevron.down"),
        Row(systemImage: "bell", title: CoachReminderCopy.settingsTitle, value: SettingsView.reminderSummary(0),
            trailingSystemImage: SettingsValueRowLayoutTests.disclosure),
        Row(systemImage: "bell", title: CoachReminderCopy.settingsTitle, value: SettingsView.reminderSummary(2),
            trailingSystemImage: SettingsValueRowLayoutTests.disclosure),
        Row(systemImage: "scope", title: FocusAreasCopy.title, value: FocusAreasCopy.summary([]),
            valueLineLimit: 2, trailingSystemImage: SettingsValueRowLayoutTests.disclosure),
        Row(systemImage: "scope", title: FocusAreasCopy.title, value: FocusAreasCopy.summary([.arms, .legs]),
            valueLineLimit: 2, trailingSystemImage: SettingsValueRowLayoutTests.disclosure),
    ]

    /// The rounded body font the row draws at `size`.
    private func font(at size: DynamicTypeSize) -> UIFont {
        let traits = UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(size))
        let body = UIFont.preferredFont(forTextStyle: .body, compatibleWith: traits)
        return body.fontDescriptor.withDesign(.rounded).map { UIFont(descriptor: $0, size: body.pointSize) } ?? body
    }

    /// Hosts every row at `size` and checks each.
    private func assertRowsReadCleanly(at size: DynamicTypeSize) throws {
        let rows = self.rows
        let screen = CGSize(width: 375, height: 2400)
        let (_, window) = HostedSurface.host(
            List {
                ForEach(rows.indices, id: \.self) { index in
                    let row = rows[index]
                    Section {
                        SettingsValueRowLabel(
                            systemImage: row.systemImage,
                            title: row.title,
                            value: row.value,
                            valueLineLimit: row.valueLineLimit,
                            trailingSystemImage: row.trailingSystemImage
                        )
                    }
                }
            }
            .listStyle(.insetGrouped)
            .environment(\.dynamicTypeSize, size),
            size: screen
        )
        let root = try XCTUnwrap(window.rootViewController?.view)
        let elements = AccessibilityTree.elements(in: root)
        var claimed = Set<ObjectIdentifier>()
        /// The topmost element labeled `label` not yet matched to an earlier row.
        func next(_ label: String) throws -> NSObject {
            let element = try XCTUnwrap(
                elements.filter { $0.accessibilityLabel == label && !claimed.contains(ObjectIdentifier($0)) }
                    .min { $0.accessibilityFrame.minY < $1.accessibilityFrame.minY },
                "no \(label) at \(size); tree reads \(AccessibilityTree.labels(in: root))"
            )
            claimed.insert(ObjectIdentifier(element))
            return element
        }

        for row in rows {
            let title = try next(row.title)
            let shown = try next(row.value)

            // A text broken mid-word is narrower than that word, so every word must fit its text's width -
            // at full size beside the title, and at no less than the row's shrink once stacked, where a
            // split word would also take a line more than the text has words.
            let font = font(at: size)
            let scale = size.isAccessibilitySize ? SettingsValueRowLabel.stackedMinimumScale : 1
            for (text, element) in [(row.title, title), (row.value, shown)] {
                let words = text.split(separator: " ").map(String.init)
                for word in words {
                    let wordWidth = (word as NSString).size(withAttributes: [.font: font]).width
                    XCTAssertGreaterThanOrEqual(element.accessibilityFrame.width + 1, scale * wordWidth,
                                                "\"\(word)\" is broken across lines in \"\(text)\" at \(size)")
                }
                if size.isAccessibilitySize {
                    XCTAssertLessThanOrEqual(element.accessibilityFrame.height, CGFloat(words.count) * font.lineHeight + 2,
                                             "\"\(text)\" takes more lines than it has words at \(size)")
                }
            }

            XCTAssertFalse(title.accessibilityFrame.intersects(shown.accessibilityFrame),
                           "\(row.title) \(title.accessibilityFrame) overlaps \"\(row.value)\" \(shown.accessibilityFrame) at \(size)")
            if size.isAccessibilitySize {
                XCTAssertGreaterThanOrEqual(shown.accessibilityFrame.minY, title.accessibilityFrame.maxY,
                                            "\"\(row.value)\" should sit under \(row.title) at \(size)")
            } else {
                XCTAssertGreaterThanOrEqual(shown.accessibilityFrame.minX, title.accessibilityFrame.maxX,
                                            "\"\(row.value)\" should trail \(row.title) at \(size)")
            }
        }
    }

    func testValueRowsNeverBreakAWordOrOverlapAtAnyTextSize() throws {
        for size in DynamicTypeSize.allCases {
            try assertRowsReadCleanly(at: size)
        }
    }
}
