import Foundation

protocol ProgressionServiceProtocol {
    func getAllChains() -> [ProgressionChain]
    func getChain(by id: String) -> ProgressionChain?
    func getUserLevel(for chainId: String) async throws -> Int
    func updateUserLevel(for chainId: String, level: Int) async throws
    func checkAdvancement(chainId: String, exerciseId: String, recentSets: [SetLog]) -> Bool
}
