import SwiftUI

@MainActor
protocol ShareServiceProtocol {
    func generateShareCard(workout: Workout, stats: GamificationStats, isPremium: Bool) -> UIImage?
}
