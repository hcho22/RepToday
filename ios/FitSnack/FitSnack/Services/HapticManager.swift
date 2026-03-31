import UIKit

enum HapticManager {
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.impactOccurred()
    }

    static func notification(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(type)
    }

    static func selection() {
        let generator = UISelectionFeedbackGenerator()
        generator.selectionChanged()
    }

    // Convenience impact methods
    static func light() { impact(.light) }
    static func medium() { impact(.medium) }
    static func heavy() { impact(.heavy) }

    // Convenience notification methods
    static func success() { notification(.success) }
    static func warning() { notification(.warning) }
    static func error() { notification(.error) }
}
