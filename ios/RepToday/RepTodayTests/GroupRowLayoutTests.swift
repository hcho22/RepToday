import SwiftUI
import UIKit
import XCTest
@testable import RepToday

/// The shared group row (`GroupRow`) on the narrowest phone the app supports (375pt wide), in a row group,
/// with the titles and values the Settings and Profile screens give it, at every text size. No word is ever
/// broken in half, the title and the value never overlap, and at the accessibility sizes the value sits
/// under the title rather than beside it.
@MainActor
final class GroupRowLayoutTests: XCTestCase {

    private struct Row {
        let icon: AppIcon?
        let title: String
        var value: String?
        var showsChevron = true
    }

    /// The rows that show a value: Trainer, Reminders, Focus Areas.
    private let valueRows: [Row] = Trainer.allCases.map(\.displayName).map {
        Row(icon: .profile, title: TrainerChoiceCopy.settingsTitle, value: $0)
    } + [
        Row(icon: .profile, title: TrainerChoiceCopy.settingsTitle, value: TrainerChoiceCopy.notChosenValue),
        Row(icon: .bell, title: CoachReminderCopy.settingsTitle, value: SettingsView.reminderSummary(0)),
        Row(icon: .bell, title: CoachReminderCopy.settingsTitle, value: SettingsView.reminderSummary(2)),
        Row(icon: .focus, title: FocusAreasCopy.title, value: FocusAreasCopy.summary([])),
        Row(icon: .focus, title: FocusAreasCopy.title, value: FocusAreasCopy.summary([.arms, .legs])),
        Row(icon: .focus, title: FocusAreasCopy.title, value: FocusAreasCopy.summary(FocusArea.allCases)),
    ]

    /// The rows that show only a title: Profile's and the rest of Settings'.
    private let titleRows: [Row] = [
        Row(icon: .profile, title: "Account"),
        Row(icon: .settings, title: "Settings"),
        Row(icon: nil, title: "Privacy Policy", showsChevron: false),
        Row(icon: .coach, title: CoachDataDisclosureCopy.settingsRowTitle, showsChevron: false),
        Row(icon: .shield, title: InjuryFlagsCopy.title),
        Row(icon: .signout, title: SettingsView.signOutTitle, showsChevron: false),
        Row(icon: .trash, title: SettingsView.deleteAccountTitle, showsChevron: false),
    ]

    /// The font `token` draws at `size`: its cut scaled for its text style and rounded to a whole point, as
    /// SwiftUI draws a custom font.
    private func font(_ token: ThemeFont, at size: DynamicTypeSize) -> UIFont {
        let traits = UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(size))
        let style = token.uiTextStyle ?? .body
        let pointSize = UIFontMetrics(forTextStyle: style).scaledValue(for: token.size, compatibleWith: traits).rounded()
        return UIFont(name: token.name, size: pointSize) ?? .systemFont(ofSize: pointSize)
    }

    /// Hosts every row at `size`, each in its own row group as the screens lay it out, and checks each.
    private func assertRowsReadCleanly(_ rows: [Row], at size: DynamicTypeSize) throws {
        let screen = CGSize(width: 375, height: 3600)
        let (_, window) = HostedSurface.host(
            VStack(spacing: Theme.Spacing.smd) {
                ForEach(rows.indices, id: \.self) { index in
                    let row = rows[index]
                    RowGroup {
                        GroupRow(icon: row.icon, title: row.title, value: row.value, showsChevron: row.showsChevron)
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.screenMargin)
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
            let shown = try row.value.map(next)

            // A text broken mid-word is narrower than that word, so every word must fit its text's width -
            // at full size beside the title, and at no less than the row's shrink once stacked, where a
            // split word would also take a line more than the text has words.
            let scale = size.isAccessibilitySize ? GroupRow.stackedMinimumScale : 1
            var texts: [(String, NSObject, ThemeFont)] = [(row.title, title, GroupRow.titleFont)]
            if let value = row.value, let shown { texts.append((value, shown, GroupRow.valueFont)) }
            for (text, element, token) in texts {
                let font = font(token, at: size)
                let words = text.split(separator: " ").map(String.init)
                for word in words {
                    let wordWidth = (word as NSString).size(withAttributes: [.font: font]).width
                    XCTAssertGreaterThanOrEqual(element.accessibilityFrame.width + 1, scale * wordWidth,
                                                "\"\(word)\" is broken across lines in \"\(text)\" at \(size)")
                }
                if size.isAccessibilitySize {
                    // A row whose title is its only text reports that text at the row's frame, so its bound
                    // allows the row's vertical padding and its 60 pt floor.
                    let lines = CGFloat(words.count) * font.lineHeight
                    let bound = row.value == nil
                        ? max(lines + 2 * Theme.Spacing.smd, Theme.Spacing.rowHeight)
                        : lines
                    XCTAssertLessThanOrEqual(element.accessibilityFrame.height, bound + 2,
                                             "\"\(text)\" takes more lines than it has words at \(size)")
                }
            }

            guard let value = row.value, let shown else { continue }
            XCTAssertFalse(title.accessibilityFrame.intersects(shown.accessibilityFrame),
                           "\(row.title) \(title.accessibilityFrame) overlaps \"\(value)\" \(shown.accessibilityFrame) at \(size)")
            if size.isAccessibilitySize {
                XCTAssertGreaterThanOrEqual(shown.accessibilityFrame.minY, title.accessibilityFrame.maxY,
                                            "\"\(value)\" should sit under \(row.title) at \(size)")
            } else {
                XCTAssertGreaterThanOrEqual(shown.accessibilityFrame.minX, title.accessibilityFrame.maxX,
                                            "\"\(value)\" should trail \(row.title) at \(size)")
            }
        }
    }

    /// The largest accessibility size on the narrowest phone, where "Reminders" or "Settings" in Headline
    /// is wider than the row and used to split mid-word: every row stacks and shrinks a word instead.
    func testNoRowBreaksAWordAtTheLargestTextSize() throws {
        try assertRowsReadCleanly(valueRows + titleRows, at: .accessibility5)
    }

    func testRowsNeverBreakAWordOrOverlapAtAnyTextSize() throws {
        for size in DynamicTypeSize.allCases {
            try assertRowsReadCleanly(valueRows + titleRows, at: size)
        }
    }
}
