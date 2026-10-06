import UIKit
import XCTest
@testable import RepToday

/// US-TP02/US-TP03/US-TP04: the bundled Trainer art, the Trainer preference and its resolution, the one
/// Trainer write, and the pose resolver.
final class TrainerTests: XCTestCase {

    // MARK: - Fixtures

    private func user(sex: Sex, trainer: Trainer? = nil) -> User {
        var user = MockPersistence.sampleUser
        user.profile.sex = sex
        user.profile.trainer = trainer
        return user
    }

    /// The JSON of a profile persisted before `trainer` existed: today's encoding with the key removed.
    private func legacyProfileJSON(sex: Sex) throws -> Data {
        let data = try JSONEncoder().encode(user(sex: sex, trainer: .male).profile)
        var json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNotNil(json.removeValue(forKey: "trainer"))
        return try JSONSerialization.data(withJSONObject: json)
    }

    // MARK: - US-TP03: resolution

    /// All nine combinations of sex x {no choice, male, female}: the explicit choice always wins, else
    /// male -> male, female -> female, other -> unresolved.
    func testEffectiveTrainerAcrossEverySexAndChoice() {
        let expected: [Sex: [Trainer?: Trainer?]] = [
            .male: [nil: .male, .male: .male, .female: .female],
            .female: [nil: .female, .male: .male, .female: .female],
            .other: [nil: nil, .male: .male, .female: .female],
        ]
        for sex in Sex.allCases {
            for choice in [nil, Trainer.male, Trainer.female] as [Trainer?] {
                let profile = user(sex: sex, trainer: choice).profile
                XCTAssertEqual(
                    Trainer.effective(for: profile), expected[sex]?[choice] ?? nil,
                    "sex \(sex), choice \(String(describing: choice))"
                )
            }
        }
    }

    func testOtherHasNoDefaultTrainer() {
        XCTAssertNil(Trainer.defaultTrainer(for: .other))
        XCTAssertEqual(Trainer.defaultTrainer(for: .male), .male)
        XCTAssertEqual(Trainer.defaultTrainer(for: .female), .female)
    }

    /// A profile persisted before the field existed decodes with no choice and resolves from its
    /// stored sex answer - no migration.
    func testLegacyProfileWithoutTheTrainerKeyDecodesAndResolvesFromSex() throws {
        for sex in Sex.allCases {
            let profile = try JSONDecoder().decode(UserProfile.self, from: try legacyProfileJSON(sex: sex))
            XCTAssertNil(profile.trainer)
            XCTAssertEqual(profile.sex, sex)
            XCTAssertEqual(Trainer.effective(for: profile), Trainer.defaultTrainer(for: sex))
        }
    }

    func testExplicitChoiceRoundTrips() throws {
        let profile = user(sex: .other, trainer: .female).profile
        let decoded = try JSONDecoder().decode(UserProfile.self, from: JSONEncoder().encode(profile))
        XCTAssertEqual(decoded, profile)
        XCTAssertEqual(decoded.trainer, .female)
    }

