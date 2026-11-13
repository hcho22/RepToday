import XCTest
@testable import RepToday

/// US-HO02 / US-HO03: Focus Areas (decision 20) - the mapping, the profile field that replaced the goal
/// list, and the emphasis they give a Training Day without ever touching the Rotation.
final class FocusAreaTests: XCTestCase {

    private var library: [Exercise] = []

    override func setUp() async throws {
        library = try await MockExerciseService().exercises()
    }

    private func exercise(_ id: String) throws -> Exercise {
        try XCTUnwrap(library.first { $0.id == id }, "\(id) is not in the catalog")
    }

    private func plan(
        _ day: TrainingDay,
        minutes: Int,
        level: FitnessLevel = .intermediate,
        focusAreas: [FocusArea] = [],
        logs: [WorkoutLog] = []
    ) -> SessionPlan {
        var plan = SessionAssembly.planSession(
            requestedMinutes: minutes,
            user: TrainingDayFixtures.user(level: level, focusAreas: focusAreas),
            library: library,
            recentLogs: logs,
            trainingDay: day,
            asOf: TrainingDayFixtures.asOf,
            calendar: TrainingDayFixtures.calendar
        )
        SessionAssembly.fit(&plan, targetSeconds: minutes * 60)
        return plan
    }

    // MARK: Mapping (decision 20)

    func testTheMappingFollowsDecision20() throws {
        let expected: [(String, Set<FocusArea>)] = [
            ("push_standard", [.chest]),
            ("push_diamond", [.chest, .arms]),
            ("push_pike", [.shoulders]),
            ("push_floor_dips", [.shoulders, .arms]),
            ("pull_wall_scapular_pull", [.back]),
            ("pull_floor_row", [.back, .arms]),
            ("pull_floor_row_single_arm", [.back, .arms]),
            ("pull_superman", [.back]),
            ("core_forearm_plank", [.abs]),
            ("core_dead_bug", [.abs]),
            ("squat_bodyweight", [.legs]),
            ("lunge_reverse", [.legs]),
            ("hinge_glute_bridge", [.glutes]),
            ("hinge_good_morning", [.glutes]),
        ]
        for (id, areas) in expected {
            let covered = Set(FocusArea.allCases.filter { $0.covers(try! exercise(id)) })
            XCTAssertEqual(covered, areas, id)
        }
    }

    func testEveryArmsMovementIsInTheCatalog() throws {
        for id in FocusArea.armsMovementIds {
            _ = try exercise(id)
        }
    }

    func testNoFocusAreaCoversAStretch() {
        for stretch in library where stretch.pillar == .mobility {
            XCTAssertFalse(FocusArea.allCases.covers(stretch), stretch.id)
        }
    }

    // MARK: The profile field

    func testAProfileStoredWithTheOldGoalDecodesWithNoFocusAreas() throws {
        let legacy = """
        {"age":40,"sex":"male","heightCm":180,"weightKg":80,"fitnessLevel":"beginner",
         "primaryGoal":"build_strength","sitsLong":true,"injuries":["knees"],"typicalAvailableMinutes":20}
        """
        let profile = try JSONDecoder().decode(UserProfile.self, from: Data(legacy.utf8))
        XCTAssertEqual(profile.focusAreas, [])
        XCTAssertEqual(profile.fitnessLevel, .beginner)
        XCTAssertEqual(profile.injuries, ["knees"])
        XCTAssertNil(profile.trainer)
    }

    func testFocusAreasRoundTripInCanonicalOrderAndKeepTheLegacyGoalKey() throws {
        var profile = TrainingDayFixtures.user().profile
        profile.focusAreas = [.glutes, .chest, .abs]
        let data = try PersistenceCoder.encoder.encode(profile)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        // A build from before Focus Areas requires the old key, so it is still written.
        XCTAssertEqual(object["primaryGoal"] as? String, UserProfile.legacyPrimaryGoalValue)
        let decoded = try PersistenceCoder.decoder.decode(UserProfile.self, from: data)
        XCTAssertEqual(decoded.focusAreas, [.chest, .abs, .glutes])
    }

