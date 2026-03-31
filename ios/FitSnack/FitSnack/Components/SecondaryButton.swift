import SwiftUI

struct SecondaryButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
        }
        .buttonStyle(SecondaryButtonStyle())
        .accessibilityLabel(title)
    }
}

#Preview {
    SecondaryButton(title: "Skip") {}
        .padding()
}
