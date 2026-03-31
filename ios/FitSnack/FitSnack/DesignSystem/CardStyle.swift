import SwiftUI

struct CardModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .padding(AppSpacing.cardPadding)
            .background(AppColors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusCard))
            .shadow(
                color: colorScheme == .dark ? .white.opacity(0.04) : .black.opacity(0.06),
                radius: colorScheme == .dark ? 4 : 8,
                x: 0,
                y: colorScheme == .dark ? 1 : 2
            )
    }
}

extension View {
    func cardStyle() -> some View {
        modifier(CardModifier())
    }
}
