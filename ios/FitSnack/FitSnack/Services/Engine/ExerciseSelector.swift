import Foundation

/// Selects exercises from a filtered pool using staleness scoring, variety enforcement,
/// progression chain integration, and auto-advancement detection.
struct ExerciseSelector {

    // MARK: - Staleness Scoring

    /// Returns days since each movement pattern was last worked, based on workout history.
    /// Patterns never worked return `Int.max` (highest staleness).
    func stalenessScores(history: [Workout], referenceDate: Date = Date()) -> [MovementPattern: Int] {
        var lastWorked: [MovementPattern: Date] = [:]

        for workout in history {
            guard let completedAt = workout.completedAt ?? Optional(workout.createdAt) else { continue }
            for block in workout.mainBlocks {
                for we in block.exercises {
                    let pattern = we.exercise.movementPattern
                    if let existing = lastWorked[pattern] {
                        if completedAt > existing { lastWorked[pattern] = completedAt }
                    } else {
                        lastWorked[pattern] = completedAt
                    }
                }
            }
        }

        var scores: [MovementPattern: Int] = [:]
        let calendar = Calendar.current
        for pattern in MovementPattern.allCases {
            if let date = lastWorked[pattern] {
                scores[pattern] = max(0, calendar.dateComponents([.day], from: date, to: referenceDate).day ?? 0)
            } else {
                scores[pattern] = Int.max
            }
        }
        return scores
    }

    // MARK: - Variety Enforcement

    /// Returns exercise IDs used in the last N workouts (default 3).
    func recentExerciseIds(history: [Workout], lookback: Int = 3) -> Set<String> {
        var ids = Set<String>()
        for workout in history.prefix(lookback) {
            for block in workout.mainBlocks {
                for we in block.exercises {
                    ids.insert(we.exerciseId)
                }
            }
        }
        return ids
    }

    // MARK: - Progression Chain Integration

    /// Selects the exercise at the user's current chain level from a set of exercises
    /// sharing the same `progressionChainId`. Falls back to the lowest level if the
    /// user's level exceeds available exercises.
    func selectAtChainLevel(
        exercises: [Exercise],
        chainId: String,
        progressionLevels: [String: Int]
    ) -> Exercise? {
        let chainExercises = exercises
            .filter { $0.progressionChainId == chainId }
            .sorted { ($0.progressionOrder ?? 0) < ($1.progressionOrder ?? 0) }

        guard !chainExercises.isEmpty else { return nil }

        let userLevel = progressionLevels[chainId] ?? 1
        return chainExercises.first { ($0.progressionOrder ?? 1) == userLevel }
            ?? chainExercises.last
    }

    // MARK: - Auto-advancement Detection

    /// Checks if the user has met the advancement criteria for an exercise based on
    /// their recent set log data. Returns `true` if the user should advance to the
    /// next progression level.
    func shouldAdvance(
        exercise: Exercise,
        recentSetLogs: [SetLog]
    ) -> Bool {
        guard let criteria = exercise.advancementCriteria else { return false }

        // Parse criteria like "3x10 for 2 sessions" → need 2 sessions where all sets hit 10 reps
        // For now, simple heuristic: if all recent completed sets hit the target reps,
        // and there are at least 6 completed sets (roughly 2 sessions × 3 sets), advance.
        let completedSets = recentSetLogs.filter { $0.completed }
        guard completedSets.count >= 6 else { return false }

        // Check if target reps specified in criteria
        if let targetReps = parseTargetReps(from: criteria) {
            return completedSets.allSatisfy { ($0.reps ?? 0) >= targetReps }
        }

        // Default: advance if consistently completing all sets
        return true
    }

    // MARK: - Exercise Selection with All Heuristics

    /// Selects exercises for given movement patterns, applying variety enforcement and
    /// progression chain awareness.
    func select(
        from exercises: [Exercise],
        patterns: [MovementPattern],
        count: Int,
        history: [Workout],
        progressionLevels: [String: Int],
        usedIds: inout Set<String>
    ) -> [Exercise] {
        let recentIds = recentExerciseIds(history: history)
        var selected: [Exercise] = []

        for pattern in patterns {
            let candidates = exercises
                .filter { $0.movementPattern == pattern }
                .filter { !usedIds.contains($0.id) }
                .filter { !recentIds.contains($0.id) }

            // Group by progression chain; pick at user's level when possible
            var chainPicked = Set<String>()
            for candidate in candidates {
                guard selected.count < count else { break }
                if let chainId = candidate.progressionChainId, !chainPicked.contains(chainId) {
                    if let chainExercise = selectAtChainLevel(
                        exercises: candidates, chainId: chainId, progressionLevels: progressionLevels
                    ), !usedIds.contains(chainExercise.id) {
                        selected.append(chainExercise)
                        usedIds.insert(chainExercise.id)
                        chainPicked.insert(chainId)
                        continue
                    }
                }
                selected.append(candidate)
                usedIds.insert(candidate.id)
            }

            // If variety enforcement left us empty for this pattern, relax it
            if selected.isEmpty || !selected.contains(where: { $0.movementPattern == pattern }) {
                let relaxed = exercises
                    .filter { $0.movementPattern == pattern && !usedIds.contains($0.id) }
                if let pick = relaxed.first {
                    selected.append(pick)
                    usedIds.insert(pick.id)
                }
            }
        }

        return Array(selected.prefix(count))
    }

    // MARK: - Private

    private func parseTargetReps(from criteria: String) -> Int? {
        // Matches patterns like "3x10" or "3x12"
        let pattern = #/(\d+)x(\d+)/#
        guard let match = criteria.firstMatch(of: pattern) else { return nil }
        return Int(match.2)
    }
}