    func testAFocusAreaALaterBuildAddsIsDroppedNotFatal() throws {
        let future = """
        {"age":40,"sex":"male","heightCm":180,"weightKg":80,"fitnessLevel":"beginner",
         "focusAreas":["chest","calves"],"sitsLong":false,"injuries":[],"typicalAvailableMinutes":20}
        """
        let profile = try JSONDecoder().decode(UserProfile.self, from: Data(future.utf8))
        XCTAssertEqual(profile.focusAreas, [.chest])
    }

    // MARK: Training Days (US-HO03)

    /// A Focus Area that covers nothing on the day leaves the session exactly as it is with none - the
    /// same stations, numbers and rests.
    func testAFocusAreaOffItsDayLeavesTheSessionUnchanged() {
        for minutes in [5, 15, 30, 45, 60] {
            let none = plan(.push, minutes: minutes)
            let offDay = plan(.push, minutes: minutes, focusAreas: [.legs, .glutes, .back])
            XCTAssertEqual(none.stations.map(\.exercise.id), offDay.stations.map(\.exercise.id), "\(minutes) min")
            XCTAssertEqual(none.stations.map(\.value), offDay.stations.map(\.value), "\(minutes) min")
            XCTAssertEqual(none.roundRestSeconds, offDay.roundRestSeconds, "\(minutes) min")
            XCTAssertEqual(none.transitionSeconds, offDay.transitionSeconds, "\(minutes) min")
        }
    }

    func testAFocusedLadderIsOrderedFirstAndTakesTheSlotOnAShortSession() {
        let mains = { (plan: SessionPlan) in plan.stations.filter { $0.role == .main }.map(\.exercise.progressionChainId) }
        XCTAssertEqual(mains(plan(.push, minutes: 5)), ["push_horizontal"])
        XCTAssertEqual(mains(plan(.push, minutes: 5, focusAreas: [.shoulders])), ["push_vertical"])
        XCTAssertEqual(mains(plan(.push, minutes: 15, focusAreas: [.shoulders])), ["push_vertical", "push_horizontal"])

        XCTAssertEqual(mains(plan(.legs, minutes: 5)), ["squat"])
        XCTAssertEqual(mains(plan(.legs, minutes: 5, focusAreas: [.glutes])).first.map { ["hinge_bridge", "hinge_hip"].contains($0) }, true)
        // Legs puts both squat-side ladders ahead of the hinge side.
        XCTAssertEqual(Set(mains(plan(.legs, minutes: 15, focusAreas: [.legs]))), ["squat", "lunge"])
    }

    /// A focused station is padded first (decision 20): an unfocused station carries Padding only when no
    /// focused station could take another step and land the session closer to its length - a focused
    /// step that would overshoot the remaining gap gives way to a smaller unfocused one, since the fit
    /// always takes the closest landing.
    func testFocusedStationsArePaddedFirst() {
        for level in FitnessLevel.allCases {
            for (day, focus) in [(TrainingDay.push, FocusArea.chest), (.pull, .back), (.legs, .glutes), (.push, .abs)] {
                for minutes in [30, 45, 60] {
                    let fitted = plan(day, minutes: minutes, level: level, focusAreas: [focus])
                    let target = minutes * 60
                    let unfocusedPadded = fitted.stations.contains { !$0.isFocused && $0.padSteps > 0 }
                    let focusedStepWouldLandCloser = fitted.stations.indices.contains { index in
                        let station = fitted.stations[index]
                        guard station.isFocused, station.value + RepGrammar.step <= station.ceiling else { return false }
                        var trial = fitted
                        trial.stations[index].value += RepGrammar.step
                        return abs(trial.totalSeconds - target) < abs(fitted.totalSeconds - target)
                    }
                    XCTAssertFalse(
                        unfocusedPadded && focusedStepWouldLandCloser,
                        "\(level) \(day) \(focus) \(minutes) min padded an unfocused station before a focused one"
                    )
                    XCTAssertTrue(fitted.stations.contains { $0.isFocused }, "\(level) \(day) \(focus) \(minutes) min")
                }
            }
        }
    }

