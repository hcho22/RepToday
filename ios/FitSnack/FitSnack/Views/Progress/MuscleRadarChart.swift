import SwiftUI

struct MuscleRadarChart: View {
    let data: [FocusGroup: Double]

    private let axes: [FocusGroup] = FocusGroup.allCases
    private let idealDistribution: [FocusGroup: Double] = [
        .push: 0.7, .pull: 0.7, .squat: 0.7,
        .hinge: 0.7, .core: 0.7, .cardio: 0.7, .mobility: 0.7,
    ]

    var body: some View {
        FitSnackCard {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                Text("Muscle Balance")
                    .font(AppTypography.headline)
                    .foregroundStyle(AppColors.textPrimary)

                Text("Last 30 days")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)

                GeometryReader { geo in
                    let size = min(geo.size.width, geo.size.height)
                    let center = CGPoint(x: geo.size.width / 2, y: size / 2)
                    let radius = size / 2 - 36

                    ZStack {
                        // Grid rings
                        ForEach([0.25, 0.5, 0.75, 1.0], id: \.self) { level in
                            radarPath(values: axes.map { _ in level }, center: center, radius: radius)
                                .stroke(AppColors.divider, lineWidth: 1)
                        }

                        // Axis lines
                        ForEach(0..<axes.count, id: \.self) { i in
                            Path { path in
                                path.move(to: center)
                                path.addLine(to: point(for: i, value: 1.0, center: center, radius: radius))
                            }
                            .stroke(AppColors.divider, lineWidth: 1)
                        }

                        // Ideal distribution overlay
                        radarPath(values: axes.map { idealDistribution[$0] ?? 0.7 }, center: center, radius: radius)
                            .fill(AppColors.textSecondary.opacity(0.08))

                        radarPath(values: axes.map { idealDistribution[$0] ?? 0.7 }, center: center, radius: radius)
                            .stroke(AppColors.textSecondary.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))

                        // Actual data
                        let values = axes.map { data[$0] ?? 0 }

                        radarPath(values: values, center: center, radius: radius)
                            .fill(AppColors.brand.opacity(0.15))

                        radarPath(values: values, center: center, radius: radius)
                            .stroke(AppColors.brand, lineWidth: 2)

                        // Data points
                        ForEach(0..<axes.count, id: \.self) { i in
                            Circle()
                                .fill(AppColors.brand)
                                .frame(width: 6, height: 6)
                                .position(point(for: i, value: values[i], center: center, radius: radius))
                        }

                        // Axis labels
                        ForEach(0..<axes.count, id: \.self) { i in
                            let labelPoint = point(for: i, value: 1.0, center: center, radius: radius + 20)
                            Text(axisLabel(axes[i]))
                                .font(AppTypography.caption)
                                .foregroundStyle(AppColors.textSecondary)
                                .position(labelPoint)
                        }
                    }
                }
                .frame(height: 240)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilityDescription)
            }
        }
    }

    // MARK: - Geometry

    private func angle(for index: Int) -> Double {
        let slice = 2 * .pi / Double(axes.count)
        return slice * Double(index) - .pi / 2
    }

    private func point(for index: Int, value: Double, center: CGPoint, radius: CGFloat) -> CGPoint {
        let a = angle(for: index)
        let clampedValue = min(max(value, 0), 1.0)
        return CGPoint(
            x: center.x + CGFloat(cos(a)) * radius * clampedValue,
            y: center.y + CGFloat(sin(a)) * radius * clampedValue
        )
    }

    private func radarPath(values: [Double], center: CGPoint, radius: CGFloat) -> Path {
        Path { path in
            for (i, value) in values.enumerated() {
                let p = point(for: i, value: value, center: center, radius: radius)
                if i == 0 {
                    path.move(to: p)
                } else {
                    path.addLine(to: p)
                }
            }
            path.closeSubpath()
        }
    }

    private func axisLabel(_ group: FocusGroup) -> String {
        switch group {
        case .push: "Push"
        case .pull: "Pull"
        case .squat: "Squat"
        case .hinge: "Hinge"
        case .core: "Core"
        case .cardio: "Cardio"
        case .mobility: "Mobility"
        }
    }

    private var accessibilityDescription: String {
        let items = axes.map { group in
            "\(axisLabel(group)): \(Int((data[group] ?? 0) * 100))%"
        }
        return "Muscle balance chart. " + items.joined(separator: ", ")
    }
}
