import XCTest
import UIKit
@testable import RepToday

/// Pins the accent palette's WCAG contrast so a shade change cannot silently regress it.
///
/// Dark appearance needs two accents: one dark enough that white labels on it reach 4.5:1
/// (`AccentFill`), and one light enough to read as text on dark surfaces (`AccentColor`). Contrast is a
/// function of luminance alone, and those two needs ask for disjoint luminances, so no single shade can
/// do both - see `artifacts/reports/dark-accent-contrast/validation.md`.
///
/// Every color is resolved from the shipped asset catalog and every surface from the system's own
/// dynamic colors, under the trait collection the screen actually renders with, so these ratios are
/// the ones the app draws rather than a hand-copied table.
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
    /// A presented sheet in dark appearance, where the system lifts its surfaces.
    private var darkElevated: UITraitCollection { traits(.dark, elevated: true) }

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

    private func system(_ color: UIColor, _ traits: UITraitCollection) -> RGBA {
        components(color, traits)
    }

    private let white = RGBA(red: 1, green: 1, blue: 1, alpha: 1)

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

    // MARK: - White on the accent fill

    /// Every filled accent surface carries white content: prominent buttons, selected chips, the coach's
    /// user bubble, the paywall plan card. That label must reach 4.5:1 in both appearances.
    func testWhiteLabelsOnTheAccentFillReachTextContrast() throws {
        for (name, traits) in [("light", light), ("dark", dark), ("dark sheet", darkElevated)] {
            let fill = try asset("AccentFill", traits)
            XCTAssertGreaterThanOrEqual(
                contrast(white, on: fill), textContrast,
                "white on AccentFill (\(name)) must reach 4.5:1"
            )
            XCTAssertGreaterThanOrEqual(
                contrast(try asset("OnAccentSecondary", traits), on: fill), textContrast,
                "OnAccentSecondary on AccentFill (\(name)) - the paywall plan's price line - must reach 4.5:1"
            )
        }
    }

    // MARK: - Accent as text

    /// The text-weight accent stays legible on every dark surface it is drawn on as small text: the
    /// screen background, cards and inset-grouped rows, and a presented sheet's background.
    func testAccentTextReachesTextContrastOnEverySurfaceItSitsOn() throws {
        let surfaces: [(String, UITraitCollection, UIColor)] = [
            ("light background", light, .systemBackground),
            ("light surface", light, .secondarySystemBackground),
            ("dark background", dark, .systemBackground),
            ("dark surface/card", dark, .secondarySystemBackground),
            ("dark grouped row", dark, .secondarySystemGroupedBackground),
            ("dark sheet background", darkElevated, .systemBackground),
        ]
        for (name, traits, surface) in surfaces {
            XCTAssertGreaterThanOrEqual(
                contrast(try asset("AccentColor", traits), on: system(surface, traits)), textContrast,
                "AccentColor text on the \(name) must reach 4.5:1"
            )
        }
    }

    /// The injury screen's Retry, presented as the coach's sheet, sits on a raised #2C2C2E row in dark
    /// appearance, where the plain accent falls short.
    func testAccentOnElevatedSurfaceReachesTextContrastOnARaisedRow() throws {
        for (name, traits) in [("light", light), ("dark", dark), ("dark sheet", darkElevated)] {
            XCTAssertGreaterThanOrEqual(
                contrast(
                    try asset("AccentOnElevatedSurface", traits),
                    on: system(.secondarySystemBackground, traits)
                ),
                textContrast,
                "AccentOnElevatedSurface on a \(name) row must reach 4.5:1"
            )
        }
    }

    /// The Profile "Premium" badge: an accent caption on a faint accent wash over a card.
    func testPremiumBadgeCaptionReachesTextContrastOnItsWash() throws {
        for (name, traits) in [("light", light), ("dark", dark)] {
            let wash = composite(
                try asset("AccentBadgeFill", traits),
                over: system(.secondarySystemBackground, traits)
            )
            XCTAssertGreaterThanOrEqual(
                contrast(try asset("AccentColor", traits), on: wash), textContrast,
                "the accent badge caption on its wash (\(name)) must reach 4.5:1"
            )
        }
    }

    // MARK: - What must not move

    /// Light appearance is the brand's reference and already passes, so the new tokens are the accent
    /// itself there; dark `AccentColor` keeps its shade for text, icons, links and controls.
    func testLightAppearanceAndTheDarkTextAccentAreUnchanged() throws {
        let lightAccent = RGBA(red: 0.180, green: 0.310, blue: 0.380, alpha: 1)
        let darkAccent = RGBA(red: 0.470, green: 0.560, blue: 0.620, alpha: 1)

        assertComponents(try asset("AccentColor", light), lightAccent, "light AccentColor is the brand reference")
        assertComponents(try asset("AccentColor", dark), darkAccent, "dark AccentColor stays the text-weight accent")
        assertComponents(try asset("AccentFill", light), lightAccent, "light AccentFill must equal the accent")
        assertComponents(
            try asset("AccentOnElevatedSurface", light), lightAccent, "light AccentOnElevatedSurface must equal the accent"
        )

        var lightWash = lightAccent
        lightWash.alpha = 0.12
        assertComponents(try asset("AccentBadgeFill", light), lightWash, "light badge wash stays the accent at 12%")
        var darkWash = darkAccent
        darkWash.alpha = 0.08
        assertComponents(try asset("AccentBadgeFill", dark), darkWash, "dark badge wash is the dark accent at 8%")

        var lightSecondary = white
        lightSecondary.alpha = 0.9
        assertComponents(try asset("OnAccentSecondary", light), lightSecondary, "light secondary on-accent stays 90% white")
    }

    // MARK: - Every prominent button uses the fill

    /// `.borderedProminent` fills with the app tint, which is the text-weight accent. Every prominent
    /// button must go through `accentFilledButtonStyle()` instead, so a new one cannot quietly bring back
    /// a 3.4:1 label.
    func testNoViewAppliesBorderedProminentOutsideTheAccentFillStyle() throws {
        // Built by concatenation so this guard's own source never contains the literal it hunts for.
        let rawStyle = "buttonStyle(" + ".borderedProminent)"
        let helperFileName = "AccentFilledButtonStyle.swift"

        // `<repo>/ios/RepToday/RepTodayTests/AccentContrastTests.swift` -> `<repo>/ios/RepToday/RepToday`.
        let appSources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("RepToday")
        let swiftFiles = (FileManager.default.enumerator(at: appSources, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" }) ?? []
        XCTAssertFalse(swiftFiles.isEmpty, "found no app sources under \(appSources.path) - the guard is scanning the wrong place")

        var helperAppliesTheStyle = false
        for file in swiftFiles {
            let source = try String(contentsOf: file, encoding: .utf8)
            if file.lastPathComponent == helperFileName {
                helperAppliesTheStyle = source.contains(rawStyle)
                continue
            }
            XCTAssertFalse(
                source.contains(rawStyle),
                """
                \(file.lastPathComponent) applies \(rawStyle) directly, which fills with the text-weight \
                accent and puts its white label at 3.4:1 in dark appearance. Use \
                `.accentFilledButtonStyle()` instead.
                """
            )
        }
        // Positive control, so a renamed helper cannot make the scan pass vacuously.
        XCTAssertTrue(helperAppliesTheStyle, "\(helperFileName) no longer applies \(rawStyle) - update this guard")
    }
}
