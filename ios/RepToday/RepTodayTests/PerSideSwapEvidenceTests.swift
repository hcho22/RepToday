import XCTest
import SwiftUI
@testable import RepToday

/// End-to-end evidence for the prescription as the user meets it: the player *saying* "per side" on a
/// movement the engine charges both sides for, the in-session swap keeping the slot's own set count and
/// the session inside its budget, and the spoken form of that same target agreeing with its own counts
/// on every slot of a real session.
///
/// Everything here runs the real pipeline over the real bundled `Exercises.json` - `SessionAssembly`
/// generates the session, `ExerciseSwap` (through `OnDeviceWorkoutEngine`, the same seam the app wires) does
/// the substitution, and `ActiveSessionViewModel` / `ActiveSessionView` / `ReadyView` are the production
/// surfaces - so the strings and the arithmetic asserted here are the ones a user actually gets. The
/// printed transcripts and rendered PNGs are the reviewable artifact; the assertions are what make them
/// a gate rather than a demo.
@MainActor
final class PerSideSwapEvidenceTests: XCTestCase {

    /// Where the rendered-UI evidence is written - resolved by `EvidenceOutput`, which is the single
    /// place that decides between the default per-run temporary directory, the committed
    /// `artifacts/reports/<story>/` under `REPTODAY_WRITE_EVIDENCE=1`, and a `REPTODAY_EVIDENCE_DIR`
    /// root. Every render and every assertion runs identically in all three modes; only where the
    /// bytes land changes.
    private typealias Evidence = EvidenceOutput.Story

    private let requestedMinutes = 30

    /// The window a hosted surface lives in while it is measured or captured.
    private var renderWindow: UIWindow?

    // MARK: - Fixtures

    private let calendar = TrainingDayFixtures.calendar
    private var asOf: Date { TrainingDayFixtures.asOf }

    private func date(daysAgo: Int) -> Date {
        TrainingDayFixtures.date(daysAgo: daysAgo)
    }

    /// A steady-state, past-cold-start user with a learned 30-minute default. Advanced: the per-side
    /// moves this fixture pins (`core_side_plank`, `hinge_single_leg_bridge`) sit beyond a beginner's
    /// staples (ADR-0007), and an advanced user keeps the whole Discipline-Phase catalog.
    private func steadyUser() -> User {
        User(
            id: "evidence-user",
            displayName: "Riley",
            createdAt: date(daysAgo: 120),
            profile: UserProfile(
                age: 34, sex: .female, heightCm: 168.5, weightKg: 62.0,
                fitnessLevel: .advanced,
                sitsLong: true, injuries: [], typicalAvailableMinutes: requestedMinutes
            ),
            phase: .discipline,
            subscription: .free,
            consistency: Consistency(
                weeklyGoal: 3, score: 78.0, workoutsThisWeek: 2,
                longestChain: 6, totalWorkoutsCompleted: 38, totalMinutesExercised: 540
            ),
            duration: User.Duration(
                defaultMinutes: requestedMinutes,
                onboardingSeedMinutes: requestedMinutes,
                completedDurationEWMA: Double(requestedMinutes)
            ),
            coldStart: User.ColdStart(sessionsLogged: 12, active: false)
        )
    }

    /// Two full Push -> Pull -> Legs Cycles (each followed by its Rest Day) and a third Cycle's Push and
    /// Pull Days, so the Rotation serves a **Legs Day** today - and one shaped so that day carries every
    /// kind of per-side slot:
    /// - The lunge and bridge ladders were last worked on the first Legs Day (13 days ago) and the squat
    ///   and hip ladders on the second (7 days ago), so today's two main slots lead with `lunge_reverse`
    ///   and `hinge_single_leg_bridge` - both per-side **rep** movements.
    /// - Of the three core ladders, the plank ladder was worked longest before the current Cycle began, so
    ///   the Core Sprinkle is its current rung, `core_side_plank` - a per-side **training hold**.
    private func history() -> [WorkoutLog] {
        typealias F = TrainingDayFixtures
        func core(_ id: String) -> LoggedExercise {
            id == "core_dead_bug"
                ? F.station(id, pattern: .core, role: .core, value: 10, earned: 10)
                : F.station(id, pattern: .core, role: .core, value: 30, earned: 30, isHold: true)
        }
        func day(_ daysAgo: Int, _ mains: [(String, MovementPattern, Int)], core id: String) -> WorkoutLog {
            F.log(
                mains.map { F.station($0.0, pattern: $0.1, value: $0.2, earned: $0.2) } + [core(id)],
                completedAt: date(daysAgo: daysAgo),
                requestedMinutes: requestedMinutes
            )
        }
        return [
            day(17, [("push_standard", .push, 20), ("push_floor_dips", .push, 20)], core: "core_dead_bug"),
            day(15, [("pull_floor_row", .pull, 20), ("pull_reverse_snow_angel", .pull, 20)], core: "core_hollow_hold"),
            day(13, [("lunge_reverse", .squat, 10), ("hinge_single_leg_bridge", .hinge, 10)], core: "core_side_plank"),
            day(11, [("push_standard", .push, 20), ("push_floor_dips", .push, 20)], core: "core_dead_bug"),
            day(9, [("pull_floor_row", .pull, 20), ("pull_reverse_snow_angel", .pull, 20)], core: "core_hollow_hold"),
            day(7, [("squat_bodyweight", .squat, 20), ("hinge_good_morning", .hinge, 20)], core: "core_dead_bug"),
            day(5, [("push_standard", .push, 20), ("push_floor_dips", .push, 20)], core: "core_hollow_hold"),
            day(3, [("pull_floor_row", .pull, 20), ("pull_reverse_snow_angel", .pull, 20)], core: "core_dead_bug"),
        ]
    }

    private func library() throws -> [Exercise] {
        let bundle = Bundle(for: AppState.self)
        let url = try XCTUnwrap(bundle.url(forResource: "Exercises", withExtension: "json"))
        return try JSONDecoder().decode([Exercise].self, from: Data(contentsOf: url))
    }

    /// The real Steps 1-7 pipeline at a fixed clock, so the transcripts below are reproducible. The
    /// Rotation picks the day from `history()`.
    private func generate() throws -> Workout {
        let workout = SessionAssembly.assemble(
            requestedMinutes: requestedMinutes,
            user: steadyUser(),
            library: try library(),
            recentLogs: history(),
            sessionPolicy: .default,
            asOf: asOf,
            calendar: calendar
        )
        XCTAssertEqual(workout.trainingDay, .legs, "the history ends on a Pull Day, so today is a Legs Day")
        return workout
    }

    private func player(_ workout: Workout, engine: any WorkoutEngineProtocol) -> ActiveSessionViewModel {
        ActiveSessionViewModel(
            workout: workout, swapEngine: engine, user: steadyUser(), recentLogs: history(),
            sessionPolicy: .default, now: { self.asOf }, cuePlayer: SilentCuePlayer()
        )
    }

    private struct SilentCuePlayer: SessionCuePlayer {
        func play(_ cue: SessionCue, suppressAudio: Bool) {}
    }

    /// The planned wall-clock of a (possibly swapped) lineup, measured with the engine's own even-round
    /// model. A swap replaces a slot in place, so the flat step list re-partitions cleanly back into the
    /// original block structure - which the measurement must preserve, because the even-round
    /// `plannedSeconds` prices a training block as a circuit (over its rounds/round-rest) and a bookend
    /// linearly; flattening a mixed lineup into one block would misread the warm-up's single set as the
    /// whole session's round count.
    private func plannedSeconds(of prescriptions: [PrescribedExercise], like workout: Workout) -> Int {
        var iterator = prescriptions.makeIterator()
        let blocks: [WorkoutBlock] = workout.blocks.map { block in
            let slots = block.exercises.compactMap { _ in iterator.next() }
            return WorkoutBlock(id: block.id, title: block.title, category: block.category, exercises: slots)
        }
        return SessionAssembly.plannedSeconds(
            of: Workout(
                id: workout.id, createdAt: workout.createdAt, shape: workout.shape,
                focusPillar: workout.focusPillar, requestedMinutes: workout.requestedMinutes,
                wasReturn: workout.wasReturn, blocks: blocks
            )
        )
    }

    private func pad(_ text: String, _ width: Int) -> String {
        text.count >= width ? text : text + String(repeating: " ", count: width - text.count)
    }

    // MARK: - The generated session says "per side" wherever it charges both sides

    /// Walks a real 30-minute session slot by slot and prints exactly what the player shows and what
    /// VoiceOver reads for each, then gates both directions: a movement the timing model charges for
    /// both sides is labelled "per side", and one it does not is never labelled that way. The printed
    /// transcript is the artifact; the paired assertions keep it honest.
    func testGeneratedSessionLabelsEveryPerSideSlot() throws {
        let workout = try generate()
        let slots = workout.blocks.flatMap { block in block.exercises.map { (block.title, $0) } }

        print("=== Rep Today - real 30 minute session, per-side labelling ===")
        print(pad("BLOCK", 19) + pad("MOVEMENT", 30) + pad("PLAYER SHOWS", 22)
              + pad("VOICEOVER READS", 42) + "WORK/SET")
        var perSideCount = 0
        for (blockTitle, prescription) in slots {
            let visual = ActiveSessionView.targetText(prescription)
            let spoken = ActiveSessionView.targetAccessibilityText(prescription)
            let work = SessionAssembly.workSecondsPerSet(of: prescription)
            let isPerSide = prescription.exercise.sidesPerSet > 1
            if isPerSide { perSideCount += 1 }
            print(pad(blockTitle, 19) + pad(prescription.exercise.id, 30) + pad(visual, 22)
                  + pad("\"\(spoken)\"", 42) + "\(work)s"
                  + (isPerSide ? "   <- charged for both sides" : ""))

            if isPerSide {
                XCTAssertTrue(
                    visual.hasSuffix(" per side"),
                    "\(prescription.exercise.id) is charged for both sides but the player shows '\(visual)'"
                )
                XCTAssertTrue(
                    spoken.hasSuffix(" per side"),
                    "\(prescription.exercise.id) is charged for both sides but VoiceOver reads '\(spoken)'"
                )
            } else {
                XCTAssertFalse(visual.contains("per side"), "bilateral \(prescription.exercise.id) mislabelled")
                XCTAssertFalse(spoken.contains("per side"), "bilateral \(prescription.exercise.id) mislabelled")
            }
        }

        let planned = SessionAssembly.plannedSeconds(of: workout)
        print("planned \(planned)s (\(String(format: "%.1f", Double(planned) / 60)) min) against a "
              + "\(requestedMinutes) min request; \(perSideCount) of \(slots.count) slots are per side")
        XCTAssertGreaterThan(perSideCount, 0, "the transcript proves nothing if the session has no per-side slot")
        XCTAssertLessThanOrEqual(
            abs(planned - requestedMinutes * 60), SessionAssembly.toleranceSeconds,
            "the session has to land within the fit's tolerance of the request"
        )
    }

