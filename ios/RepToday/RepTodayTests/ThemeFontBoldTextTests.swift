import XCTest
import SwiftUI
import UIKit
@testable import RepToday

/// Bold Text draws every Theme type token in its heavier bundled cut: SwiftUI does not embolden a custom
/// font by itself, so without this a Bold Text user would lose the heavier type the system fonts gave.
@MainActor
final class ThemeFontBoldTextTests: XCTestCase {

    private typealias Name = Theme.Typography.FontName

    /// Inter steps one weight heavier (400 to 600, 500 to 700, 600 and up to 800), Bricolage Bold to
    /// ExtraBold, and display cuts already at ExtraBold stay.
    func testEachCutResolvesToItsBoldTextCut() {
        let expected: [(String, String)] = [
            (Name.textRegular, Name.textSemiBold),
            (Name.textMedium, Name.textBold),
            (Name.textSemiBold, Name.textExtraBold),
            (Name.textBold, Name.textExtraBold),
            (Name.textExtraBold, Name.textExtraBold),
            (Name.value, Name.displaySmall),
            (Name.displaySmall, Name.displaySmall),
            (Name.display, Name.display),
            (Name.displayLarge, Name.displayLarge),
        ]
        for (regular, bold) in expected {
            let token = ThemeFont(regular, size: 17, relativeTo: .body)
            XCTAssertEqual(token.fontName(for: .regular), regular, "\(regular) without Bold Text")
            XCTAssertEqual(token.fontName(for: nil), regular, "\(regular) with no legibility weight")
            XCTAssertEqual(token.fontName(for: .bold), bold, "\(regular) under Bold Text")
            XCTAssertNotNil(UIFont(name: bold, size: 17), "\(bold) is bundled and registered")
        }
    }

    /// The reading-text tokens change cut under Bold Text; the display tokens do not.
    func testThemeTokensResolveToAHeavierCutUnderBoldText() {
        let reading: [ThemeFont] = [
            Theme.Typography.body, Theme.Typography.caption, Theme.Typography.headline, Theme.Typography.button,
            Theme.Typography.callout, Theme.Typography.calloutMedium, Theme.Typography.quietAction,
            Theme.Typography.chip, Theme.Typography.sessionButton, Theme.Typography.value,
        ]
        for token in reading {
            XCTAssertNotEqual(token.fontName(for: .bold), token.fontName(for: .regular), "\(token.name) under Bold Text")
        }
        for token in [Theme.Typography.largeTitle, Theme.Typography.title, Theme.Typography.target, Theme.Typography.displayL] {
            XCTAssertEqual(token.fontName(for: .bold), token.name, "\(token.name) is already ExtraBold")
        }
    }

    /// Applied through `.font(_:)`, a token really draws wider under Bold Text: the modifier reads the
    /// environment's legibility weight.
    func testTheModifierDrawsTheBoldTextCut() {
        func width(_ weight: LegibilityWeight) -> CGFloat {
            UIHostingController(rootView: Text("Skip rest Complete").font(Theme.Typography.body).fixedSize()
                .environment(\.legibilityWeight, weight))
                .sizeThatFits(in: CGSize(width: 10_000, height: 10_000)).width
        }
        XCTAssertGreaterThan(width(.bold), width(.regular), "Bold Text must draw Inter SemiBold for body")
    }
}
