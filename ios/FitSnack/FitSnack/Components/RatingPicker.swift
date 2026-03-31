import SwiftUI

struct RatingPicker: View {
    @Binding var selectedRating: Int
    private let emojis = ["😫", "😕", "😐", "😊", "🤩"]

    var body: some View {
        HStack(spacing: AppSpacing.md) {
            ForEach(1...5, id: \.self) { rating in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedRating = rating
                    }
                    HapticManager.impact(.light)
                } label: {
                    Text(emojis[rating - 1])
                        .font(.system(size: 36))
                        .scaleEffect(selectedRating == rating ? 1.2 : 1.0)
                        .opacity(selectedRating == rating ? 1.0 : 0.5)
                        .animation(.easeInOut(duration: 0.2), value: selectedRating)
                }
                .accessibilityLabel("Rate \(rating) out of 5")
            }
        }
    }
}
