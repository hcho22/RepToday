import Foundation

struct ProgressionChain: Codable, Identifiable {
    let id: String
    let name: String
    let description: String
    let movementPattern: MovementPattern
    let exerciseIds: [String]
    let levels: [ChainLevel]

    struct ChainLevel: Codable {
        let exerciseId: String
        let order: Int
        let advancementCriteria: String
    }
}
