import SwiftUI

struct PrimaryButton: View {
    let title: String
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
        }
        .buttonStyle(PrimaryButtonStyle(isEnabled: isEnabled))
        .disabled(!isEnabled)
        .accessibilityLabel(title)
    }
}

#Preview {
    PrimaryButton(title: "Get Started") {}
        .padding()
}
