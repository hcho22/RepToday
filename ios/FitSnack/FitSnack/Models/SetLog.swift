import Foundation

struct SetLog: Codable, Identifiable {
    var id: String { "\(setNumber)" }
    var setNumber: Int
    var completed: Bool = true
    var reps: Int?
    var weight: Double?
    var durationSeconds: Int?
    var completedAt: Date
}
