import XCTest
import SwiftUI
import UIKit
@testable import RepToday

/// Pins the palette's WCAG contrast so a shade change cannot silently regress it.
///
/// The visual direction is dark only and black first: every text and meaning color must read at 4.5:1
/// on black and on the surfaces it sits on, and every vivid fill carries black content at 4.5:1. The
/// palette is pinned to the design tokens, and the asset catalog's accent colors (what system controls
/// tint with) must mirror `sun`.
///
/// Colors are resolved from `Theme` and the shipped asset catalog under the dark trait collection the
/// app renders with, so these ratios are the ones the app draws rather than a hand-copied table.
final class AccentContrastTests: XCTestCase {

    /// WCAG 2.x AA for body text (Theme.Typography.button, 17pt semibold, is not large text).
    private let textContrast = 4.5

    // MARK: - Traits

    private func traits(_ style: UIUserInterfaceStyle, elevated: Bool = false) -> UITraitCollection {
        UITraitCollection { traits in
            traits.userInterfaceStyle = style
            traits.userInterfaceLevel = elevated ? .elevated : .base
        }
    }

    private var light: UITraitCollection { traits(.light) }
    private var dark: UITraitCollection { traits(.dark) }

    // MARK: - Color math

    private struct RGBA: Equatable {
        var red, green, blue, alpha: Double
    }

    private func asset(_ name: String, _ traits: UITraitCollection) throws -> RGBA {
        let color = try XCTUnwrap(
            UIColor(named: name, in: Bundle(for: AppState.self), compatibleWith: traits),
            "the asset catalog has no color named \(name)"
        )
        return components(color, traits)
    }

    private func components(_ color: UIColor, _ traits: UITraitCollection) -> RGBA {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        color.resolvedColor(with: traits).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return RGBA(red: red, green: green, blue: blue, alpha: alpha)
    }

    /// A `Theme` token as the screen resolves it under `traits`.
    private func token(_ color: Color, _ traits: UITraitCollection) -> RGBA {
        components(UIColor(color), traits)
    }

    /// `foreground` drawn over an opaque `background` (source-over).
    private func composite(_ foreground: RGBA, over background: RGBA) -> RGBA {
        let a = foreground.alpha
        return RGBA(
            red: foreground.red * a + background.red * (1 - a),
            green: foreground.green * a + background.green * (1 - a),
            blue: foreground.blue * a + background.blue * (1 - a),
            alpha: 1
        )
    }

