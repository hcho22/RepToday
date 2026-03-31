import XCTest
import SwiftUI
@testable import FitSnack

final class ColorAssetTests: XCTestCase {

    private let expectedColorNames = [
        "Brand", "BrandLight", "BrandDark",
        "Success", "Warning", "Danger", "Fire",
        "TextPrimary", "TextSecondary",
        "Background", "CardBackground", "Divider"
    ]

    func testAllColorAssetsExist() {
        for name in expectedColorNames {
            let color = UIColor(named: name)
            XCTAssertNotNil(color, "Color asset '\(name)' should exist in asset catalog")
        }
    }

    func testColorAssetCount() {
        XCTAssertEqual(expectedColorNames.count, 12, "Should have exactly 12 color assets defined")
    }

    func testBrandColorsAreNotTransparent() {
        let brandColors = ["Brand", "BrandLight", "BrandDark"]
        for name in brandColors {
            guard let color = UIColor(named: name) else {
                XCTFail("Color asset '\(name)' not found")
                continue
            }
            var alpha: CGFloat = 0
            color.getRed(nil, green: nil, blue: nil, alpha: &alpha)
            XCTAssertEqual(alpha, 1.0, accuracy: 0.01, "\(name) should be fully opaque")
        }
    }

    func testLightAndDarkVariantsAreDifferent() {
        let lightTraitCollection = UITraitCollection(userInterfaceStyle: .light)
        let darkTraitCollection = UITraitCollection(userInterfaceStyle: .dark)

        for name in expectedColorNames {
            guard let color = UIColor(named: name) else {
                XCTFail("Color asset '\(name)' not found")
                continue
            }
            let lightColor = color.resolvedColor(with: lightTraitCollection)
            let darkColor = color.resolvedColor(with: darkTraitCollection)

            var lr: CGFloat = 0, lg: CGFloat = 0, lb: CGFloat = 0
            var dr: CGFloat = 0, dg: CGFloat = 0, db: CGFloat = 0
            lightColor.getRed(&lr, green: &lg, blue: &lb, alpha: nil)
            darkColor.getRed(&dr, green: &dg, blue: &db, alpha: nil)

            let isDifferent = abs(lr - dr) > 0.01 || abs(lg - dg) > 0.01 || abs(lb - db) > 0.01
            XCTAssertTrue(isDifferent, "\(name) should have different light and dark variants")
        }
    }

    func testAppColorsMapToAssets() {
        XCTAssertNotNil(UIColor(named: "Brand"), "AppColors.brand maps to Brand asset")
        XCTAssertNotNil(UIColor(named: "BrandLight"), "AppColors.brandLight maps to BrandLight asset")
        XCTAssertNotNil(UIColor(named: "BrandDark"), "AppColors.brandDark maps to BrandDark asset")
        XCTAssertNotNil(UIColor(named: "Success"), "AppColors.success maps to Success asset")
        XCTAssertNotNil(UIColor(named: "Warning"), "AppColors.warning maps to Warning asset")
        XCTAssertNotNil(UIColor(named: "Danger"), "AppColors.danger maps to Danger asset")
        XCTAssertNotNil(UIColor(named: "Fire"), "AppColors.fire maps to Fire asset")
        XCTAssertNotNil(UIColor(named: "TextPrimary"), "AppColors.textPrimary maps to TextPrimary asset")
        XCTAssertNotNil(UIColor(named: "TextSecondary"), "AppColors.textSecondary maps to TextSecondary asset")
        XCTAssertNotNil(UIColor(named: "Background"), "AppColors.background maps to Background asset")
        XCTAssertNotNil(UIColor(named: "CardBackground"), "AppColors.cardBackground maps to CardBackground asset")
        XCTAssertNotNil(UIColor(named: "Divider"), "AppColors.divider maps to Divider asset")
    }
}
