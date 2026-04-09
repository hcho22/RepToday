import Foundation

/// Determines which movement pattern combination to use for today's workout
/// based on staleness scoring and recent history.
struct MovementPatternRotation {

    /// Day rotation templates.
    /// Each template defines primary and secondary movement patterns.
    enum DayTemplate: CaseIterable {
        /// Day A: Push + Core
        case pushCore
        /// Day B: Pull + Hinge
        case pullHinge
        /// Day C: Squat + Primal
        case squatPrimal
        /// Day D: Full Body Circuit
        case fullBody

        var primaryPatterns: [MovementPattern] {
            switch self {
            case .pushCore: [.pushHorizontal, .pushVertical]
            case .pullHinge: [.pullHorizontal, .pullVertical, .hinge]
            case .squatPrimal: [.squat, .lunge, .primal]
            case .fullBody: [.pushHorizontal, .pullHorizontal, .squat, .hinge]
            }
        }

        var secondaryPatterns: [MovementPattern] {
            switch self {
            case .pushCore: [.coreAntiExtension, .coreFlexion, .coreRotation]
            case .pullHinge: [.carry, .coreCompression]
            case .squatPrimal: [.mobility, .coreRotation]
            case .fullBody: [.cardio, .coreFlexion]
            }
        }

        var allPatterns: [MovementPattern] {
            primaryPatterns + secondaryPatterns
        }

        var displayName: String {
            switch self {
            case .pushCore: "Push + Core"
            case .pullHinge: "Pull + Hinge"
            case .squatPrimal: "Squat + Primal"
            case .fullBody: "Full Body Circuit"
            }
        }
    }

    /// Selects the day template with the highest aggregate staleness score.
    /// Never repeats yesterday's primary focus group unless it's the only option.
    func selectTemplate(
        stalenessScores: [MovementPattern: Int],
        history: [Workout]
    ) -> DayTemplate {
        let yesterdayFocus = lastWorkoutPrimaryFocus(history: history)

        let scored = DayTemplate.allCases.map { template -> (DayTemplate, Int) in
            let score = template.primaryPatterns.reduce(0) { sum, pattern in
                let staleness = stalenessScores[pattern] ?? Int.max
                return sum + min(staleness, 365) // Cap to prevent Int overflow
            }
            return (template, score)
        }

        let sorted = scored.sorted { $0.1 > $1.1 }

        // Prefer highest staleness, but skip if it repeats yesterday's focus
        if let yesterdayFocus {
            for (template, _) in sorted {
                let templateFocuses = Set(template.primaryPatterns.map(\.focusGroup))
                if !templateFocuses.contains(yesterdayFocus) {
                    return template
                }
            }
        }

        // All templates repeat yesterday's focus, or no history — pick highest staleness
        return sorted.first?.0 ?? .fullBody
    }

    /// Returns the primary focus group of the most recent workout, if any.
    func lastWorkoutPrimaryFocus(history: [Workout]) -> FocusGroup? {
        guard let last = history.first else { return nil }
        let patterns = last.mainBlocks
            .flatMap(\.exercises)
            .map(\.exercise.movementPattern)

        // Most frequent focus group
        var counts: [FocusGroup: Int] = [:]
        for pattern in patterns {
            counts[pattern.focusGroup, default: 0] += 1
        }
        return counts.max(by: { $0.value < $1.value })?.key
    }
}