    // MARK: - Swapping a per-side slot mid-session

    /// The end-user swap path: start the real player on a real session, walk to a per-side slot the way a
    /// user does (finishing sets), tap Swap, and print what changed. The substitute has to stay a
    /// same-pillar/pattern peer, carry its own honest per-side label, keep the slot's role, and leave the
    /// session inside the fit's tolerance.
    func testPlayerSwapAtAPerSideSlotKeepsCopyAndBudget() async throws {
        let workout = try generate()
        let viewModel = player(workout, engine: OnDeviceWorkoutEngine(exerciseService: try MockExerciseService()))
        viewModel.start()

        // Walk forward the way the user does - completing each set - until a per-side slot is on screen.
        var guardRail = 0
        while let step = viewModel.currentStep, step.prescription.exercise.sidesPerSet == 1, guardRail < 200 {
            viewModel.completeSet()
            guardRail += 1
        }
        let before = try XCTUnwrap(viewModel.currentStep, "walked off the end without reaching a per-side slot")
        XCTAssertGreaterThan(before.prescription.exercise.sidesPerSet, 1)

        let plannedBefore = plannedSeconds(of: viewModel.steps.map(\.prescription), like: workout)
        print("=== Rep Today - in-session swap at a per-side slot ===")
        print("before: \(before.blockTitle) · slot \(before.position) of \(before.total) · "
              + "\(before.prescription.exercise.id) · player shows \"\(ActiveSessionView.targetText(before.prescription))\" "
              + "· \(before.prescription.sets) sets · rest \(before.prescription.restSeconds)s")

        await viewModel.swapCurrentExercise()
        XCTAssertFalse(viewModel.noSwapAlternative, "the catalog should offer a peer for this slot")

        let after = try XCTUnwrap(viewModel.currentStep)
        let plannedAfter = plannedSeconds(of: viewModel.steps.map(\.prescription), like: workout)
        print("after:  \(after.blockTitle) · slot \(after.position) of \(after.total) · "
              + "\(after.prescription.exercise.id) · player shows \"\(ActiveSessionView.targetText(after.prescription))\" "
              + "· VoiceOver reads \"\(ActiveSessionView.targetAccessibilityText(after.prescription))\" "
              + "· \(after.prescription.sets) sets · rest \(after.prescription.restSeconds)s")
        print("set count \(before.prescription.sets) -> \(after.prescription.sets)"
              + (before.prescription.sets == after.prescription.sets
                 ? " (slot's own count kept)" : " (re-picked to hold the budget)"))
        print("planned \(plannedBefore)s -> \(plannedAfter)s against a \(requestedMinutes) min request; "
              + "set counter reset to \(viewModel.currentSet)")

        XCTAssertNotEqual(after.prescription.exercise.id, before.prescription.exercise.id, "the slot actually changed")
        XCTAssertEqual(after.prescription.exercise.pillar, before.prescription.exercise.pillar)
        XCTAssertEqual(after.prescription.exercise.movementPattern, before.prescription.exercise.movementPattern)
        XCTAssertEqual(after.blockTitle, before.blockTitle, "the substitute stays in the block it replaced")
        XCTAssertEqual(viewModel.currentSet, 1, "the set counter restarts on the substitute")

        let substituteLabel = ActiveSessionView.targetText(after.prescription)
        if after.prescription.exercise.sidesPerSet > 1 {
            XCTAssertTrue(substituteLabel.hasSuffix(" per side"), "per-side substitute shown as \"\(substituteLabel)\"")
        } else {
            XCTAssertFalse(substituteLabel.contains("per side"), "bilateral substitute shown as \"\(substituteLabel)\"")
        }
        XCTAssertEqual(after.prescription.role, before.prescription.role, "the substitute keeps the slot's role")
        XCTAssertLessThanOrEqual(
            abs(plannedAfter - requestedMinutes * 60), SessionAssembly.toleranceSeconds,
            "the swap left the session outside the fit's tolerance"
        )
    }

    /// Swapping every slot of a real session in turn - not just the one the walk happens to land on. A
    /// swap **keeps the slot's set count and role** everywhere: a Training Day station runs four rounds
    /// like its peers and the warm-up/cooldown stretches stay one set, so a substitute that will not fit at
    /// the kept count is declined outright. One printed line per slot is the reviewable sweep.
    func testSwappingEverySlotKeepsBudgetAndRespectsTheSetLever() async throws {
        let workout = try generate()
        let engine = OnDeviceWorkoutEngine(exerciseService: try MockExerciseService())
        let slotCount = workout.blocks.reduce(0) { $0 + $1.exercises.count }
        // The assembled session's planned wall-clock, before any swap. A swap keeps the slot's set count,
        // so the only thing it moves is the substitute's own per-set work - by at most the swapped slot's
        // `slotTolerance`, which is the swap's contract and what this sweep verifies.
        let plannedBefore = SessionAssembly.plannedSeconds(of: workout)

        print("=== Rep Today - swap sweep over all \(slotCount) slots of a 30 minute session ===")
        var substituted = 0, rePicked = 0, noAlternative = 0
        for index in 0..<slotCount {
            let viewModel = player(workout, engine: engine)
            viewModel.start()
            var guardRail = 0
            while viewModel.currentStepIndex < index, !viewModel.isComplete, guardRail < 400 {
                viewModel.completeSet()
                guardRail += 1
            }
            XCTAssertEqual(viewModel.currentStepIndex, index, "could not park the player on slot \(index + 1)")
            let before = try XCTUnwrap(viewModel.currentStep)

            await viewModel.swapCurrentExercise()
            let after = try XCTUnwrap(viewModel.currentStep)
            let planned = plannedSeconds(of: viewModel.steps.map(\.prescription), like: workout)
            let label = pad("slot \(index + 1)/\(slotCount)", 14) + pad(before.blockTitle, 19)

            if viewModel.noSwapAlternative {
                noAlternative += 1
                print(label + "\(before.prescription.exercise.id): no alternative - original kept, planned \(planned)s")
                XCTAssertEqual(after.prescription.exercise.id, before.prescription.exercise.id)
                continue
            }

            substituted += 1
            let moved = after.prescription.sets != before.prescription.sets
            if moved { rePicked += 1 }
            print(label
                  + pad("\(before.prescription.exercise.id) (\(ActiveSessionView.targetText(before.prescription)))", 40)
                  + "-> " + pad("\(after.prescription.exercise.id) (\(ActiveSessionView.targetText(after.prescription)))", 40)
                  + "sets \(before.prescription.sets)->\(after.prescription.sets) "
                  + (moved ? "MOVED" : "kept") + " · planned \(planned)s")

            XCTAssertEqual(after.prescription.exercise.pillar, before.prescription.exercise.pillar)
            XCTAssertEqual(after.prescription.exercise.movementPattern, before.prescription.exercise.movementPattern)
            XCTAssertTrue(after.prescription.exercise.equipment.isEmpty, "Zero-Equipment Floor")
            let slotTolerance = ExerciseSwap.slotTolerance(
                workSeconds: before.prescription.sets * SessionAssembly.workSecondsPerSet(of: before.prescription)
            )
            XCTAssertLessThanOrEqual(
                abs(planned - plannedBefore), slotTolerance,
                "swapping slot \(index + 1) (\(before.prescription.exercise.id) -> "
                + "\(after.prescription.exercise.id)) moved the session \(abs(planned - plannedBefore))s, "
                + "past the swapped slot's \(slotTolerance)s budget"
            )
            XCTAssertEqual(after.prescription.role, before.prescription.role, "slot \(index + 1) swap lost its role")
            // No slot has a set lever: a circuit runs a uniform round count and a substitute joins at it,
            // the bookends stay one set, so a block can never be left uneven by a swap.
            XCTAssertEqual(
                after.prescription.sets, before.prescription.sets,
                "slot \(index + 1) swap changed the set count \(before.prescription.sets)->\(after.prescription.sets); "
                + "a swap must keep the block's uniform round count"
            )
        }
        print("swept \(slotCount) slots: \(substituted) substituted (\(rePicked) that moved a set count), "
              + "\(noAlternative) with no alternative")
        XCTAssertGreaterThan(substituted, 0)
        XCTAssertEqual(rePicked, 0, "no swap may move a slot's set count")
    }

    // MARK: - Rendered-UI evidence

