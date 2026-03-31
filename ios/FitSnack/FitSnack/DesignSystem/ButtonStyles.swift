import SwiftUI

struct PrimaryButtonStyle: ButtonStyle {
    var isEnabled: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppTypography.button)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: AppSpacing.buttonHeight)
            .background(isEnabled ? AppColors.brand : AppColors.brand.opacity(0.4))
            .clipShape(RoundedRectangle(cornerRadius: AppSpacing.cornerRadius))
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    var isEnabled: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        let foreground = isEnabled ? AppColors.brand : AppColors.brand.opacity(0.4)
        configuration.label
            .font(AppTypography.button)
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity)
            .frame(height: AppSpacing.buttonHeight)
            .background(.clear)
            .overlay(
                RoundedRectangle(cornerRadius: AppSpacing.cornerRadius)
                    .stroke(foreground, lineWidth: 1.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: AppSpacing.cornerRadius))
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.7 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}
