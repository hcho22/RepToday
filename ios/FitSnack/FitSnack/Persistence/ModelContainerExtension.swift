import SwiftData

extension ModelContainer {
    static func fitSnackContainer() throws -> ModelContainer {
        let schema = Schema([SDUserProfile.self, SDWorkout.self])
        let configuration = ModelConfiguration(schema: schema)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
