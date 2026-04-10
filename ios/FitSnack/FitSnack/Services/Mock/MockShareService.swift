import SwiftUI

@MainActor
final class MockShareService: ShareServiceProtocol {
    func generateShareCard(workout: Workout, stats: GamificationStats, isPremium: Bool) -> UIImage? {
        let cardView = ShareWorkoutCardView(
            workout: workout,
            stats: stats,
            showWatermark: !isPremium
        )
        let renderer = ImageRenderer(content: cardView)
        renderer.scale = 3.0
        return renderer.uiImage
    }
}