    func testAFocusedStationIsPaddedAtLeastAsFarAsWithoutTheFocus() {
        let without = plan(.push, minutes: 45)
        let with = plan(.push, minutes: 45, focusAreas: [.chest])
        let chestWithout = without.stations.first { $0.role == .main && $0.exercise.progressionChainId == "push_horizontal" }
        let chestWith = with.stations.first { $0.role == .main && $0.exercise.progressionChainId == "push_horizontal" }
        XCTAssertGreaterThanOrEqual(chestWith?.value ?? 0, chestWithout?.value ?? .max)
    }

    func testThePracticeSlotGoesToTheFocusedLadderFirst() {
        // Push, 30 min: two mains and one Practice Movement, for the first ladder by default.
        let practiceLadder = { (plan: SessionPlan) in
            plan.stations.filter { $0.role == .practice }.map(\.exercise.progressionChainId)
        }
        XCTAssertEqual(practiceLadder(plan(.push, minutes: 30)), ["push_horizontal"])
        XCTAssertEqual(practiceLadder(plan(.push, minutes: 30, focusAreas: [.shoulders])), ["push_vertical"])

        // Arms covers rows: with the row ladder worked most recently it would lose the Practice slot to
        // the postural ladder, but the rung above its current one is a row, so Arms hands it the slot.
        let rowsYesterday = TrainingDayFixtures.log(
            [TrainingDayFixtures.station("pull_wall_scapular_pull", pattern: .pull, earned: 15)],
            completedAt: TrainingDayFixtures.date(daysAgo: 1)
        )
        let beginnerPull = { (focus: [FocusArea]) in
            practiceLadder(self.plan(.pull, minutes: 30, level: .beginner, focusAreas: focus, logs: [rowsYesterday]))
        }
        XCTAssertEqual(beginnerPull([]), ["pull_postural"])
        XCTAssertEqual(beginnerPull([.arms]), ["pull_horizontal"])
    }

    /// Abs adds one Core Sprinkle wherever core appears (ADR-0018): 2 at 15-30 minutes and 3 at 45-60, one
    /// per core ladder. A Discipline-Phase beginner or intermediate is offered only two core ladders (the
    /// hollow ladder is advanced-only, ADR-0007), so their 45-60 minute session holds both and runs one
    /// movement fewer rather than repeating a ladder.
    func testAbsAddsACoreSprinkleWhereverCoreAppears() {
        for (level, ladders) in [(FitnessLevel.intermediate, 2), (.advanced, 3)] {
            for day in TrainingDay.rotation {
                for minutes in [5, 10, 15, 20, 30, 45, 60] {
                    let core = plan(day, minutes: minutes, level: level, focusAreas: [.abs]).stations.filter { $0.role == .core }
                    let asked = minutes <= 10 ? 0 : (minutes <= 30 ? 2 : 3)
                    XCTAssertEqual(core.count, min(asked, ladders), "\(level) \(day) \(minutes) min")
                    XCTAssertEqual(Set(core.map(\.exercise.progressionChainId)).count, core.count, "every Core Sprinkle on its own ladder")
                }
            }
        }
        XCTAssertEqual(SessionAssembly.coreSprinkleCount(forRequestedMinutes: 30, focusAreas: [.abs, .chest]), 2)
        XCTAssertEqual(SessionAssembly.coreSprinkleCount(forRequestedMinutes: 30, focusAreas: [.chest]), 1)
        XCTAssertEqual(SessionAssembly.coreSprinkleCount(forRequestedMinutes: 45, focusAreas: [.abs]), 3)
        XCTAssertEqual(SessionAssembly.coreSprinkleCount(forRequestedMinutes: 60, focusAreas: [.chest]), 2)
    }