    /// Hosts a production surface in a real key window and lets it settle, so what follows reads a
    /// laid-out, drawn view - whether that is its pixels or its accessibility tree.
    private func hosted<V: View>(_ view: V, size: CGSize) -> UIHostingController<V> {
        let (host, window) = HostedSurface.host(view, size: size)
        // Held for the lifetime of the test case, because a released window takes the hosted view
        // down with it.
        renderWindow = window
        return host
    }

    /// Renders a production surface to a PNG in `story`'s evidence directory.
    private func render<V: View>(_ view: V, size: CGSize, fileName: String, story: String) throws {
        try renderHosted(hosted(view, size: size), size: size, fileName: fileName, story: story)
    }

    /// Renders an *already-hosted* surface, for a state that only exists once the view has been driven
    /// into it - a running hold, which is unreachable through the restore path by design (US-O03).
    private func renderHosted<V: View>(
        _ host: UIHostingController<V>, size: CGSize, fileName: String, story: String
    ) throws {
        // Capturing (which pins the render scale) is `HostedSurface`'s, and encoding, the did-it-draw
        // check and the write are all `EvidenceOutput`'s, so a capture that failed either precondition
        // never reaches disk to overwrite a committed baseline.
        let image = HostedSurface.capture(host.view, size: size)
        try EvidenceOutput.write(image, named: fileName, for: story)
    }

    /// A resumed-session snapshot parked on `index` - the production path the player uses to reopen an
    /// abandoned session, and so the way to render the player at a mid-session slot without reaching
    /// into it.
    private func resumed(_ workout: Workout, at index: Int, currentSet: Int) -> ActiveSessionState {
        let fresh = ActiveSessionState(fresh: workout)
        var completed: [UUID: [CompletedSet]] = [:]
        for slot in fresh.slots.prefix(index) {
            completed[slot.prescription.id] = (0..<slot.prescription.sets).map { _ in
                CompletedSet(reps: slot.prescription.reps, durationSeconds: slot.prescription.durationSeconds)
            }
        }
        if currentSet > 1 {
            let slot = fresh.slots[index]
            completed[slot.prescription.id] = (0..<(currentSet - 1)).map { _ in
                CompletedSet(reps: slot.prescription.reps, durationSeconds: slot.prescription.durationSeconds)
            }
        }
        return renderable(
            ActiveSessionState(
                workout: fresh.workout, slots: fresh.slots, currentStepIndex: index,
                currentSet: currentSet, completedSets: completed, skippedStepIDs: [],
                startedAt: nil, rest: nil
            )
        )
    }

    /// Normalizes a snapshot for rendering: the elapsed clock is read against the real `Date()` inside
    /// the view, so the origin has to be a real-time one to read plausibly, and any rest in force would
    /// put `RestView` on screen instead of the player.
    private func renderable(_ state: ActiveSessionState) -> ActiveSessionState {
        ActiveSessionState(
            workout: state.workout, slots: state.slots, currentStepIndex: state.currentStepIndex,
            currentSet: state.currentSet, completedSets: state.completedSets,
            skippedStepIDs: state.skippedStepIDs,
            startedAt: Date().addingTimeInterval(-8 * 60 - 12), rest: nil
        )
    }

    /// The player wired the way `ReadyView` wires it - engine, user and history included - so the Swap
    /// control is present and the surface is the production one.
    private func playerView(_ state: ActiveSessionState) throws -> some View {
        ActiveSessionView(
            resuming: state,
            workoutEngine: OnDeviceWorkoutEngine(exerciseService: try MockExerciseService()),
            user: steadyUser(),
            recentLogs: history()
        )
    }

    /// The player on a per-side hold, at default Dynamic Type and at an accessibility size - the second
    /// one is the case the `fixedSize` on the target line exists for, where "per side" would otherwise be
    /// the part that gets truncated away.
    func testRenderPlayerAtAPerSideHold() throws {
        let workout = try generate()
        let slots = workout.blocks.flatMap(\.exercises)
        let index = try XCTUnwrap(
            slots.firstIndex { $0.exercise.sidesPerSet > 1 && $0.exercise.isHold },
            "no per-side hold in the generated session"
        )
        print("rendering the player at slot \(index + 1): \(slots[index].exercise.id) - "
              + "\"\(ActiveSessionView.targetText(slots[index]))\"")
        let state = resumed(workout, at: index, currentSet: 2)

        try render(
            try playerView(state),
            size: CGSize(width: 393, height: 852),
            fileName: "player-per-side-hold.png", story: Evidence.perSideSwap
        )
        try render(
            try playerView(state).environment(\.dynamicTypeSize, .accessibility3),
            size: CGSize(width: 393, height: 852),
            fileName: "player-per-side-hold-accessibility-type.png", story: Evidence.perSideSwap
        )
    }

    /// The player on a per-side *rep* movement, where the suffix lands on a count rather than a clock -
    /// the Legs Day's lead lunge.
    func testRenderPlayerAtAPerSideRepMovement() throws {
        let workout = try generate()
        let slots = workout.blocks.flatMap(\.exercises)
        let index = try XCTUnwrap(
            slots.firstIndex { $0.exercise.sidesPerSet > 1 && !$0.exercise.isHold },
            "no per-side rep movement in the generated session"
        )
        print("rendering the player at slot \(index + 1): \(slots[index].exercise.id) - "
              + "\"\(ActiveSessionView.targetText(slots[index]))\"")
        try render(
            try playerView(resumed(workout, at: index, currentSet: 1)),
            size: CGSize(width: 393, height: 852),
            fileName: "player-per-side-reps.png", story: Evidence.perSideSwap
        )
    }

    /// US-CC02, as the user reads it on the running player: a real strength training block is a circuit,
    /// so its headline reads **"Round N of M"** and the same first station is on screen again in a later
    /// round (the rotation returns to it), while a warm-up bookend keeps the linear **"Set N of M"**. Both
    /// the circuit rounds and the bookend are rendered from the same real generated session, so the
    /// strings on the PNGs are the ones the shipped player shows. A companion transcript records the block
    /// shape (uniform round count) the "Round N of M" label is read off.
    func testRenderStrengthCircuitRoundLabels() throws {
        let workout = try generate()

        // The flat index where the strength (circuit) training block begins, and its uniform round count.
        var flatIndex = 0
        var circuitStart: Int?
        var roundCount = 0
        for block in workout.blocks {
            if SessionAssembly.isCircuit(block.category) {
                circuitStart = flatIndex
                roundCount = block.exercises.map(\.sets).max() ?? 0
                break
            }
            flatIndex += block.exercises.count
        }
        let start = try XCTUnwrap(circuitStart, "the generated session has no circuit training block")
        XCTAssertGreaterThanOrEqual(roundCount, 2, "need at least two rounds to show Round 1 and Round 2")

        let slots = workout.blocks.flatMap(\.exercises)
        let leadStation = slots[start].exercise.id
        print("=== Rep Today - US-CC02 circuit \"Round N of M\" ===")
        print("strength circuit begins at slot \(start + 1) (\(leadStation)); uniform round count M = \(roundCount)")
        print("rendering Round 1 and Round 2 on the same lead station, and the warm-up bookend's Set label")

        // Round 1 of M, then Round 2 of M on the SAME lead station - the rotation returns to it each round.
        try render(
            try playerView(resumed(workout, at: start, currentSet: 1)),
            size: playerSize, fileName: "player-circuit-round-1.png", story: "us-cc02"
        )
        try render(
            try playerView(resumed(workout, at: start, currentSet: 2)),
            size: playerSize, fileName: "player-circuit-round-2.png", story: "us-cc02"
        )
        // The warm-up bookend is not a circuit (US-CC02): it shows "Set N of M", no round.
        try render(
            try playerView(resumed(workout, at: 0, currentSet: 1)),
            size: playerSize, fileName: "player-warmup-bookend-set-label.png", story: "us-cc02"
        )

        // A transcript of what each rendered surface says, so the round labels are reviewable as text too.
        let vmRound1 = ActiveSessionViewModel(state: resumed(workout, at: start, currentSet: 1), now: { self.asOf })
        let vmRound2 = ActiveSessionViewModel(state: resumed(workout, at: start, currentSet: 2), now: { self.asOf })
        let vmWarmup = ActiveSessionViewModel(state: resumed(workout, at: 0, currentSet: 1), now: { self.asOf })
        XCTAssertEqual(vmRound1.currentRound, 1)
        XCTAssertEqual(vmRound1.circuitRoundCount, roundCount)
        XCTAssertEqual(vmRound2.currentRound, 2)
        XCTAssertNil(vmWarmup.currentRound, "the warm-up bookend carries no round")
        let transcript = [
            "# US-CC02 - what the player shows",
            "",
            "| rendered surface | headline shown | block |",
            "| --- | --- | --- |",
            "| player-circuit-round-1.png | Round 1 of \(roundCount) | strength (circuit) |",
            "| player-circuit-round-2.png | Round 2 of \(roundCount) | strength (circuit) |",
            "| player-warmup-bookend-set-label.png | Set 1 of \(slots[0].sets) | warm-up (linear bookend) |",
            "",
            "Lead circuit station: \(leadStation). Every station in the strength block carries the same "
            + "set count (M = \(roundCount)), which is why \"Round N of M\" is well-defined (US-CC03).",
        ].joined(separator: "\n") + "\n"
        try EvidenceOutput.write(transcript, named: "round-label-transcript.md", for: "us-cc02")
    }

