import Foundation

/// A specific integrity violation found while loading the bundled exercise library (US-B02).
///
/// Every case names the offending exercise (or chain) and the rule it broke, so a malformed
/// library fails loudly at load time with an actionable message instead of silently feeding
/// the engine bad data. `errorDescription` is the human-readable form; the enum is `Equatable`
/// so tests can assert the exact case a broken fixture produces.
enum ExerciseLibraryError: Error, Equatable, LocalizedError {
    /// `Exercises.json` could not be found in the bundle it was asked to load from.
    case resourceMissing
    /// The resource was found but could not be read or decoded into `[Exercise]`.
    case decodingFailed(String)
    /// Two or more exercises share the same `id`.
    case duplicateId(String)
    /// An exercise carries non-empty `equipment`, violating the Zero-Equipment Floor.
    case equipmentNotEmpty(exerciseId: String)
    /// A `regressionId`/`progressionId` (`link`) points at an id absent from the library.
    case unresolvedChainLink(exerciseId: String, missingId: String, link: String)
    /// A chain's `progressionOrder` values are not a contiguous `0..<count` sequence.
    case chainNotContiguous(chainId: String, orders: [Int])

    var errorDescription: String? {
        switch self {
        case .resourceMissing:
            return "Exercises.json is missing from the bundle."
        case .decodingFailed(let detail):
            return "Exercises.json could not be decoded into [Exercise]: \(detail)"
        case .duplicateId(let id):
            return "Duplicate exercise id '\(id)': every exercise id must be unique."
        case .equipmentNotEmpty(let id):
            return "Exercise '\(id)' has non-empty equipment, violating the Zero-Equipment Floor."
        case .unresolvedChainLink(let id, let missingId, let link):
            return "Exercise '\(id)' has \(link) '\(missingId)', which resolves to no exercise in the library."
        case .chainNotContiguous(let chainId, let orders):
            return "Progression chain '\(chainId)' is not contiguous: progressionOrder values \(orders) must be 0..<\(orders.count)."
        }
    }
}

/// Loads, integrity-checks, and queries the bundled exercise library (US-B02).
///
/// Despite the `Mock` name (kept to match the `ServiceContainer` naming convention), this is
/// the real, production loader for the bundled JSON catalog - there is no separate "real"
/// exercise service in the MVP. It decodes `Exercises.json` exactly once and caches both the
/// ordered list and an `id`-keyed lookup, so every query after construction is in-memory.
///
/// Construction validates the library and throws an `ExerciseLibraryError` on the first
/// violation (`init(library:)` is the validating core that the data/bundle inits funnel
/// through), making a malformed library a loud startup failure rather than a silent one.
final class MockExerciseService: ExerciseServiceProtocol {
    private let library: [Exercise]
    /// `id -> Exercise`, for O(1) id lookups and chain-link resolution.
    private let byId: [String: Exercise]

    /// Validates and caches an already-decoded library, throwing on the first integrity
    /// violation. This is the validating core; tests feed it deliberately broken libraries to
    /// exercise each rule.
    init(library: [Exercise]) throws {
        try Self.validate(library)
        self.library = library
        self.byId = Dictionary(uniqueKeysWithValues: library.map { ($0.id, $0) })
    }

    /// Decodes a JSON library payload, then validates and caches it.
    convenience init(data: Data) throws {
        let decoded: [Exercise]
        do {
            decoded = try JSONDecoder().decode([Exercise].self, from: data)
        } catch {
            throw ExerciseLibraryError.decodingFailed(String(describing: error))
        }
        try self.init(library: decoded)
    }

    /// Loads `Exercises.json` from `bundle`, then decodes, validates, and caches it.
    ///
    /// Defaults to the bundle that ships the app module (which also carries the resource), so
    /// the same call works at app runtime, in SwiftUI previews, and under the test host.
    convenience init(bundle: Bundle = Bundle(for: MockExerciseService.self)) throws {
        guard let url = bundle.url(forResource: "Exercises", withExtension: "json") else {
            throw ExerciseLibraryError.resourceMissing
        }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw ExerciseLibraryError.decodingFailed(String(describing: error))
        }
        try self.init(data: data)
    }

    // MARK: - Queries

    func exercises() async throws -> [Exercise] {
        library
    }

    func exercise(id: String) async throws -> Exercise? {
        byId[id]
    }

    func exercises(for pillar: Pillar) async throws -> [Exercise] {
        library.filter { $0.pillar == pillar }
    }

    func exercises(for movementPattern: MovementPattern) async throws -> [Exercise] {
        library.filter { $0.movementPattern == movementPattern }
    }

    func exercises(for phase: Phase) async throws -> [Exercise] {
        library.filter { $0.phase == phase }
    }

    func exercises(inDifficultyRange range: ClosedRange<Int>) async throws -> [Exercise] {
        library.filter { range.contains($0.difficulty) }
    }

    func nextInChain(after id: String) async throws -> Exercise? {
        guard let current = byId[id], let nextId = current.progressionId else { return nil }
        return byId[nextId]
    }

    // MARK: - Validation

    /// Integrity-checks a library, throwing the first violation found. Rules (in order):
    /// unique ids, the Zero-Equipment Floor, resolvable chain links, contiguous chains.
    private static func validate(_ library: [Exercise]) throws {
        // Unique ids - checked first because every later rule relies on an id-keyed lookup.
        var seen = Set<String>()
        for exercise in library where !seen.insert(exercise.id).inserted {
            throw ExerciseLibraryError.duplicateId(exercise.id)
        }
        let byId = Dictionary(uniqueKeysWithValues: library.map { ($0.id, $0) })

        // Zero-Equipment Floor: every movement is pure bodyweight.
        for exercise in library where !exercise.equipment.isEmpty {
            throw ExerciseLibraryError.equipmentNotEmpty(exerciseId: exercise.id)
        }

        // Chain links resolve: no dangling regression/progression references.
        for exercise in library {
            if let regressionId = exercise.regressionId, byId[regressionId] == nil {
                throw ExerciseLibraryError.unresolvedChainLink(
                    exerciseId: exercise.id, missingId: regressionId, link: "regressionId"
                )
            }
            if let progressionId = exercise.progressionId, byId[progressionId] == nil {
                throw ExerciseLibraryError.unresolvedChainLink(
                    exerciseId: exercise.id, missingId: progressionId, link: "progressionId"
                )
            }
        }

        // Each chain's progressionOrder is a contiguous 0..<count sequence (no gaps/dupes).
        // Sorted by chain id so the first reported offender is deterministic.
        let chains = Dictionary(grouping: library, by: \.progressionChainId)
        for (chainId, members) in chains.sorted(by: { $0.key < $1.key }) {
            let orders = members.map(\.progressionOrder).sorted()
            guard orders == Array(0..<members.count) else {
                throw ExerciseLibraryError.chainNotContiguous(chainId: chainId, orders: orders)
            }
        }
    }
}