    private func luminance(_ color: RGBA) -> Double {
        func linear(_ channel: Double) -> Double {
            channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(color.red) + 0.7152 * linear(color.green) + 0.0722 * linear(color.blue)
    }

    /// The WCAG contrast ratio of a (possibly translucent) foreground over an opaque background.
    private func contrast(_ foreground: RGBA, on background: RGBA) -> Double {
        let lighter = max(luminance(composite(foreground, over: background)), luminance(background))
        let darker = min(luminance(composite(foreground, over: background)), luminance(background))
        return (lighter + 0.05) / (darker + 0.05)
    }

    private func assertComponents(
        _ actual: RGBA, _ expected: RGBA, _ message: String, file: StaticString = #filePath, line: UInt = #line
    ) {
        let accuracy = 0.5 / 255
        XCTAssertEqual(actual.red, expected.red, accuracy: accuracy, message, file: file, line: line)
        XCTAssertEqual(actual.green, expected.green, accuracy: accuracy, message, file: file, line: line)
        XCTAssertEqual(actual.blue, expected.blue, accuracy: accuracy, message, file: file, line: line)
        XCTAssertEqual(actual.alpha, expected.alpha, accuracy: accuracy, message, file: file, line: line)
    }

    private let black = RGBA(red: 0, green: 0, blue: 0, alpha: 1)

    private func hex(_ value: UInt32) -> RGBA {
        RGBA(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255,
            alpha: 1
        )
    }

    // MARK: - The palette

    /// The palette is the design tokens' (`tokens.json`), value for value.
    func testThePaletteIsTheDesignTokens() {
        let tokens: [(String, Color, UInt32)] = [
            ("black", Theme.Colors.black, 0x000000), ("surface1", Theme.Colors.surface1, 0x131316),
            ("surface2", Theme.Colors.surface2, 0x1D1D22), ("surface3", Theme.Colors.surface3, 0x2C2C33),
            ("line", Theme.Colors.line, 0x2E2E36), ("text1", Theme.Colors.text1, 0xFFFFFF),
            ("text2", Theme.Colors.text2, 0xB9B9C4), ("text3", Theme.Colors.text3, 0x8F8F9B),
            ("sun", Theme.Colors.sun, 0xFFD23F), ("push", Theme.Colors.push, 0xFF6B3D),
            ("pull", Theme.Colors.pull, 0x4D9BFF), ("legs", Theme.Colors.legs, 0x3DDC84),
            ("rest", Theme.Colors.rest, 0xC9A7FF), ("danger", Theme.Colors.danger, 0xFF5468),
            ("sun tint", Theme.Colors.sunTint, 0x2C2409), ("push tint", Theme.Colors.pushTint, 0x2B140C),
            ("pull tint", Theme.Colors.pullTint, 0x0D1E36), ("legs tint", Theme.Colors.legsTint, 0x0C2B1A),
            ("rest tint", Theme.Colors.restTint, 0x241C36), ("art outline", Theme.Colors.artOutline, 0xFFF4E4),
            ("stage base", Theme.Colors.stageBase, 0x0B0B0D),
        ]
        for (name, color, value) in tokens {
            assertComponents(token(color, dark), hex(value), "\(name) is the token value")
        }
        XCTAssertEqual(token(Theme.Colors.scrim, dark).alpha, 0.78, accuracy: 0.5 / 255, "the scrim is black at 78%")
    }

    /// System controls tint with the asset catalog's accent, so it mirrors `sun`; the badge wash is
    /// `sun`'s tint and content on a vivid fill is black.
    func testTheAssetCatalogMirrorsTheTheme() throws {
        for name in ["AccentColor", "AccentFill", "AccentOnElevatedSurface"] {
            assertComponents(try asset(name, dark), hex(0xFFD23F), "\(name) is sun")
            assertComponents(try asset(name, light), hex(0xFFD23F), "\(name) is sun in every appearance")
        }
        assertComponents(try asset("AccentBadgeFill", dark), hex(0x2C2409), "the badge wash is sun's tint")
        assertComponents(try asset("OnAccentSecondary", dark), black, "secondary content on a vivid fill is black")
    }

    // MARK: - Contrast

    /// A vivid fill always carries black content (DESIGN "Color"), at 4.5:1 or better.
    func testBlackOnEveryVividFillReachesTextContrast() {
        let fills: [(String, Color)] = [
            ("sun", Theme.Colors.sun), ("push", Theme.Colors.push), ("pull", Theme.Colors.pull),
            ("legs", Theme.Colors.legs), ("rest", Theme.Colors.rest), ("danger", Theme.Colors.danger),
        ]
        for (name, fill) in fills {
            XCTAssertGreaterThanOrEqual(
                contrast(token(Theme.Colors.onAccent, dark), on: token(fill, dark)), textContrast,
                "black on \(name) must reach 4.5:1"
            )
        }
    }

    /// Every text and meaning color reads at 4.5:1 on black and on the card and control surfaces.
    func testTextAndMeaningColorsReachTextContrastOnEverySurface() {
        let foregrounds: [(String, Color)] = [
            ("text1", Theme.Colors.text1), ("text2", Theme.Colors.text2), ("text3", Theme.Colors.text3),
            ("sun", Theme.Colors.sun), ("push", Theme.Colors.push), ("pull", Theme.Colors.pull),
            ("legs", Theme.Colors.legs), ("rest", Theme.Colors.rest), ("danger", Theme.Colors.danger),
        ]
        let surfaces: [(String, Color)] = [
            ("black", Theme.Colors.black), ("surface1", Theme.Colors.surface1), ("surface2", Theme.Colors.surface2),
        ]
        for (fore, foreground) in foregrounds {
            for (back, background) in surfaces {
                XCTAssertGreaterThanOrEqual(
                    contrast(token(foreground, dark), on: token(background, dark)), textContrast,
                    "\(fore) on \(back) must reach 4.5:1"
                )
            }
        }
    }

    /// Selected option cards and the Premium badge put `sun` text on its tint over a card.
    func testSunReadsOnItsTint() {
        XCTAssertGreaterThanOrEqual(
            contrast(token(Theme.Colors.accent, dark), on: token(Theme.Colors.accentBadgeFill, dark)), textContrast,
            "the accent badge caption on its wash must reach 4.5:1"
        )
        XCTAssertGreaterThanOrEqual(
            contrast(token(Theme.Colors.text1, dark), on: token(Theme.Colors.sunTint, dark)), textContrast,
            "a selected option card's title must reach 4.5:1"
        )
    }
}