    /// The OPT1 fix, as the user sees it: a swap taken mid-circuit keeps the current round rather than
    /// resetting to Round 1. The player is driven through the real rotation into Round 2, a swap is taken,
    /// and the rendered "after" frame still reads Round 2 - the visual counterpart to the
    /// no-double-count regression test, so a reviewer can see the round was not thrown back to 1.
    func testRenderMidCircuitSwapKeepsTheRound() async throws {
        let workout = try generate()
        let viewModel = player(workout, engine: OnDeviceWorkoutEngine(exerciseService: try MockExerciseService()))
        viewModel.start()

        // Rotate the real player until a circuit station is on screen in Round 2 (rotation, not grinding).
        var guardRail = 0
        while guardRail < 400 {
            guardRail += 1
            if viewModel.currentRound == 2 { break }
            guard !viewModel.isComplete else { break }
            if viewModel.isResting { viewModel.skipRest() }
            viewModel.completeSet()
        }
        let before = try XCTUnwrap(viewModel.currentStep, "never reached Round 2 of a circuit")
        XCTAssertEqual(viewModel.currentRound, 2, "parked on Round 2 before the swap")
        try render(
            try playerView(renderable(viewModel.snapshot())),
            size: playerSize, fileName: "player-swap-round-2-before.png", story: "us-cc02"
        )

        await viewModel.swapCurrentExercise()

        XCTAssertEqual(viewModel.currentRound, 2, "the mid-circuit swap kept Round 2 rather than resetting to 1")
        let after = try XCTUnwrap(viewModel.currentStep)
        print("mid-circuit swap on Round 2: \(before.prescription.exercise.id) -> \(after.prescription.exercise.id), "
              + "round stayed \(viewModel.currentRound ?? -1)")
        try render(
            try playerView(renderable(viewModel.snapshot())),
            size: playerSize, fileName: "player-swap-round-2-after.png", story: "us-cc02"
        )
    }

    /// The swap as the user sees it: the player before the tap and after it, both rendered from the real
    /// view model's own snapshot - so the "after" frame is the state the swap actually produced (peer in
    /// place, its own label, the slot's set count, set counter back to 1), not a hand-built one. The slot
    /// is the Legs Day's lead per-side station, the lunge; its peer is the bilateral squat, so the "per
    /// side" suffix the before frame shows is gone from the after frame.
    func testRenderPlayerBeforeAndAfterSwappingAPerSideSlot() async throws {
        let workout = try generate()
        let viewModel = player(workout, engine: OnDeviceWorkoutEngine(exerciseService: try MockExerciseService()))
        viewModel.start()
        var guardRail = 0
        while let step = viewModel.currentStep, guardRail < 200,
              !(step.prescription.exercise.sidesPerSet > 1 && SessionAssembly.isCircuit(step.blockCategory)) {
            viewModel.completeSet()
            guardRail += 1
        }
        let before = try XCTUnwrap(viewModel.currentStep)
        try render(
            try playerView(renderable(viewModel.snapshot())),
            size: CGSize(width: 393, height: 852),
            fileName: "player-swap-before.png", story: Evidence.perSideSwap
        )

        await viewModel.swapCurrentExercise()
        let after = try XCTUnwrap(viewModel.currentStep)
        XCTAssertNotEqual(after.prescription.exercise.id, before.prescription.exercise.id)
        print("swap rendered: \(before.prescription.exercise.id) "
              + "\"\(ActiveSessionView.targetText(before.prescription))\" -> "
              + "\(after.prescription.exercise.id) \"\(ActiveSessionView.targetText(after.prescription))\"")
        try render(
            try playerView(renderable(viewModel.snapshot())),
            size: CGSize(width: 393, height: 852),
            fileName: "player-swap-after.png", story: Evidence.perSideSwap
        )
    }

    /// The Ready Screen the user reads *before* starting: the whole lineup with its targets, so the
    /// "per side" rows can be reviewed where they are first seen. Wired to the same services the app's
    /// mock container uses, with a user whose learned default is the 30 minutes the transcripts use.
    func testRenderReadyScreenWithPerSideRows() throws {
        try render(
            ReadyView(services: try readyServices(), now: { self.asOf }),
            size: CGSize(width: 393, height: 1420),
            fileName: "ready-screen-per-side-rows.png", story: Evidence.perSideSwap
        )
    }

    /// The container `ReadyView` is wired to - the same services the app's mock container uses.
    private func readyServices() throws -> ServiceContainer {
        let exerciseService = try MockExerciseService()
        let userService = MockUserService(user: steadyUser())
        let policyStore = InMemorySessionPolicyStore()
        let consistencyService = ConsistencyScoreService(now: { self.asOf }, calendar: self.calendar)
        let workoutLogService = MockWorkoutLogService(logs: history())
        let activeSessionStore = InMemoryActiveSessionStore()
        let authService = MockAuthService()
        return ServiceContainer(
            exerciseService: exerciseService,
            // Pin the assembler's clock so the hosted Ready Screen generates the same lineup as
            // `generate()` (fixed `asOf`), rather than drifting with the wall clock and diverging by
            // a staleness tier as real time moves away from the fixture date.
            workoutEngine: OnDeviceWorkoutEngine(exerciseService: exerciseService, now: { self.asOf }),
            sessionPolicyService: DeterministicSessionPolicyService(
                store: policyStore, exerciseService: exerciseService, userService: userService
            ),
            consistencyService: consistencyService,
            phaseService: PhaseEvaluatorService(exerciseService: exerciseService),
            userService: userService,
            workoutLogService: workoutLogService,
            activeSessionStore: activeSessionStore,
            sessionCompletionService: SessionCompletionService(
                workoutLogService: workoutLogService, userService: userService,
                consistencyService: consistencyService,
                phaseService: PhaseEvaluatorService(exerciseService: exerciseService),
                policyStore: policyStore
            ),
            healthKitService: MockHealthKitService(),
            subscriptionService: MockSubscriptionService(),
            premiumSessionAuthority: PremiumSessionAuthority(),
            authService: authService,
            analyticsService: MockAnalyticsService(),
            accountDeletionService: AccountDeletionService(
                userService: userService,
                workoutLogService: workoutLogService,
                sessionPolicyStore: policyStore,
                activeSessionStore: activeSessionStore,
                authService: authService
            )
        )
    }

    // MARK: - The spoken target agrees with its own counts

    /// Walks a real 30-minute session and prints what the screen shows against what VoiceOver reads at
    /// every slot, gating each spoken string on agreeing with its own numbers. The warm-up and cooldown
    /// bookends are single-set, so the singular is the first and last thing a screen-reader user hears
    /// in *every* session, however short - it used to read "1 sets of 45 second holds" there. The
    /// printed table and the written transcript are the artifact; the assertions make them a gate.
    func testGeneratedSessionSpeaksAGrammaticalTargetAtEverySlot() throws {
        let workout = try generate()
        let slots = workout.blocks.flatMap { block in block.exercises.map { (block.title, $0) } }

        print("=== Rep Today - what VoiceOver reads at every slot of a real 30 minute session ===")
        print(pad("BLOCK", 19) + pad("MOVEMENT", 28) + pad("SCREEN SHOWS", 20) + "VOICEOVER READS")
        var transcript = ["| Block | Movement | Screen shows | VoiceOver reads |", "| --- | --- | --- | --- |"]
        for (blockTitle, prescription) in slots {
            let visual = ActiveSessionView.targetText(prescription)
            let spoken = ActiveSessionView.targetAccessibilityText(prescription)
            print(pad(blockTitle, 19) + pad(prescription.exercise.id, 28) + pad(visual, 20) + "\"\(spoken)\"")
            transcript.append("| \(blockTitle) | \(prescription.exercise.displayName) | `\(visual)` | \(spoken) |")
            assertSpokenTargetAgrees(spoken, with: prescription)
        }

        let bookends = [try XCTUnwrap(slots.first), try XCTUnwrap(slots.last)]
        for (blockTitle, prescription) in bookends {
            XCTAssertEqual(
                prescription.sets, 1,
                "\(blockTitle) is expected to be the single-set shape that made this bug unavoidable"
            )
            XCTAssertTrue(
                ActiveSessionView.targetAccessibilityText(prescription).hasPrefix("1 set of "),
                "the \(blockTitle) bookend still reads plural"
            )
        }

        try EvidenceOutput.write(transcript.joined(separator: "\n") + "\n", named: "voiceover-target-transcript.md", for: Evidence.perSideSwap)
    }

    /// Gates one spoken target against the prescription behind it: the set count, the rep noun and the
    /// hold noun each have to agree with their own number, and the " per side" suffix has to survive
    /// the pluralisation rather than being swallowed by it.
    private func assertSpokenTargetAgrees(
        _ spoken: String, with prescription: PrescribedExercise,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let sets = prescription.sets
        XCTAssertTrue(
            spoken.hasPrefix(sets == 1 ? "1 set of " : "\(sets) sets of "),
            "\(prescription.exercise.id) prescribes \(sets) set(s) but VoiceOver reads \"\(spoken)\"",
            file: file, line: line
        )
        if let reps = prescription.reps {
            XCTAssertTrue(
                spoken.contains(reps == 1 ? "of 1 rep" : "of \(reps) reps"),
                "\(prescription.exercise.id) prescribes \(reps) rep(s) but VoiceOver reads \"\(spoken)\"",
                file: file, line: line
            )
            XCTAssertFalse(spoken.contains(" 1 reps"), "\"\(spoken)\"", file: file, line: line)
        }
        if let seconds = prescription.durationSeconds {
            XCTAssertTrue(
                spoken.contains(sets == 1 ? "of a \(seconds) second hold" : "of \(seconds) second holds"),
                "\(prescription.exercise.id) is a \(seconds)s hold over \(sets) set(s) but VoiceOver "
                + "reads \"\(spoken)\"",
                file: file, line: line
            )
        }
        XCTAssertEqual(
            spoken.hasSuffix(" per side"), prescription.exercise.sidesPerSet > 1,
            "the per-side suffix did not survive pluralisation in \"\(spoken)\"",
            file: file, line: line
        )
    }

