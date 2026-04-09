import SwiftUI
import UIKit

enum AppColors {
    // Primary
    static let brand = adaptive(light: (0.310, 0.275, 0.898), dark: (0.506, 0.549, 0.973))
    static let brandLight = adaptive(light: (0.506, 0.549, 0.973), dark: (0.647, 0.706, 0.988))
    static let brandDark = adaptive(light: (0.216, 0.188, 0.639), dark: (0.388, 0.400, 0.945))

    // Accents
    static let success = adaptive(light: (0.063, 0.725, 0.506), dark: (0.204, 0.827, 0.600))
    static let warning = adaptive(light: (0.961, 0.620, 0.043), dark: (0.984, 0.749, 0.141))
    static let danger = adaptive(light: (0.937, 0.267, 0.267), dark: (0.973, 0.443, 0.443))
    static let fire = adaptive(light: (0.976, 0.451, 0.086), dark: (0.984, 0.573, 0.235))

    // Neutrals
    static let textPrimary = adaptive(light: (0.067, 0.094, 0.153), dark: (0.976, 0.980, 0.984))
    static let textSecondary = adaptive(light: (0.420, 0.447, 0.502), dark: (0.612, 0.639, 0.686))
    static let background = adaptive(light: (0.976, 0.980, 0.984), dark: (0.067, 0.094, 0.153))
    static let cardBackground = adaptive(light: (0.976, 0.980, 0.984), dark: (0.122, 0.161, 0.216))
    static let divider = adaptive(light: (0.898, 0.906, 0.922), dark: (0.216, 0.255, 0.318))

    private static func adaptive(
        light: (CGFloat, CGFloat, CGFloat),
        dark: (CGFloat, CGFloat, CGFloat)
    ) -> Color {
        Color(UIColor { traits in
            switch traits.userInterfaceStyle {
            case .dark:
                UIColor(red: dark.0, green: dark.1, blue: dark.2, alpha: 1.0)
            default:
                UIColor(red: light.0, green: light.1, blue: light.2, alpha: 1.0)
            }
        })
    }
}
