import Foundation
import SwiftData

final class MockProgressionService: ProgressionServiceProtocol {
    private var chains: [ProgressionChain] = []
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        loadChains()
    }

    private func loadChains() {
        guard let url = Bundle.main.url(forResource: "ProgressionChains", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            return
        }
        chains = (try? JSONDecoder().decode([ProgressionChain].self, from: data)) ?? []
    }

    func getAllChains() -> [ProgressionChain] {
        chains
    }

    func getChain(by id: String) -> ProgressionChain? {
        chains.first { $0.id == id }
    }

    func getUserLevel(for chainId: String) async throws -> Int {
        let descriptor = FetchDescriptor<SDUserProfile>()
        guard let profile = try modelContext.fetch(descriptor).first else { return 0 }
        return profile.getProgressionLevels()[chainId] ?? 0
    }

    func updateUserLevel(for chainId: String, level: Int) async throws {
        let descriptor = FetchDescriptor<SDUserProfile>()
        guard let profile = try modelContext.fetch(descriptor).first else { return }
        var levels = profile.getProgressionLevels()
        levels[chainId] = level
        profile.setProgressionLevels(levels)
        try modelContext.save()
    }

    func checkAdvancement(chainId: String, exerciseId: String, recentSets: [SetLog]) -> Bool {
        let completedSets = recentSets.filter { $0.completed }
        guard completedSets.count >= 3 else { return false }

        return completedSets.allSatisfy { set in
            if let reps = set.reps { return reps >= 8 }
            if let duration = set.durationSeconds { return duration >= 30 }
            return false
        }
    }
}
