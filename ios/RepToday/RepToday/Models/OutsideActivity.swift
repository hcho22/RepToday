import Foundation

// MARK: - OutsideActivityType

/// The kind of workout done outside Rep Today, and the Training Day group it worked (PRD decision 21):
/// run, bike and hike work Legs; swim, row and climb work Pull; anything else works no group. The raw
/// value is the stored form.
enum OutsideActivityType: String, Codable, CaseIterable, Identifiable, Hashable {
    case run
    case bike
    case hike
    case swim
    case row
    case climb
    case other

    var id: String { rawValue }

    /// The group the activity worked, which then gets at least one day off, or `nil`.
    var group: TrainingDay? {
        switch self {
        case .run, .bike, .hike: return .legs
        case .swim, .row, .climb: return .pull
        case .other: return nil
        }
    }

    /// The name the entry sheet and Today show.
    var label: String {
        switch self {
        case .run: return "Run"
        case .bike: return "Bike ride"
        case .hike: return "Hike"
        case .swim: return "Swim"
        case .row: return "Row"
        case .climb: return "Climb"
        case .other: return "Other workout"
        }
    }

    var systemImage: String {
        switch self {
        case .run: return "figure.run"
        case .bike: return "figure.outdoor.cycle"
        case .hike: return "figure.hiking"
        case .swim: return "figure.pool.swim"
        case .row: return "figure.rower"
        case .climb: return "figure.climbing"
        case .other: return "figure.mixed.cardio"
        }
    }

    /// Whether a distance means anything for this kind of workout.
    var hasDistance: Bool {
        switch self {
        case .run, .bike, .hike, .swim, .row: return true
        case .climb, .other: return false
        }
    }
}

// MARK: - OutsideActivity

/// A workout done outside Rep Today (`CONTEXT.md` "Outside Activity"), logged by hand from Today or
/// added from an Apple Health suggestion (decision 22). It counts as showing up for the Consistency Score
/// and gives the group it worked at least one day off (`TrainingRotation`), but never completes a group.
///
/// A played Custom Workout (M4, decision 27) is recorded as one too, which is what "counts like an
/// Outside Activity" means: it carries `customWorkoutId`, and its group is the one the workout's own
/// movements worked (`CustomWorkout.trainedGroup`) rather than its type's. Its `type` stays `.other`, so
/// a build that predates Custom Workouts reads it as an ordinary outside workout.
struct OutsideActivity: Codable, Equatable, Identifiable, Hashable {
    var id: UUID
    var type: OutsideActivityType
    /// When it happened. The Rotation and the Consistency Score read only its calendar day.
    var date: Date
    var durationMinutes: Int
    /// Optional distance in meters, for the kinds of workout that have one.
    var distanceMeters: Double?
    /// The Apple Health workout it was added from, so that workout is never suggested again. `nil` for an
    /// activity logged by hand.
    var healthWorkoutId: UUID?
    /// The Custom Workout this records a play of (M4), or `nil` for an ordinary Outside Activity.
    var customWorkoutId: UUID? = nil
    /// That Custom Workout's title, so Today can name it without reading the workout.
    var customWorkoutTitle: String? = nil
    /// The group that Custom Workout worked (FR-8), fixed when it was played.
    var customWorkoutGroup: TrainingDay? = nil

    init(
        id: UUID = UUID(),
        type: OutsideActivityType,
        date: Date,
        durationMinutes: Int = OutsideActivity.defaultDurationMinutes,
        distanceMeters: Double? = nil,
        healthWorkoutId: UUID? = nil,
        customWorkoutId: UUID? = nil,
        customWorkoutTitle: String? = nil,
        customWorkoutGroup: TrainingDay? = nil
    ) {
        self.id = id
        self.type = type
        self.date = date
        self.durationMinutes = durationMinutes
        self.distanceMeters = distanceMeters
        self.healthWorkoutId = healthWorkoutId
        self.customWorkoutId = customWorkoutId
        self.customWorkoutTitle = customWorkoutTitle
        self.customWorkoutGroup = customWorkoutGroup
    }

    /// Whether this records a played Custom Workout.
    var isCustomWorkout: Bool { customWorkoutId != nil }

    /// The Training Day group it worked, or `nil`: a Custom Workout's own group, else its type's.
    var group: TrainingDay? { isCustomWorkout ? customWorkoutGroup : type.group }

    /// The name Today shows for it.
    var label: String {
        guard isCustomWorkout else { return type.label }
        return customWorkoutTitle.map { "Custom Workout: \($0)" } ?? "Custom Workout"
    }

    /// The duration the entry sheet opens at.
    static let defaultDurationMinutes = 30

    /// The longest duration the entry sheet accepts: a whole day out on a hike is the outer edge.
    static let maxDurationMinutes = 600
}
