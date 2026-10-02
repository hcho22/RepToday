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
    /// A `pillar == .mobility` movement is missing the `complements` field the prefer-then-fill
    /// bookend selection reads (US-M02). Every mobility stretch must carry it (an empty `[]` is
    /// valid - "complements no pattern"); a *missing* key is a tagging omission, not "no matches".
    case mobilityMissingComplements(exerciseId: String)
    /// An exercise carries no `audience`, so the access rule (`MovementAccess`, ADR-0007) would have to
    /// guess who gets it. Every catalog movement must say.
    case missingAudience(exerciseId: String)
    /// A chain is not a clean doubly-linked ladder: `exerciseId`'s `progressionId`/`regressionId` does
    /// not point at the adjacent `progressionOrder` in the same chain, or the neighbour does not link back.
    case chainNotDoublyLinked(exerciseId: String, linkedId: String)
    /// A movement offered to users links into one withdrawn until version 2, so withdrawing it would
    /// leave a hole in a live ladder. A withdrawn movement must sit in a chain wholly withdrawn.
    case withdrawnMovementInLiveChain(exerciseId: String, withdrawnId: String)

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
        case .mobilityMissingComplements(let id):
            return "Mobility movement '\(id)' is missing the 'complements' field (US-M02): every stretch must be tagged (use [] for none)."
        case .missingAudience(let id):
            return "Exercise '\(id)' is missing the 'audience' field (ADR-0007): every movement must say who is offered it."
        case .chainNotDoublyLinked(let id, let linkedId):
            return "Exercise '\(id)' and '\(linkedId)' are not adjacent, mutually linked rungs of one progression chain."
        case .withdrawnMovementInLiveChain(let id, let withdrawnId):
            return "Exercise '\(id)' is offered to users but links to '\(withdrawnId)', which is withdrawn until version 2."
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
///
/// The file also carries the movements **withdrawn until version 2** (`audience == .version2`,
/// ADR-0007). They are validated with everything else so they stay recoverable, but the service never
/// serves them: `exercises()` and every query below read the *offered* library, and the withdrawn ones
/// are reachable only through `withdrawnExercises()`. That is what keeps them out of every session,
/// swap, progress surface and Coach context by construction - nothing downstream has to remember to
/// filter them.
final class MockExerciseService: ExerciseServiceProtocol {
    /// The movements offered to users (everything except the version-2 withdrawals).
    private let library: [Exercise]
    /// The version-2 withdrawals, kept whole for recovery.
    private let withdrawn: [Exercise]
    /// `id -> Exercise` over the offered library, for O(1) id lookups and chain-link resolution.
    private let byId: [String: Exercise]

    /// Validates and caches an already-decoded library, throwing on the first integrity
    /// violation. This is the validating core; tests feed it deliberately broken libraries to
    /// exercise each rule.
    init(library: [Exercise]) throws {
        try Self.validate(library)
        self.library = library.filter { !MovementAccess.isWithdrawn($0) }
        self.withdrawn = library.filter(MovementAccess.isWithdrawn)
        self.byId = Dictionary(uniqueKeysWithValues: self.library.map { ($0.id, $0) })
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

    func withdrawnExercises() async throws -> [Exercise] {
        withdrawn
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

        // Every mobility stretch carries a `complements` tag (US-M02) - `[]` is valid, a missing
        // key is not - so the prefer-then-fill bookend selection has an honest, uniform schema and
        // a newly added stretch cannot silently ship untagged.
        for exercise in library where exercise.pillar == .mobility && exercise.complements == nil {
            throw ExerciseLibraryError.mobilityMissingComplements(exerciseId: exercise.id)
        }

        // Every movement says who is offered it (ADR-0007).
        for exercise in library where exercise.audience == nil {
            throw ExerciseLibraryError.missingAudience(exerciseId: exercise.id)
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

        // Every chain is a clean doubly-linked ladder: a rung's progression is the next order in the same
        // chain and links back as that rung's regression. Reordering a chain (ADR-0007 moved Sumo Squat
        // behind Bodyweight Squat) must rewire both directions or this fails loudly at load.
        for exercise in library.sorted(by: { $0.id < $1.id }) {
            if let nextId = exercise.progressionId, let next = byId[nextId] {
                guard next.progressionChainId == exercise.progressionChainId,
                      next.progressionOrder == exercise.progressionOrder + 1,
                      next.regressionId == exercise.id else {
                    throw ExerciseLibraryError.chainNotDoublyLinked(exerciseId: exercise.id, linkedId: nextId)
                }
            }
            if let previousId = exercise.regressionId, let previous = byId[previousId] {
                guard previous.progressionChainId == exercise.progressionChainId,
                      previous.progressionOrder == exercise.progressionOrder - 1,
                      previous.progressionId == exercise.id else {
                    throw ExerciseLibraryError.chainNotDoublyLinked(exerciseId: exercise.id, linkedId: previousId)
                }
            }
        }

        // A withdrawn movement sits in a chain withdrawn whole: no offered movement may link into one.
        for exercise in library.sorted(by: { $0.id < $1.id }) where !MovementAccess.isWithdrawn(exercise) {
            for linkedId in [exercise.regressionId, exercise.progressionId].compactMap({ $0 }) {
                if let linked = byId[linkedId], MovementAccess.isWithdrawn(linked) {
                    throw ExerciseLibraryError.withdrawnMovementInLiveChain(exerciseId: exercise.id, withdrawnId: linkedId)
                }
            }
        }
    }
}
