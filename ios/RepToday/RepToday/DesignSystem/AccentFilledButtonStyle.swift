import SwiftUI

extension View {
    /// The app's filled primary button: `.borderedProminent` filled with `Theme.Colors.accentFill`
    /// rather than the app tint, so its white label keeps 4.5:1 in dark appearance.
    ///
    /// Every prominent button goes through here; `AccentContrastTests` fails the build if a view
    /// applies `.borderedProminent` directly, since that would fill with the text-weight accent.
    func accentFilledButtonStyle() -> some View {
        buttonStyle(.borderedProminent)
            .tint(Theme.Colors.accentFill)
    }
}