    /// A build without the field (a revert) must still read a profile that carries it: the old
    /// `UserProfile` shape ignores the unknown key. Modelled with a struct of exactly the old fields.
    func testAProfileCarryingTheTrainerKeyDecodesInTheShapeBeforeIt() throws {
        struct LegacyProfile: Decodable {
            var age: Int
            var sex: Sex
            var heightCm: Double
            var weightKg: Double
            var fitnessLevel: FitnessLevel
            var primaryGoal: PrimaryGoal
            var sitsLong: Bool
            var injuries: [String]
            var typicalAvailableMinutes: Int
        }
        let data = try JSONEncoder().encode(user(sex: .male, trainer: .female).profile)
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("\"trainer\":\"female\""))
        let legacy = try JSONDecoder().decode(LegacyProfile.self, from: data)
        XCTAssertEqual(legacy.sex, .male)
    }

    // MARK: - US-TP03: the one write

    func testSaveTrainerChoiceWritesOnlyTheTrainer() async throws {
        let service = MockUserService(user: user(sex: .other))
        try await service.saveTrainerChoice(.male)
        let stored = try await service.currentUser()
        XCTAssertEqual(stored?.profile.trainer, .male)
        XCTAssertEqual(stored.map { Trainer.effective(for: $0.profile) }, .male)
    }

    /// The write re-reads the stored user, so a change another writer saved after the caller loaded
    /// the user survives the Trainer write.
    func testSaveTrainerChoiceKeepsAFieldAnotherWriterChangedAfterTheCallerLoaded() async throws {
        let service = MockUserService(user: user(sex: .male))
        let firstLoad = try XCTUnwrapAsync(await service.currentUser())

        var secondWriter = firstLoad
        secondWriter.consistency.totalWorkoutsCompleted += 5
        secondWriter.profile.injuries.append("knees")
        try await service.save(secondWriter)

        try await service.saveTrainerChoice(.female)

        let stored = try XCTUnwrapAsync(await service.currentUser())
        XCTAssertEqual(stored.profile.trainer, .female)
        XCTAssertEqual(stored.consistency.totalWorkoutsCompleted, firstLoad.consistency.totalWorkoutsCompleted + 5)
        XCTAssertEqual(stored.profile.injuries, firstLoad.profile.injuries + ["knees"])
    }

    func testSaveTrainerChoiceWithNoStoredUserThrows() async {
        do {
            try await MockUserService().saveTrainerChoice(.male)
            XCTFail("a write with no stored user must throw")
        } catch {
            XCTAssertEqual(error as? TrainerChoiceError, .noUser)
        }
    }

    /// Account deletion removes the profile and the choice with it, so a fresh onboarding resolves from
    /// its own answer.
    func testAccountDeletionErasesTheChoice() async throws {
        let service = MockUserService(user: user(sex: .male, trainer: .female))
        try await service.deleteCurrentUser()
        let afterDeletion = try await service.currentUser()
        XCTAssertNil(afterDeletion)

        try await service.save(user(sex: .male))
        let reOnboarded = try XCTUnwrapAsync(await service.currentUser())
        XCTAssertNil(reOnboarded.profile.trainer)
        XCTAssertEqual(Trainer.effective(for: reOnboarded.profile), .male)
    }

    // MARK: - US-TP04: pose resolver

    func testResolverAgainstTheBundledArt() {
        let resolver = TrainerPoseResolver.bundled
        for trainer in Trainer.allCases {
            XCTAssertEqual(
                resolver.art(exerciseId: "push_wall", trainer: trainer),
                .pair(
                    start: "Trainer/\(trainer.rawValue)/push_wall-start",
                    end: "Trainer/\(trainer.rawValue)/push_wall-end"
                )
            )
            XCTAssertEqual(
                resolver.art(exerciseId: "pull_wall_scapular_pull", trainer: trainer),
                .single(.end, "Trainer/\(trainer.rawValue)/pull_wall_scapular_pull-end")
            )
            XCTAssertEqual(resolver.art(exerciseId: "pull_ytw", trainer: trainer), .none)
            XCTAssertEqual(resolver.art(exerciseId: "not_a_movement", trainer: trainer), .none)
        }
    }

    /// Each Trainer resolves on its own, and dropping a missing pose in under the naming convention
    /// upgrades the answer with no code change.
    func testResolverIsPerTrainerAndUpgradesOnAFileDrop() {
        var available: Set<String> = [
            "Trainer/male/pull_reverse_snow_angel-start",
            "Trainer/male/pull_reverse_snow_angel-end",
            "Trainer/female/pull_reverse_snow_angel-end",
        ]
        let resolver = TrainerPoseResolver { available.contains($0) }
        XCTAssertEqual(
            resolver.art(exerciseId: "pull_reverse_snow_angel", trainer: .male),
            .pair(start: "Trainer/male/pull_reverse_snow_angel-start", end: "Trainer/male/pull_reverse_snow_angel-end")
        )
        XCTAssertEqual(
            resolver.art(exerciseId: "pull_reverse_snow_angel", trainer: .female),
            .single(.end, "Trainer/female/pull_reverse_snow_angel-end")
        )

        available.insert("Trainer/female/pull_reverse_snow_angel-start")
        XCTAssertEqual(
            resolver.art(exerciseId: "pull_reverse_snow_angel", trainer: .female),
            .pair(start: "Trainer/female/pull_reverse_snow_angel-start", end: "Trainer/female/pull_reverse_snow_angel-end")
        )
    }

    func testResolverReportsAStartOnlyPoseAndThePreviewPicksTheStart() {
        let resolver = TrainerPoseResolver { $0 == "Trainer/female/x-start" }
        XCTAssertEqual(resolver.art(exerciseId: "x", trainer: .female), .single(.start, "Trainer/female/x-start"))
        XCTAssertEqual(TrainerPoseArt.pair(start: "s", end: "e").previewAssetName, "s")
        XCTAssertEqual(TrainerPoseArt.single(.end, "e").previewAssetName, "e")
        XCTAssertNil(TrainerPoseArt.none.previewAssetName)
    }

    // MARK: - US-TP09: copy

    func testPoseAccessibilityLabels() {
        XCTAssertEqual(
            TrainerPoseCopy.accessibilityLabel(exerciseName: "Glute Bridge", art: .pair(start: "s", end: "e")),
            "Glute Bridge, trainer showing start and end positions"
        )
        XCTAssertEqual(
            TrainerPoseCopy.accessibilityLabel(exerciseName: "Wall Scapular Pull", art: .single(.end, "e")),
            "Wall Scapular Pull, trainer showing end position"
        )
        XCTAssertEqual(
            TrainerPoseCopy.accessibilityLabel(exerciseName: "X", art: .single(.start, "s")),
            "X, trainer showing start position"
        )
        XCTAssertEqual(
            TrainerPoseCopy.accessibilityLabel(exerciseName: "Prone Y-T-W Raises", art: .none),
            "Prone Y-T-W Raises demonstration"
        )
    }

    // MARK: - US-TP02: bundled art

    /// The bundle carries art for every served movement that has art, keyed by exercise id: 70 full
    /// pairs per Trainer, the two end-only gaps, and nothing for the no-art movement or the withheld
    /// `version2` crawls (decision 16).
    func testTheBundleCarriesArtForEveryServedMovementAndNoneForVersion2() throws {
        let url = try XCTUnwrap(Bundle(for: AppState.self).url(forResource: "Exercises", withExtension: "json"))
        let catalog = try JSONDecoder().decode([Exercise].self, from: Data(contentsOf: url))
        let resolver = TrainerPoseResolver.bundled
        for trainer in Trainer.allCases {
            var pairs = 0
            for exercise in catalog {
                let art = resolver.art(exerciseId: exercise.id, trainer: trainer)
                if exercise.audience == .version2 {
                    XCTAssertEqual(art, .none, "\(exercise.id) is version2 and must not be bundled")
                    continue
                }
                if case .pair = art { pairs += 1 }
            }
            XCTAssertEqual(pairs, 70, "\(trainer) full pairs")
        }
    }

    /// The two "Cossack Squat" movements (strength `squat_cossack`, mobility `mobility_cossack`) resolve
    /// to their own image sets, keyed by id, each untrimmed at 600x600 and drawing exactly its own
    /// family folder's source as committed. (Today the leg and mobility folders carry identical
    /// drawings for the two, so the point is that each id resolves on its own, never by display name.)
    func testTheTwoCossackSquatsResolveToTheirOwnUntrimmedArt() throws {
        let appBundle = Bundle(for: AppState.self)
        for trainer in Trainer.allCases {
            let strengthArt = TrainerPoseResolver.bundled.art(exerciseId: "squat_cossack", trainer: trainer)
            let mobilityArt = TrainerPoseResolver.bundled.art(exerciseId: "mobility_cossack", trainer: trainer)
            XCTAssertNotEqual(strengthArt, mobilityArt, "the two Cossack Squats must resolve to separate image sets")
            for id in ["squat_cossack", "mobility_cossack"] {
                for pose in TrainerPose.allCases {
                    let name = "\(id)-\(pose.rawValue)"
                    let bundled = try XCTUnwrap(
                        UIImage(named: "Trainer/\(trainer.rawValue)/\(name)", in: appBundle, with: nil),
                        "Trainer/\(trainer.rawValue)/\(name)"
                    )
                    XCTAssertEqual(bundled.size.width * bundled.scale, 600, "\(name) must keep its 600 px canvas")
                    XCTAssertEqual(bundled.size.height * bundled.scale, 600, "\(name) must keep its 600 px canvas")
                    XCTAssertEqual(
                        try pixels(of: bundled), try pixels(of: committedPNG(trainer.rawValue, name)),
                        "\(trainer)/\(name) must draw its own committed source"
                    )
                }
            }
        }
    }

    // MARK: - Helpers

    private func committedPNG(_ trainer: String, _ name: String) throws -> UIImage {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("RepToday/Resources/Assets.xcassets/Trainer/\(trainer)/\(name).imageset/\(name).png")
        return try XCTUnwrap(UIImage(contentsOfFile: url.path), "no committed PNG at \(url.path)")
    }

    /// The image redrawn into a fixed 600x600 RGBA buffer, so a catalog-compiled image and a raw PNG
    /// compare by what they draw rather than by how they are stored.
    private func pixels(of image: UIImage) throws -> Data {
        let side = 600
        let cgImage = try XCTUnwrap(image.cgImage)
        var buffer = Data(count: side * side * 4)
        try buffer.withUnsafeMutableBytes { raw in
            let context = try XCTUnwrap(CGContext(
                data: raw.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))
        }
        return buffer
    }
}

/// `XCTUnwrap` for an expression that has already been awaited.
private func XCTUnwrapAsync<T>(_ value: T?, file: StaticString = #filePath, line: UInt = #line) throws -> T {
    try XCTUnwrap(value, file: file, line: line)
}