    /// The Ready Screen is where the user first meets the lineup, and it carried its own copy of the
    /// formatter that fed the *visual* string to VoiceOver - so the preview spoke "3 multiplication 12"
    /// where the player spoke the nouns. These labels are read off the live view tree of the real
    /// screen, not re-derived from the formatter, so they are what VoiceOver would actually announce.
    func testReadyScreenRowsSpeakTheNounsRatherThanTheGlyph() throws {
        let slots = try generate().blocks.flatMap(\.exercises)
        let host = hosted(ReadyView(services: try readyServices(), now: { self.asOf }), size: CGSize(width: 393, height: 1420))
        let labels = AccessibilityTree.labels(in: host.view)

        print("=== Rep Today - Ready Screen lineup, accessibility labels read off the live view tree ===")
        var rows: [String] = []
        for prescription in slots {
            let name = prescription.exercise.displayName
            let row = try XCTUnwrap(
                labels.first { $0.hasPrefix("\(name), ") },
                "no Ready Screen row for \(name); the screen reads \(labels)"
            )
            print("  \"\(row)\"")
            rows.append(row)
            XCTAssertEqual(
                row, "\(name), \(ActiveSessionView.targetAccessibilityText(prescription))",
                "the Ready Screen describes \(name) differently from the player the user works it on"
            )
            assertSpokenTargetAgrees(String(row.dropFirst(name.count + 2)), with: prescription)
        }

        for label in labels {
            XCTAssertFalse(
                label.contains("×"),
                "a screen reader would read the multiplication glyph aloud: \"\(label)\""
            )
        }
        try EvidenceOutput.write(rows.map { "- \($0)" }.joined(separator: "\n") + "\n", named: "ready-screen-voiceover-labels.md", for: Evidence.perSideSwap)
    }

    /// The player parked on each single-set bookend - the warm-up the session opens on and the cooldown
    /// it closes on - captured with the spoken target printed alongside, so the rendered screen and the
    /// string read over it can be reviewed together.
    func testRenderPlayerAtTheSingleSetBookends() throws {
        let workout = try generate()
        let slots = workout.blocks.flatMap(\.exercises)
        let bookends = [(0, "player-bookend-warmup.png"), (slots.count - 1, "player-bookend-cooldown.png")]

        for (index, fileName) in bookends {
            let prescription = slots[index]
            print("rendering slot \(index + 1)/\(slots.count): \(prescription.exercise.id) - screen shows "
                  + "\"\(ActiveSessionView.targetText(prescription))\", VoiceOver reads "
                  + "\"\(ActiveSessionView.targetAccessibilityText(prescription))\"")
            try render(
                try playerView(resumed(workout, at: index, currentSet: 1)),
                size: CGSize(width: 393, height: 852),
                fileName: fileName,
                story: Evidence.perSideSwap
            )
        }
    }

    // MARK: - Session timer redesign (US-O03)

    private var playerSize: CGSize { CGSize(width: 393, height: 852) }

    /// The flat index (into `workout.blocks.flatMap(\.exercises)`) of the first timed hold in the
    /// **training** circuit (`SessionAssembly.isCircuit`) - on the fixture's Legs Day, the Core Sprinkle's
    /// side plank. The US-O03 Hold Timer surfaces below read a training hold rather than a warm-up or
    /// cooldown bookend hold. `perSide` narrows it to a two-leg hold when the side copy is what is under
    /// test. `nil` when the generated session carries no such hold.
    private func firstTrainingHoldIndex(in workout: Workout, perSide: Bool = false) -> Int? {
        var flat = 0
        for block in workout.blocks {
            let training = SessionAssembly.isCircuit(block.category)
            for slot in block.exercises {
                let timed = slot.exercise.isHold && (slot.durationSeconds ?? 0) > 0
                let sideOK = !perSide || slot.exercise.sidesPerSet > 1
                if training && timed && sideOK { return flat }
                flat += 1
            }
        }
        return nil
    }

    /// A hosted player with its hold actually running, for rendering and reading mid-countdown.
    ///
    /// The leg starts on its own as the player appears (ADR-0010: every hold auto-starts, training holds
    /// included), which is the only way a running leg is reachable: a hold is never persisted (US-O03),
    /// so there is no snapshot that restores one. The helper asserts no Start-hold tap was needed.
    ///
    /// `settlingAt` pins what the ring *reads* before the surface is handed back, which is what a render
    /// needs. Without it the leg is captured a fraction of a second after it started, so whether the
    /// countdown shows N or N-1 - and the arc's fill fraction with it, since that is `remaining / total`
    /// over whole seconds - depends on how the runloop pump happens to land, and the PNG's bytes churn
    /// between runs for no change in behaviour. Waiting for the exact remaining second puts the capture
    /// inside a whole one-second window instead, and the extra settle lets the arc's 0.5s animation
    /// finish. The clock underneath is the real one, so this is as far as determinism honestly goes:
    /// the number and the arc are pinned, the frame's antialiasing is not.
    private func hostedMidHold<V: View>(
        _ view: V, size: CGSize, settlingAt settlingSeconds: Int? = nil
    ) throws -> UIHostingController<V> {
        let host = hosted(view, size: size)
        let appeared = AccessibilityTree.labels(in: host.view)
        XCTAssertFalse(
            appeared.contains { $0.hasPrefix("Start hold") },
            "the hold should start on its own, with no Start-hold tap; it reads \(appeared)"
        )

        func pump(until end: Date) {
            RunLoop.main.run(mode: .default, before: end)
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
        }

        guard let settlingSeconds else {
            pump(until: Date().addingTimeInterval(0.6))
            return host
        }

        // The leg started as the player appeared, so hosting may already have used up a second or two:
        // pin the requested second, or the next whole second still ahead if that one has passed.
        let showing = appeared.compactMap { label -> Int? in
            guard label.hasPrefix("Hold, "), label.hasSuffix(" seconds remaining") else { return nil }
            return Int(label.dropFirst("Hold, ".count).dropLast(" seconds remaining".count))
        }.first
        let pinned = showing.map { min(settlingSeconds, $0 - 1) } ?? settlingSeconds
        let target = "Hold, \(pinned) seconds remaining"
        func reads(_ label: String) -> Bool { AccessibilityTree.labels(in: host.view).contains(label) }
        let ceiling = Date().addingTimeInterval(20)
        while Date() < ceiling && !reads(target) {
            pump(until: Date().addingTimeInterval(0.02))
        }
        XCTAssertTrue(
            reads(target),
            "the countdown never settled at \"\(target)\"; it reads \(AccessibilityTree.labels(in: host.view))"
        )
        // Let the arc finish animating to its new fill, in small steps and only while the second just
        // pinned is still the one on screen, so a slow machine gives up the settle rather than the pin.
        let settled = Date().addingTimeInterval(0.55)
        while Date() < settled && reads(target) {
            pump(until: Date().addingTimeInterval(0.05))
        }
        return host
    }

