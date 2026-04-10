import SwiftUI
import Lottie

/// Displays a Lottie exercise animation when available, falling back to an SF Symbol icon.
///
/// Animation files are loaded from `Resources/Animations/{exerciseId}.json`.
/// The view loops continuously and shows a loading indicator while the animation loads.
struct ExerciseDemoView: View {
    let exerciseId: String
    let fallbackIcon: String
    var size: CGFloat = 100

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if reduceMotion || !animationExists {
                fallbackView
            } else {
                LottieView {
                    LottieAnimation.named(exerciseId, subdirectory: "Animations")
                } placeholder: {
                    ProgressView()
                        .controlSize(.regular)
                        .tint(AppColors.brand)
                        .accessibilityLabel("Loading exercise animation")
                }
                .looping()
                .reloadAnimationTrigger(exerciseId, showPlaceholder: true)
                .accessibilityLabel("Exercise demonstration animation")
            }
        }
        .frame(width: size, height: size)
    }

    // MARK: - Fallback

    private var animationExists: Bool {
        Bundle.main.url(
            forResource: exerciseId,
            withExtension: "json",
            subdirectory: "Animations"
        ) != nil
    }

    private var fallbackView: some View {
        Image(systemName: fallbackIcon)
            .font(.system(size: size * 0.64))
            .foregroundStyle(AppColors.brand)
            .accessibilityLabel("Exercise icon")
    }
}
