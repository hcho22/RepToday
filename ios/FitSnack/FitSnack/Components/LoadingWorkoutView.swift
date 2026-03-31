import SwiftUI

struct LoadingWorkoutView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var rotation: Double = 0
    @State private var pulse = false

    var body: some View {
        VStack(spacing: AppSpacing.lg) {
            Image(systemName: "dumbbell.fill")
                .font(.system(size: 48))
                .foregroundStyle(AppColors.brand)
                .rotationEffect(.degrees(rotation))
                .scaleEffect(pulse ? 1.1 : 0.9)
                .animation(
                    reduceMotion ? nil : .easeInOut(duration: 1).repeatForever(autoreverses: true),
                    value: rotation
                )
                .animation(
                    reduceMotion ? nil : .easeInOut(duration: 0.8).repeatForever(autoreverses: true),
                    value: pulse
                )

            Text("Generating your workout...")
                .font(AppTypography.headline)
                .foregroundStyle(AppColors.textPrimary)

            Text("AI is picking the best exercises for you")
                .font(AppTypography.subheadline)
                .foregroundStyle(AppColors.textSecondary)
        }
        .onAppear {
            if !reduceMotion {
                rotation = 15
                pulse = true
            }
        }
    }
}
