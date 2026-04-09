import Foundation

struct Exercise: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let displayName: String
    let description: String
    let instructions: [String]
    let commonMistakes: [String]

    let muscleGroups: MuscleGroups
    let movementPattern: MovementPattern
    let category: ExerciseCategory
    let difficulty: Int
    let equipment: [Equipment]
    let isUnilateral: Bool

    let defaultReps: Int?
    let defaultDurationSeconds: Int?
    let defaultSets: Int
    let restBetweenSetsSeconds: Int
    let estimatedTimePerSetSeconds: Int

    let regressions: [String]
    let progressions: [String]

    let metValue: Double
    let tags: [String]

    // Phase 2 — progression chain fields (US-A03)
    let progressionChainId: String?
    let progressionOrder: Int?
    let advancementCriteria: String?
    let athleteSource: [String]?
    let apartmentFriendly: Bool?

    struct MuscleGroups: Codable, Hashable {
        let primary: [MuscleGroup]
        let secondary: [MuscleGroup]
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, displayName, description, instructions, commonMistakes
        case muscleGroups, movementPattern, category, difficulty, equipment, isUnilateral
        case defaultReps, defaultDurationSeconds, defaultSets, restBetweenSetsSeconds, estimatedTimePerSetSeconds
        case regressions, progressions, metValue, tags
        case progressionChainId, progressionOrder, advancementCriteria, athleteSource, apartmentFriendly
    }

    init(
        id: String, name: String, displayName: String,
        description: String, instructions: [String], commonMistakes: [String],
        muscleGroups: MuscleGroups, movementPattern: MovementPattern,
        category: ExerciseCategory, difficulty: Int,
        equipment: [Equipment], isUnilateral: Bool,
        defaultReps: Int?, defaultDurationSeconds: Int?,
        defaultSets: Int, restBetweenSetsSeconds: Int,
        estimatedTimePerSetSeconds: Int,
        regressions: [String], progressions: [String],
        metValue: Double, tags: [String],
        progressionChainId: String? = nil,
        progressionOrder: Int? = nil,
        advancementCriteria: String? = nil,
        athleteSource: [String]? = nil,
        apartmentFriendly: Bool? = nil
    ) {
        self.id = id
        self.name = name
        self.displayName = displayName
        self.description = description
        self.instructions = instructions
        self.commonMistakes = commonMistakes
        self.muscleGroups = muscleGroups
        self.movementPattern = movementPattern
        self.category = category
        self.difficulty = difficulty
        self.equipment = equipment
        self.isUnilateral = isUnilateral
        self.defaultReps = defaultReps
        self.defaultDurationSeconds = defaultDurationSeconds
        self.defaultSets = defaultSets
        self.restBetweenSetsSeconds = restBetweenSetsSeconds
        self.estimatedTimePerSetSeconds = estimatedTimePerSetSeconds
        self.regressions = regressions
        self.progressions = progressions
        self.metValue = metValue
        self.tags = tags
        self.progressionChainId = progressionChainId
        self.progressionOrder = progressionOrder
        self.advancementCriteria = advancementCriteria
        self.athleteSource = athleteSource
        self.apartmentFriendly = apartmentFriendly
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        displayName = try container.decode(String.self, forKey: .displayName)
        description = try container.decode(String.self, forKey: .description)
        instructions = try container.decode([String].self, forKey: .instructions)
        commonMistakes = try container.decode([String].self, forKey: .commonMistakes)
        muscleGroups = try container.decode(MuscleGroups.self, forKey: .muscleGroups)
        movementPattern = try container.decode(MovementPattern.self, forKey: .movementPattern)
        category = try container.decode(ExerciseCategory.self, forKey: .category)
        difficulty = try container.decode(Int.self, forKey: .difficulty)
        equipment = try container.decode([Equipment].self, forKey: .equipment)
        isUnilateral = try container.decode(Bool.self, forKey: .isUnilateral)
        defaultReps = try container.decodeIfPresent(Int.self, forKey: .defaultReps)
        defaultDurationSeconds = try container.decodeIfPresent(Int.self, forKey: .defaultDurationSeconds)
        defaultSets = try container.decode(Int.self, forKey: .defaultSets)
        restBetweenSetsSeconds = try container.decode(Int.self, forKey: .restBetweenSetsSeconds)
        estimatedTimePerSetSeconds = try container.decode(Int.self, forKey: .estimatedTimePerSetSeconds)
        regressions = try container.decode([String].self, forKey: .regressions)
        progressions = try container.decode([String].self, forKey: .progressions)
        metValue = try container.decode(Double.self, forKey: .metValue)
        tags = try container.decode([String].self, forKey: .tags)
        // New fields — backward-compatible with existing JSON
        progressionChainId = try container.decodeIfPresent(String.self, forKey: .progressionChainId)
        progressionOrder = try container.decodeIfPresent(Int.self, forKey: .progressionOrder)
        advancementCriteria = try container.decodeIfPresent(String.self, forKey: .advancementCriteria)
        athleteSource = try container.decodeIfPresent([String].self, forKey: .athleteSource)
        apartmentFriendly = try container.decodeIfPresent(Bool.self, forKey: .apartmentFriendly) ?? true
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(displayName, forKey: .displayName)
        try container.encode(description, forKey: .description)
        try container.encode(instructions, forKey: .instructions)
        try container.encode(commonMistakes, forKey: .commonMistakes)
        try container.encode(muscleGroups, forKey: .muscleGroups)
        try container.encode(movementPattern, forKey: .movementPattern)
        try container.encode(category, forKey: .category)
        try container.encode(difficulty, forKey: .difficulty)
        try container.encode(equipment, forKey: .equipment)
        try container.encode(isUnilateral, forKey: .isUnilateral)
        try container.encodeIfPresent(defaultReps, forKey: .defaultReps)
        try container.encodeIfPresent(defaultDurationSeconds, forKey: .defaultDurationSeconds)
        try container.encode(defaultSets, forKey: .defaultSets)
        try container.encode(restBetweenSetsSeconds, forKey: .restBetweenSetsSeconds)
        try container.encode(estimatedTimePerSetSeconds, forKey: .estimatedTimePerSetSeconds)
        try container.encode(regressions, forKey: .regressions)
        try container.encode(progressions, forKey: .progressions)
        try container.encode(metValue, forKey: .metValue)
        try container.encode(tags, forKey: .tags)
        try container.encodeIfPresent(progressionChainId, forKey: .progressionChainId)
        try container.encodeIfPresent(progressionOrder, forKey: .progressionOrder)
        try container.encodeIfPresent(advancementCriteria, forKey: .advancementCriteria)
        try container.encodeIfPresent(athleteSource, forKey: .athleteSource)
        try container.encodeIfPresent(apartmentFriendly, forKey: .apartmentFriendly)
    }
}