    /// Why a Discipline-Phase beginner or intermediate gets two Core Sprinkles, not three, at 45-60 minutes
    /// with Abs: every rung of the hollow core ladder is advanced-only (Hollow Hold, Hollow Rock,
    /// Tuck L-Sit) or Strength-Phase-gated (One-Leg L-Sit, L-Sit), so movement access offers them nothing on
    /// it (ADR-0007), and the session holds the plank and stability ladders' rungs rather than repeating a
    /// ladder. An advanced user, or anyone once the Strength Phase is earned, gets all three.
    func testTheHollowLadderIsWhyABeginnerOrIntermediateGetsTwoCoreSprinkles() throws {
        let hollow = library.filter { $0.progressionChainId == "core_hollow" }
        XCTAssertFalse(hollow.isEmpty)
        for level in [FitnessLevel.beginner, .intermediate] {
            XCTAssertTrue(hollow.allSatisfy { !MovementAccess.isAvailable($0, level: level, phase: .discipline) }, "\(level)")
            for day in TrainingDay.rotation {
                for minutes in [45, 60] {
                    let core = plan(day, minutes: minutes, level: level, focusAreas: [.abs]).stations.filter { $0.role == .core }
                    XCTAssertEqual(Set(core.map(\.exercise.progressionChainId)), ["core_plank", "core_stability"], "\(level) \(day) \(minutes) min")
                }
            }
        }
        XCTAssertTrue(hollow.contains { MovementAccess.isAvailable($0, level: .advanced, phase: .discipline) })
        XCTAssertTrue(hollow.contains { MovementAccess.isAvailable($0, level: .beginner, phase: .strength) })
        let advanced = plan(.push, minutes: 45, level: .advanced, focusAreas: [.abs]).stations.filter { $0.role == .core }
        XCTAssertEqual(Set(advanced.map(\.exercise.progressionChainId)), Set(SessionAssembly.coreLadders))
    }

    func testFocusAreasNeverChangeTheRotation() {
        let histories: [[WorkoutLog]] = [
            [],
            [TrainingDayFixtures.trainingLog(.push, completedAt: TrainingDayFixtures.date(daysAgo: 1))],
            [
                TrainingDayFixtures.trainingLog(.push, completedAt: TrainingDayFixtures.date(daysAgo: 3)),
                TrainingDayFixtures.trainingLog(.pull, completedAt: TrainingDayFixtures.date(daysAgo: 2)),
                TrainingDayFixtures.trainingLog(.legs, completedAt: TrainingDayFixtures.date(daysAgo: 1)),
            ],
        ]
        for logs in histories {
            let plans = [[], FocusArea.allCases, [.abs], [.legs, .glutes]].map { areas in
                SessionAssembly.trainingPlan(
                    user: TrainingDayFixtures.user(focusAreas: areas),
                    library: library,
                    recentLogs: logs,
                    asOf: TrainingDayFixtures.asOf,
                    calendar: TrainingDayFixtures.calendar
                )
            }
            XCTAssertEqual(Set(plans.map { "\($0)" }).count, 1, "\(plans)")
        }
    }

    func testAnAssembledSessionWithFocusAreasKeepsTheTrainingDay() {
        let workout = SessionAssembly.assemble(
            requestedMinutes: 45,
            user: TrainingDayFixtures.user(focusAreas: FocusArea.allCases),
            library: library,
            recentLogs: [],
            trainingDay: .pull,
            asOf: TrainingDayFixtures.asOf,
            calendar: TrainingDayFixtures.calendar
        )
        XCTAssertEqual(workout.trainingDay, .pull)
        let worked = workout.blocks.flatMap(\.exercises).filter { $0.role == .main || $0.role == .practice }
        XCTAssertTrue(worked.allSatisfy { $0.exercise.movementPattern == .pull })
    }
}
