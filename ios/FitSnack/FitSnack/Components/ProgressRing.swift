import SwiftUI

struct ProgressRing<Content: View>: View {
    let progress: Double
    var ringColor: Color = Theme.Colors.brand
    var trackColor: Color = Theme.Colors.divider
    var lineWidth: CGFloat = 8
    var size: CGFloat = 100
    @ViewBuilder var overlay: () -> Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle()
                .stroke(trackColor, lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: min(progress, 1.0))
                .stroke(ringColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(reduceMotion ? .none : .easeInOut(duration: 0.3), value: progress)

            overlay()
        }
        .frame(width: size, height: size)
    }
}

extension ProgressRing where Content == EmptyView {
    init(
        progress: Double,
        ringColor: Color = Theme.Colors.brand,
        trackColor: Color = Theme.Colors.divider,
        lineWidth: CGFloat = 8,
        size: CGFloat = 100
    ) {
        self.progress = progress
        self.ringColor = ringColor
        self.trackColor = trackColor
        self.lineWidth = lineWidth
        self.size = size
        self.overlay = { EmptyView() }
    }
}
