import XCTest
import SwiftUI
@testable import FitSnack

final class ColorAssetTests: XCTestCase {

    func testColorCount() {
        let colors: [Color] = [
            AppColors.brand, AppColors.brandLight, AppColors.brandDark,
            AppColors.success, AppColors.warning, AppColors.danger, AppColors.fire,
            AppColors.textPrimary, AppColors.textSecondary,
            AppColors.background, AppColors.cardBackground, AppColors.divider
        ]
        XCTAssertEqual(colors.count, 12, "Should have exactly 12 colors defined")
    }

    func testBrandColorsAreNotTransparent() {
        let brandColors: [(String, Color)] = [
            ("brand", AppColors.brand),
            ("brandLight", AppColors.brandLight),
            ("brandDark", AppColors.brandDark)
        ]
        for (name, color) in brandColors {
            let uiColor = UIColor(color)
            var alpha: CGFloat = 0
            uiColor.getRed(nil, green: nil, blue: nil, alpha: &alpha)
            XCTAssertEqual(alpha, 1.0, accuracy: 0.01, "\(name) should be fully opaque")
        }
    }

    func testLightAndDarkVariantsAreDifferent() {
        let lightTraits = UITraitCollection(userInterfaceStyle: .light)
        let darkTraits = UITraitCollection(userInterfaceStyle: .dark)

        let colors: [(String, Color)] = [
            ("brand", AppColors.brand),
            ("brandLight", AppColors.brandLight),
            ("brandDark", AppColors.brandDark),
            ("success", AppColors.success),
            ("warning", AppColors.warning),
            ("danger", AppColors.danger),
            ("fire", AppColors.fire),
            ("textPrimary", AppColors.textPrimary),
            ("textSecondary", AppColors.textSecondary),
            ("background", AppColors.background),
            ("cardBackground", AppColors.cardBackground),
            ("divider", AppColors.divider)
        ]

        for (name, color) in colors {
            let uiColor = UIColor(color)
            let lightColor = uiColor.resolvedColor(with: lightTraits)
            let darkColor = uiColor.resolvedColor(with: darkTraits)

            var lr: CGFloat = 0, lg: CGFloat = 0, lb: CGFloat = 0
            var dr: CGFloat = 0, dg: CGFloat = 0, db: CGFloat = 0
            lightColor.getRed(&lr, green: &lg, blue: &lb, alpha: nil)
            darkColor.getRed(&dr, green: &dg, blue: &db, alpha: nil)

            let isDifferent = abs(lr - dr) > 0.01 || abs(lg - dg) > 0.01 || abs(lb - db) > 0.01
            XCTAssertTrue(isDifferent, "\(name) should have different light and dark variants")
        }
    }
}
