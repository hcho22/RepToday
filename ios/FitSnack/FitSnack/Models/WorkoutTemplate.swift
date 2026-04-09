import Foundation

struct WorkoutTemplate: Codable, Identifiable {
    let id: String
    let durationMinutes: Int
    let name: String
    let warmupTimeSeconds: Int
    let cooldownTimeSeconds: Int
    let blockDefinitions: [BlockDefinition]

    struct BlockDefinition: Codable {
        let type: BlockType
        let exerciseCount: Int
        let sets: Int
        let workSeconds: Int?
        let restBetweenSetsSeconds: Int
        let restBetweenExercisesSeconds: Int
        let rounds: Int?
        let patternCount: Int
    }
}

extension WorkoutTemplate {
    /// Estimated total duration in seconds based on template structure.
    var estimatedTotalSeconds: Int {
        let blockSeconds = blockDefinitions.reduce(0) { total, block in
            total + block.estimatedDurationSeconds
        }
        return warmupTimeSeconds + blockSeconds + cooldownTimeSeconds
    }
}

extension WorkoutTemplate.BlockDefinition {
    /// Estimated block duration in seconds.
    ///
    /// For round-based blocks (`rounds != nil`): each round cycles through all exercises,
    /// each performing one work+rest interval.
    ///
    /// For set-based blocks: each exercise performs `sets` work+rest intervals,
    /// with additional rest between exercises.
    var estimatedDurationSeconds: Int {
        let work = workSeconds ?? 30
        let rounds = rounds ?? 1
        return rounds * exerciseCount * sets * (work + restBetweenSetsSeconds)
    }
}
