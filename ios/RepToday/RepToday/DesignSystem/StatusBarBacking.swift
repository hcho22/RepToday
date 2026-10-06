import SwiftUI

extension View {
    /// Paints the screen's background behind the status bar, so content scrolled up past the top of a
    /// screen slides under a solid band instead of being drawn beneath the clock and battery.
    ///
    /// For a full-screen surface with no navigation bar, whose `ScrollView` reaches the top safe-area
    /// edge (the Today, Progress and Profile tabs, and the session-complete screen). A screen with a
    /// navigation bar already gets the system's own backing and does not need it. The band is the same
    /// `Theme.Colors.background` the screen sits on, so an unscrolled screen looks exactly as it did; it
    /// takes no touches and is invisible to VoiceOver.
    func statusBarBacking() -> some View {
        overlay {
            // Either the screen's frame already reaches the top of the display (a background that
            // ignores the safe area makes it so), and the reader reports the status bar as its top
            // inset; or the frame starts below the status bar, the reader reports none, and the
            // zero-height band grows up into the inset it touches. Both paint exactly the band.
            GeometryReader { proxy in
                Theme.Colors.background
                    .frame(height: proxy.safeAreaInsets.top)
                    .ignoresSafeArea(edges: .top)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}