    /// The player at a timed movement, idle then mid-hold, read off the live accessibility tree of the
    /// production surface (US-O03).
    ///
    /// Two things are gated together because they are the same change: a timed movement now leads with
    /// its own countdown rather than a "Complete set" tap, and the always-on elapsed clock that used
    /// to sit in the top bar is gone. The clock half is asserted on the tree rather than assumed from
    /// the source, so re-adding it - the regression this story exists to prevent - fails here.
    ///
    /// The timer is the primary action, not the only one: the manual way to bank the set stays on the
    /// row as a quiet secondary throughout, idle *and* mid-leg. A user interrupted part-way through a
    /// plank must not have to choose between "Stop hold", which records nothing, and "Skip", which
    /// discards every set already banked for the exercise - so this asserts the non-destructive way out
    /// is on screen in both states.
    func testHoldTimerReplacesTheAlwaysOnSessionClock() throws {
        let workout = try generate()
        let slots = workout.blocks.flatMap(\.exercises)
        // A *training* hold: since ADR-0010 it auto-starts like a bookend hold, and "Start hold" returns
        // only after the user deliberately stops it.
        let holdIndex = try XCTUnwrap(
            firstTrainingHoldIndex(in: workout),
            "the generated session carries no training-block timed hold (bookend holds auto-start, US-CC05)"
        )
        let hold = slots[holdIndex]
        let sides = hold.exercise.sidesPerSet
        let seconds = try XCTUnwrap(hold.durationSeconds)
        print("=== Rep Today - the player at \(hold.exercise.id): \(seconds)s"
              + (sides > 1 ? " per side, two legs per set" : "") + " ===")

        let state = resumed(workout, at: holdIndex, currentSet: 1)
        let expectedStart = sides > 1 ? "Start hold, side 1 of \(sides)" : "Start hold"
        let manualTitle = hold.sets > 1
            ? "Complete set"
            : (holdIndex == slots.count - 1 ? "Finish session" : "Finish exercise")

        // Running: the leg starts on its own as the player appears (ADR-0010), the countdown takes the
        // demo's place and speaks the seconds it has left.
        let runningHost = try hostedMidHold(try playerView(state), size: playerSize, settlingAt: seconds - 1)
        let runningLabels = AccessibilityTree.labels(in: runningHost.view)
        XCTAssertTrue(
            runningLabels.contains { $0.hasPrefix("Hold, ") && $0.hasSuffix(" seconds remaining") },
            "a running hold should speak its remaining seconds; it reads \(runningLabels)"
        )
        XCTAssertTrue(runningLabels.contains("Stop hold"), "and offer the quiet way out of it")
        XCTAssertTrue(
            runningLabels.contains(manualTitle),
            "a running leg must keep \"\(manualTitle)\" offered - without it the only ways out are "
            + "\"Stop hold\", which records nothing, and \"Skip\", which discards the sets already "
            + "banked for this exercise; it reads \(runningLabels)"
        )
        XCTAssertTrue(
            runningLabels.contains("Skip this exercise"),
            "the row keeps its slots while the hold runs; it reads \(runningLabels)"
        )
        try renderHosted(runningHost, size: playerSize, fileName: "player-hold-running.png", story: Evidence.sessionTimer)

        // Idle, after a deliberate Stop hold: the Hold Timer leads again with "Start hold", and the
        // manual completion stays a quiet secondary.
        let stop = try XCTUnwrap(AccessibilityTree.element(labeled: "Stop hold", in: runningHost.view))
        XCTAssertTrue(stop.accessibilityActivate(), "the Stop hold control did not activate")
        RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.3))
        runningHost.view.setNeedsLayout()
        runningHost.view.layoutIfNeeded()
        let idleLabels = AccessibilityTree.labels(in: runningHost.view)
        XCTAssertTrue(
            idleLabels.contains(expectedStart),
            "a stopped hold should offer \"\(expectedStart)\" as the way back; it reads \(idleLabels)"
        )
        XCTAssertTrue(
            idleLabels.contains(manualTitle),
            "an idle hold should still offer \"\(manualTitle)\" as the way to bank a set held off-timer; "
            + "it reads \(idleLabels)"
        )
        try renderHosted(runningHost, size: playerSize, fileName: "player-hold-idle.png", story: Evidence.sessionTimer)

        for labels in [idleLabels, runningLabels] {
            XCTAssertFalse(
                labels.contains { $0.hasPrefix("Elapsed time") },
                "the always-on session clock is back on the player: \(labels)"
            )
        }
    }

    /// A per-side hold is two legs per set, and the player has to say so on every surface that counts
    /// them (US-O02 + US-O03): the button names the side it is about to start, the tracker names the
    /// side the set is on, and the spoken forms agree. Without this a user follows one countdown, calls
    /// the set done, and quietly does half the work the session was planned around.
    func testPerSideHoldNamesTheSideOnEverySurface() throws {
        let workout = try generate()
        let slots = workout.blocks.flatMap(\.exercises)
        let index = try XCTUnwrap(
            slots.firstIndex { $0.exercise.isHold && $0.exercise.sidesPerSet > 1 && ($0.durationSeconds ?? 0) > 0 },
            "the generated session carries no per-side hold"
        )
        let slot = slots[index]
        let seconds = try XCTUnwrap(slot.durationSeconds)
        print("=== Rep Today - \(slot.exercise.id): \(seconds)s per side, so one set is two legs ===")

        // The leg starts on its own (ADR-0010), so side 1 is already running as the player appears.
        let firstSide = resumed(workout, at: index, currentSet: 1)
        let firstLabels = AccessibilityTree.labels(in: hosted(try playerView(firstSide), size: playerSize).view)
        XCTAssertFalse(
            firstLabels.contains { $0.hasPrefix("Start hold") },
            "side 1 should start on its own; it reads \(firstLabels)"
        )
        XCTAssertTrue(
            // Inside the strength circuit block the tracker leads with "Round N of M" (US-CC02); a
            // linear bookend would lead with "Set N of M". Either way it names the side the set is on.
            firstLabels.contains { $0.contains("side 1 of 2") && ($0.hasPrefix("Set ") || $0.hasPrefix("Round ")) },
            "the set tracker should name the side the set is on; it reads \(firstLabels)"
        )
        XCTAssertTrue(
            firstLabels.contains("\(slot.exercise.displayName), \(ActiveSessionView.targetAccessibilityText(slot))"),
            "the spoken target still carries its per-side suffix; it reads \(firstLabels)"
        )
        try render(try playerView(firstSide), size: playerSize, fileName: "player-per-side-hold-side-1.png", story: Evidence.sessionTimer)

        // Between the legs - the state a relaunch restores to, so it must resume on side 2.
        var secondSide = firstSide
        secondSide.hold = ActiveSessionState.Hold(side: 2)
        let secondLabels = AccessibilityTree.labels(in: hosted(try playerView(secondSide), size: playerSize).view)
        XCTAssertTrue(
            secondLabels.contains { $0.contains("side 2 of 2") && ($0.hasPrefix("Set ") || $0.hasPrefix("Round ")) },
            "a restored between-legs hold owes side 2 and starts it; it reads \(secondLabels)"
        )
        try render(try playerView(secondSide), size: playerSize, fileName: "player-per-side-hold-side-2.png", story: Evidence.sessionTimer)
    }

    /// The rest overlay lost its clock too (US-O03) - it kept the countdown that is *about* the rest and
    /// dropped the session total that was only ever pressure. Rendered beside the player for review.
    func testRestOverlayCarriesItsCountdownButNoSessionClock() throws {
        let workout = try generate()
        var state = resumed(workout, at: 1, currentSet: 1)
        state.rest = ActiveSessionState.Rest(
            totalSeconds: 45, deadline: Date().addingTimeInterval(28), remainingWhenPaused: nil
        )

        let labels = AccessibilityTree.labels(in: hosted(try playerView(state), size: playerSize).view)

        XCTAssertTrue(
            labels.contains { $0.hasPrefix("Rest, ") && $0.hasSuffix(" seconds remaining") },
            "the rest keeps its own countdown; the overlay reads \(labels)"
        )
        XCTAssertFalse(
            labels.contains { $0.hasPrefix("Elapsed time") },
            "the always-on session clock is back on the rest overlay: \(labels)"
        )
        try render(try playerView(state), size: playerSize, fileName: "player-rest-overlay.png", story: Evidence.sessionTimer)
    }

    /// The Hold Timer driven the way a user drives it, in real time (US-O03).
    ///
    /// Everything else about the hold is asserted against an injected clock or a static render. This one
    /// hosts the production `ActiveSessionView`, lets its hold start on its own (ADR-0010), and then
    /// lets the wall clock actually run out - so the `Timer` publisher, the
    /// deadline arithmetic, the auto-record and the hand-off to the rest overlay are all exercised as
    /// one live system rather than as pieces. The hold is authored short so the test does not have to
    /// wait out a real 30-second plank.
    func testHoldTimerRunsDownAndHandsOffToRestInTheLivePlayer() throws {
        let workout = shortHoldWorkout(seconds: 2, sets: 1)

        // The hold starts on its own as the player appears (ADR-0010) - no Start-hold tap.
        let host = hosted(ActiveSessionView(resuming: ActiveSessionState(fresh: workout)), size: playerSize)
        XCTAssertFalse(
            AccessibilityTree.labels(in: host.view).contains { $0.hasPrefix("Start hold") },
            "the live player should not wait for a Start-hold tap; it reads \(AccessibilityTree.labels(in: host.view))"
        )

        // Let the hold actually run out in wall-clock time. The runloop is pumped until the hand-off
        // has *settled* - the rest overlay up and the countdown torn down - rather than for a fixed
        // budget, so a loaded machine that takes longer to push the update through still tests the
        // behaviour instead of failing on the clock. The ceiling is far past any honest run of a
        // 2-second hold, so a real regression still fails rather than hanging.
        func handedOffToRest(_ labels: [String]) -> Bool {
            labels.contains { $0.hasPrefix("Rest, ") && $0.hasSuffix(" seconds remaining") }
                && !labels.contains { $0.hasPrefix("Hold, ") }
        }
        let ceiling = Date().addingTimeInterval(20)
        var after: [String] = []
        repeat {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.1))
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
            after = AccessibilityTree.labels(in: host.view)
        } while Date() < ceiling && !handedOffToRest(after)

        print("=== Rep Today - after a live 2 second hold, the player reads: \(after) ===")
        XCTAssertTrue(
            after.contains { $0.hasPrefix("Rest, ") && $0.hasSuffix(" seconds remaining") },
            "the hold should have recorded its set and handed off to the rest; the player reads \(after)"
        )
        XCTAssertFalse(
            after.contains { $0.hasPrefix("Hold, ") },
            "the countdown should be gone once it reached zero; the player reads \(after)"
        )
        XCTAssertFalse(
            after.contains { $0.hasPrefix("Elapsed time") },
            "no running session clock anywhere in the live session; the player reads \(after)"
        )
    }

    /// The auto-advancing work window driven live through the production player (US-CC01).
    ///
    /// A rep-based strength set opens on a countdown ring with **no tap** - the window auto-starts,
    /// unlike the tap-started hold - runs down on the real `Timer` publisher in wall-clock time, and
    /// hands off to the rest at zero having recorded the set. Exercising the publisher, the deadline
    /// arithmetic and the hands-free auto-advance as one system rather than as view-model pieces; the
    /// runloop is pumped until the hand-off has *settled* rather than for a fixed budget, so a loaded
    /// machine still tests the behaviour instead of failing on the clock.
    func testWorkWindowAutoAdvancesHandsFreeInTheLivePlayer() throws {
        // Longer than `HostedSurface`'s settle interval, so the window is still running when the freshly
        // hosted surface is first read - then the loop below drives it the rest of the way to zero.
        let workout = shortRepWorkout(seconds: 5, sets: 1)
        let host = hosted(ActiveSessionView(resuming: ActiveSessionState(fresh: workout)), size: playerSize)

        // No tap: the set opens already counting down on its work window.
        let opening = AccessibilityTree.labels(in: host.view)
        XCTAssertTrue(
            opening.contains { $0.hasPrefix("Work window, ") && $0.hasSuffix(" seconds remaining") },
            "the rep-based set should open hands-free on an auto-advancing work window; "
            + "the player reads \(opening)"
        )

        func handedOffToRest(_ labels: [String]) -> Bool {
            labels.contains { $0.hasPrefix("Rest, ") && $0.hasSuffix(" seconds remaining") }
                && !labels.contains { $0.hasPrefix("Work window, ") }
        }
        let ceiling = Date().addingTimeInterval(20)
        var after: [String] = []
        repeat {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.1))
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
            after = AccessibilityTree.labels(in: host.view)
        } while Date() < ceiling && !handedOffToRest(after)

        print("=== Rep Today - after a live 2 second work window, the player reads: \(after) ===")
        XCTAssertTrue(
            after.contains { $0.hasPrefix("Rest, ") && $0.hasSuffix(" seconds remaining") },
            "the window should have auto-advanced into the rest with no tap; the player reads \(after)"
        )
        XCTAssertFalse(
            after.contains { $0.hasPrefix("Work window, ") },
            "the countdown should be gone once it reached zero; the player reads \(after)"
        )
    }

    /// The **Done** control driven live through the production player (US-CC01).
    ///
    /// Activated the way VoiceOver's double-tap does - driving the shipped control rather than a
    /// view-model call - it ends a still-running work window early and advances immediately into the
    /// rest, with no penalty prompt. The window is authored long, so it is unambiguously still running
    /// when Done is pressed and nothing but Done could have advanced it.
    func testDoneControlAdvancesEarlyInTheLivePlayer() throws {
        let workout = shortRepWorkout(seconds: 120, sets: 1)
        let host = hosted(ActiveSessionView(resuming: ActiveSessionState(fresh: workout)), size: playerSize)

        let running = AccessibilityTree.labels(in: host.view)
        XCTAssertTrue(
            running.contains { $0.hasPrefix("Work window, ") },
            "the work window should be running before Done is pressed; the player reads \(running)"
        )

        let done = try XCTUnwrap(
            AccessibilityTree.element(labeled: "Done", in: host.view),
            "the live player offers no Done control; it reads \(running)"
        )
        XCTAssertTrue(done.accessibilityActivate(), "the Done control did not activate")

        // The window's node must be gone *and* the rest up before we read the settled state - the freed
        // demo-slot countdown lingers in the tree for a beat after the swap to `RestView`.
        func advancedToRest(_ labels: [String]) -> Bool {
            labels.contains { $0.hasPrefix("Rest, ") && $0.hasSuffix(" seconds remaining") }
                && !labels.contains { $0.hasPrefix("Work window, ") }
        }
        let ceiling = Date().addingTimeInterval(20)
        var after: [String] = []
        repeat {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.1))
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
            after = AccessibilityTree.labels(in: host.view)
        } while Date() < ceiling && !advancedToRest(after)

        print("=== Rep Today - after pressing Done on a live work window, the player reads: \(after) ===")
        XCTAssertTrue(
            after.contains { $0.hasPrefix("Rest, ") && $0.hasSuffix(" seconds remaining") },
            "Done should advance early into the rest; the player reads \(after)"
        )
        XCTAssertFalse(
            after.contains { $0.hasPrefix("Work window, ") },
            "the window should be gone after Done; the player reads \(after)"
        )
    }

    /// A session of short rep-based strength sets, so a live test can drive the auto-advancing work
    /// window to zero without waiting out a real 40-second set. `estimatedTimePerSetSeconds == seconds`
    /// against a 1-rep default prices the window at `round(seconds x SessionAssembly.workPaceGenerosityFactor)`
    /// - the rep branch is paced (US-CC08) - so the timing is deterministic but *longer than* `seconds`:
    /// `seconds: 5` runs a 6s window and `seconds: 120` a 150s one. Both callers still hold at those
    /// paced numbers (6s stays under the 20s runloop ceiling; 150s stays comfortably running for the Done
    /// test), so budget against the paced value, not the raw one. Two slots, so finishing the first hands
    /// off to a rest rather than ending the session.
    private func shortRepWorkout(seconds: Int, sets: Int) -> Workout {
        let rep = Exercise(
            id: "evidence_short_rep", displayName: "Short Rep", pillar: .strength,
            movementPattern: .push, category: .strength, difficulty: 1, phase: .discipline,
            equipment: [], isHold: false, defaultReps: 1, defaultDurationSeconds: nil,
            estimatedTimePerSetSeconds: seconds, metValue: 3, progressionChainId: "evidence_rep_chain",
            progressionOrder: 0, regressionId: nil, progressionId: nil,
            advancementCriteria: "do it", apartmentFriendly: true
        )
        func slot() -> PrescribedExercise {
            PrescribedExercise(
                id: UUID(), exercise: rep, sets: sets, reps: 1, durationSeconds: nil, restSeconds: 30
            )
        }
        return Workout(
            id: UUID(), createdAt: asOf, shape: .blend, focusPillar: nil,
            requestedMinutes: 5, wasReturn: false,
            blocks: [
                WorkoutBlock(
                    id: UUID(), title: "Strength", category: .strength, exercises: [slot(), slot()]
                )
            ]
        )
    }

    /// Banking the set by hand *while* a leg runs, driven through the real controls on the hosted
    /// production player (US-O03).
    ///
    /// This is the non-destructive way out of a running hold, and it has to be reachable in one tap from
    /// the running state: the alternatives are "Stop hold", which records nothing, and "Skip", which
    /// discards every set already banked for the exercise. The leg is started and then banked through
    /// the accessibility tree the way VoiceOver's double-tap does, so what is gated is the control a
    /// user can actually reach mid-plank rather than a view-model call.
    func testBankingASetByHandMidLegEndsTheLegAndOpensTheRestInTheLivePlayer() throws {
        // Long enough that the leg is unambiguously still running when the set is banked by hand. A
        // single-station block, so banking round 1 advances to round 2 of the *same* hold - a
        // single-station circuit plays its rounds as that one exercise's successive sets (US-CC02) -
        // rather than rotating to another station.
        let workout = singleStationShortHoldWorkout(seconds: 120, sets: 2)

        // The leg starts on its own as the player appears (ADR-0010).
        let host = hosted(ActiveSessionView(resuming: ActiveSessionState(fresh: workout)), size: playerSize)
        RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.6))
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()

        let running = AccessibilityTree.labels(in: host.view)
        XCTAssertTrue(
            running.contains { $0.hasPrefix("Hold, ") },
            "the leg should be running before it is banked by hand; the player reads \(running)"
        )

        let bank = try XCTUnwrap(
            AccessibilityTree.element(labeled: "Complete set", in: host.view),
            "a running leg offers no way to bank the set without discarding the exercise; "
            + "the player reads \(running)"
        )
        XCTAssertTrue(bank.accessibilityActivate(), "the manual completion did not activate")

        func banked(_ labels: [String]) -> Bool {
            labels.contains { $0.hasPrefix("Rest, ") && $0.hasSuffix(" seconds remaining") }
                && !labels.contains { $0.hasPrefix("Hold, ") }
        }
        let ceiling = Date().addingTimeInterval(20)
        var after: [String] = []
        repeat {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.1))
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
            after = AccessibilityTree.labels(in: host.view)
        } while Date() < ceiling && !banked(after)

        print("=== Rep Today - after banking a set by hand mid-leg, the player reads: \(after) ===")
        XCTAssertFalse(
            after.contains { $0.hasPrefix("Hold, ") },
            "the running leg should have come down with the tap; the player reads \(after)"
        )
        XCTAssertTrue(
            after.contains { $0.hasPrefix("Rest, ") && $0.hasSuffix(" seconds remaining") },
            "and the set should have been banked, opening the rest; the player reads \(after)"
        )
        XCTAssertTrue(
            after.contains { $0.contains("Round 2 of 2") },
            "with the round advanced exactly one, as it is when the timer runs out; "
            + "the player reads \(after)"
        )
    }

    /// A session of short holds, so a live test can drive a real countdown without waiting out a real
    /// 30-second plank. Two slots, so finishing the first is an exercise hand-off rather than the end
    /// of the session.
    private func shortHoldWorkout(seconds: Int, sets: Int) -> Workout {
        let hold = Exercise(
            id: "evidence_short_hold", displayName: "Short Hold", pillar: .strength,
            movementPattern: .core, category: .strength, difficulty: 1, phase: .discipline,
            equipment: [], isHold: true, defaultReps: nil, defaultDurationSeconds: seconds,
            estimatedTimePerSetSeconds: 10, metValue: 3, progressionChainId: "evidence_chain",
            progressionOrder: 0, regressionId: nil, progressionId: nil,
            advancementCriteria: "hold it", apartmentFriendly: true
        )
        func slot() -> PrescribedExercise {
            PrescribedExercise(
                id: UUID(), exercise: hold, sets: sets, reps: nil,
                durationSeconds: seconds, restSeconds: 30
            )
        }
        return Workout(
            id: UUID(), createdAt: asOf, shape: .blend, focusPillar: nil,
            requestedMinutes: 5, wasReturn: false,
            blocks: [
                WorkoutBlock(
                    id: UUID(), title: "Strength", category: .strength, exercises: [slot(), slot()]
                )
            ]
        )
    }

    /// A single-station short-hold block, so a multi-set hold's *own* round-to-round progression is what
    /// a live test drives (US-CC02: a single-station circuit plays its rounds as that one exercise's
    /// successive sets) rather than the rotation moving to a second station.
    private func singleStationShortHoldWorkout(seconds: Int, sets: Int) -> Workout {
        let hold = Exercise(
            id: "evidence_short_hold", displayName: "Short Hold", pillar: .strength,
            movementPattern: .core, category: .strength, difficulty: 1, phase: .discipline,
            equipment: [], isHold: true, defaultReps: nil, defaultDurationSeconds: seconds,
            estimatedTimePerSetSeconds: 10, metValue: 3, progressionChainId: "evidence_chain",
            progressionOrder: 0, regressionId: nil, progressionId: nil,
            advancementCriteria: "hold it", apartmentFriendly: true
        )
        return Workout(
            id: UUID(), createdAt: asOf, shape: .blend, focusPillar: nil,
            requestedMinutes: 5, wasReturn: false,
            blocks: [
                WorkoutBlock(
                    id: UUID(), title: "Strength", category: .strength,
                    exercises: [PrescribedExercise(
                        id: UUID(), exercise: hold, sets: sets, reps: nil,
                        durationSeconds: seconds, restSeconds: 30
                    )]
                )
            ]
        )
    }

    /// The secondary row at an accessibility Dynamic Type size (US-O03).
    ///
    /// A timed movement carries several columns - Swap, the manual completion, Skip - across a 393pt
    /// row, and the manual one carries the longest title in it ("Finish exercise"), which is the part
    /// that says what the tap actually does. At the largest type sizes that title never clips: either
    /// the control grows past the 60pt touch target to wrap it, or - once the columns cannot hold its
    /// words - the controls stack full width and it fits on one line. Measured off the live
    /// accessibility tree at both sizes, because a render alone cannot tell a grown row from a clipped
    /// one.
    func testManualHoldCompletionGrowsRatherThanClippingAtAccessibilityType() throws {
        let workout = try generate()
        let slots = workout.blocks.flatMap(\.exercises)
        let index = try XCTUnwrap(
            slots.indices.first { slots[$0].exercise.isHold && (slots[$0].durationSeconds ?? 0) > 0 },
            "the generated session carries no timed movement to hold"
        )
        // Parked on the exercise's last set, where the manual control carries the row's longest title.
        let state = resumed(workout, at: index, currentSet: slots[index].sets)
        let title = index == slots.count - 1 ? "Finish session" : "Finish exercise"

        let atDefault = try XCTUnwrap(
            AccessibilityTree.element(labeled: title, in: hosted(try playerView(state), size: playerSize).view),
            "the idle hold offers no \"\(title)\" control"
        ).accessibilityFrame.height
        XCTAssertGreaterThanOrEqual(
            atDefault, Theme.Spacing.workoutTouchTarget - 0.5,
            "the manual completion must meet the 60pt active-screen touch target"
        )

        let axHost = hosted(
            try playerView(state).environment(\.dynamicTypeSize, .accessibility3), size: playerSize
        )
        let control = try XCTUnwrap(
            AccessibilityTree.element(labeled: title, in: axHost.view),
            "the control is gone at accessibility type; the player reads \(AccessibilityTree.labels(in: axHost.view))"
        ).accessibilityFrame
        let atAccessibilitySize = control.height
        let fitsOnOneLine = ActiveSessionView.textWidth(title, style: .body, size: .accessibility3, weight: nil) <= control.width

        print("=== Rep Today - \"\(title)\" is \(atDefault)pt tall at default type, "
              + "\(atAccessibilitySize)pt at accessibility3 ===")
        XCTAssertTrue(
            fitsOnOneLine || atAccessibilitySize > atDefault,
            "\"\(title)\" must fit its \(control.width)pt control on one line or the control must grow to wrap it, "
                + "never hold 60pt and clip it"
        )
        try render(
            try playerView(state).environment(\.dynamicTypeSize, .accessibility3),
            size: playerSize,
            fileName: "player-hold-idle-accessibility-type.png", story: Evidence.sessionTimer
        )
    }

    /// Closing the player mid-hold leaves **no** countdown on disk at all (US-O03), driven through the
    /// hold starting on its own (ADR-0010) and the real End session control on the hosted production
    /// player.
    ///
    /// This is the rule that finally closed a defect three narrower guards could not. Persisting the leg
    /// - as a live deadline, as a frozen remainder, or as a frozen remainder of zero - always ended the
    /// same way, because whatever is written gets restored and whatever is restored reaches zero moments
    /// after the screen reappears: the cue fires and a set is banked for work nobody did. Nothing about
    /// the countdown is written now, so the resume has nothing to finish. What *is* carried is the side,
    /// since a per-side set half done must not restart from side 1.
    func testClosingThePlayerMidHoldLeavesNoLegOnDisk() async throws {
        let store = InMemoryActiveSessionStore()
        let workout = try generate()
        // A *training* hold, which auto-starts like a bookend hold since ADR-0010.
        let index = try XCTUnwrap(
            firstTrainingHoldIndex(in: workout),
            "the generated session carries no training-block timed hold (bookend holds auto-start, US-CC05)"
        )
        // The session is already on disk, as a resumable one is in the app - the player is reopened on
        // it. Seeding matters here: starting and freezing a leg now writes nothing by design, so without
        // it the store would be empty for the uninteresting reason that nothing persisted at all.
        let state = resumed(workout, at: index, currentSet: 1)
        // Whatever the earlier slots of the session already banked. The property under test is that the
        // close adds *nothing* to it, so it is read off the snapshot rather than assumed to be zero -
        // which would only hold while the session's first timed movement happens to be its first slot.
        let bankedBefore = state.completedSets.values.reduce(0) { $0 + $1.count }
        try await store.save(state, for: "u1")

        let host = try hostedMidHold(
            ActiveSessionView(resuming: state, store: store, userId: "u1"),
            size: playerSize
        )
        XCTAssertTrue(
            AccessibilityTree.labels(in: host.view).contains { $0.hasPrefix("Hold, ") },
            "the leg should be running before it is walked away from"
        )

        let closeControl = try XCTUnwrap(
            AccessibilityTree.element(labeled: "End session", in: host.view),
            "the player offers no close control; it reads \(AccessibilityTree.labels(in: host.view))"
        )
        XCTAssertTrue(closeControl.accessibilityActivate(), "the close control did not activate")

        // Let any write the close queued settle before reading what the Resume card would find. The
        // pump sits behind a synchronous function because `RunLoop.run(mode:before:)` is unavailable
        // from an async context (an error under Swift 6), which is the same reason the accessibility
        // helpers this test already calls hold their own pumps.
        func settle() {
            for _ in 0..<10 {
                RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.1))
            }
        }
        settle()
        let saved = try await store.load(for: "u1")
        let snapshot = try XCTUnwrap(saved, "the resumable session vanished")
        print("=== Rep Today - closing mid-hold saved hold=\(String(describing: snapshot.hold)) ===")

        // A bilateral leg on side 1 has nothing to carry; a per-side one carries only the side.
        if let hold = snapshot.hold {
            XCTAssertGreaterThan(hold.side, 1, "the only hold worth persisting is a half-done per-side set")
        }

        // And that is what the Resume card hands back: no countdown, nothing recorded, ready to restart.
        let resumedPlayer = ActiveSessionViewModel(state: snapshot, now: { Date() })
        XCTAssertFalse(resumedPlayer.isHolding, "the resumed session restores no live countdown; its leg starts fresh")
        XCTAssertFalse(resumedPlayer.isHoldPaused)
        XCTAssertEqual(
            resumedPlayer.completedSetCount, bankedBefore,
            "and banks nothing the user did not do"
        )
    }

    /// The other half of US-O03, driven through the real control that ends the session: the clock the
    /// player never shows is the same clock the completion summary finally reports.
    ///
    /// The two halves are gated together on one hosted surface, because separately either could pass
    /// while the story fails - a player with no clock and a summary with no total is a session whose
    /// minutes simply vanished, and a summary reporting a total the player also displayed is the
    /// pressure the story removes. So the last set is banked through the production "Finish session"
    /// control, and the same accessibility tree is read on both sides of that tap: no elapsed clock
    /// before it, the session's minutes on the card after it.
    func testTheSessionTotalIsHiddenDuringPlayAndRevealedOnTheCompletionSummary() throws {
        let workout = try generate()
        let slots = workout.blocks.flatMap(\.exercises)
        let last = slots.count - 1

        // Parked on the final set of the session's last slot, with the session started a little over
        // eleven minutes ago - far enough inside the minute that the rounding cannot tip while the test
        // runs, so the number asserted is the number rendered.
        let workedMinutes = 11
        var state = resumed(workout, at: last, currentSet: slots[last].sets)
        state = ActiveSessionState(
            workout: state.workout, slots: state.slots, currentStepIndex: state.currentStepIndex,
            currentSet: state.currentSet, completedSets: state.completedSets,
            skippedStepIDs: state.skippedStepIDs,
            startedAt: Date().addingTimeInterval(-Double(workedMinutes) * 60 - 5), rest: nil
        )

        let host = hosted(try playerView(state), size: playerSize)
        let duringPlay = AccessibilityTree.labels(in: host.view)
        XCTAssertFalse(
            duringPlay.contains { $0.hasPrefix("Elapsed time") },
            "the session clock is on the player again; it reads \(duringPlay)"
        )
        XCTAssertFalse(
            duringPlay.contains { $0.contains("\(workedMinutes) minute") },
            "the minutes worked so far must not be readable mid-session; it reads \(duringPlay)"
        )

        let finish = try XCTUnwrap(
            AccessibilityTree.element(labeled: "Finish session", in: host.view),
            "the player offers no way to bank the session's last set; it reads \(duringPlay)"
        )
        XCTAssertTrue(finish.accessibilityActivate(), "the Finish session control did not activate")

        func celebrating(_ labels: [String]) -> Bool {
            labels.contains("You showed up. That's the whole game.")
        }
        let ceiling = Date().addingTimeInterval(20)
        var after: [String] = []
        repeat {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.1))
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
            after = AccessibilityTree.labels(in: host.view)
        } while Date() < ceiling && !celebrating(after)

        print("=== Rep Today - the completion summary reads: \(after) ===")
        XCTAssertTrue(celebrating(after), "the session never reached its summary; it reads \(after)")
        XCTAssertTrue(
            after.contains("\(workedMinutes) minutes"),
            "the summary should finally report the \(workedMinutes) minutes the session took; "
            + "it reads \(after)"
        )
        try renderHosted(
            host, size: playerSize,
            fileName: "completion-summary-total.png", story: Evidence.sessionTimer
        )
    }
}
