import XCTest
import SwiftUI
@testable import RepToday

/// End-to-end evidence for the two user-facing halves of the per-side work model: the player *saying*
/// "per side" on a movement the engine charges both sides for, and the in-session swap keeping the
/// slot's own set count unless moving it is what keeps the session inside the minutes the user asked for.
///
/// Everything here runs the real pipeline over the real bundled `Exercises.json` - `SessionAssembly`
/// generates the session, `ExerciseSwap` (through `MockWorkoutEngine`, the same seam the app wires) does
/// the substitution, and `ActiveSessionViewModel` / `ActiveSessionView` / `ReadyView` are the production
/// surfaces - so the strings and the arithmetic asserted here are the ones a user actually gets. The
/// printed transcripts and rendered PNGs are the reviewable artifact; the assertions are what make them
/// a gate rather than a demo.
@MainActor
final class PerSideSwapEvidenceTests: XCTestCase {

    /// Where the rendered-UI evidence is written. Overridable so a later run can point it elsewhere
    /// without editing the test.
    private var evidenceDir: String {
        ProcessInfo.processInfo.environment["REPTODAY_EVIDENCE_DIR"]
            ?? "/var/folders/9t/k_yy9fqs5vd27rf12jx_rzqh0000gn/T/no-mistakes-evidence/01KYSJ41XYMX04HBJXG0WGJNEN"
    }

    private let requestedMinutes = 30

    // MARK: - Fixtures

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private var asOf: Date {
        calendar.date(from: DateComponents(year: 2026, month: 7, day: 30, hour: 12))!
    }

    private func date(daysAgo: Int) -> Date {
        calendar.date(byAdding: .day, value: -daysAgo, to: asOf)!
    }

    /// A steady-state, past-cold-start user with a learned 30-minute default - long enough that the
    /// lineup carries warm-up, strength, primal and cooldown blocks, so the per-side label and the
    /// swap's set lever are exercised across every slot shape rather than only the adjustable one.
    private func steadyUser() -> User {
        User(
            id: "evidence-user",
            displayName: "Riley",
            createdAt: date(daysAgo: 120),
            profile: UserProfile(
                age: 34, sex: .female, heightCm: 168.5, weightKg: 62.0,
                fitnessLevel: .intermediate, primaryGoal: .stayActive,
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

    /// A short history so Step 6 has demonstrated capacity to size targets against - including a
    /// per-side hold and a per-side rep movement, so their prescriptions are capacity-grown rather than
    /// sitting on the catalog default.
    private func history() -> [WorkoutLog] {
        struct Spec { let id: String, pillar: Pillar, pattern: MovementPattern; let reps: Int?, seconds: Int? }
        let specs: [Spec] = [
            Spec(id: "push_standard", pillar: .strength, pattern: .push, reps: 12, seconds: nil),
            Spec(id: "core_side_plank", pillar: .strength, pattern: .core, reps: nil, seconds: 35),
            Spec(id: "squat_split", pillar: .strength, pattern: .squat, reps: 10, seconds: nil),
            Spec(id: "mobility_cat_cow", pillar: .mobility, pattern: .mobility, reps: 10, seconds: nil),
        ]
        return (0..<8).map { offset in
            let spec = specs[offset % specs.count]
            let set = CompletedSet(reps: spec.reps, durationSeconds: spec.seconds)
            return WorkoutLog(
                id: UUID(), workoutId: UUID(), completedAt: date(daysAgo: offset * 2 + 1),
                requestedMinutes: requestedMinutes, durationMinutes: requestedMinutes - 1,
                wasReturn: false, shape: .blend, focusPillar: spec.pillar,
                perceivedDifficulty: .justRight,
                exercises: [
                    LoggedExercise(
                        id: UUID(), exerciseId: spec.id, pillar: spec.pillar,
                        movementPattern: spec.pattern, completedSets: [set, set, set], skipped: false
                    )
                ]
            )
        }
    }

    private func library() throws -> [Exercise] {
        let bundle = Bundle(for: AppState.self)
        let url = try XCTUnwrap(bundle.url(forResource: "Exercises", withExtension: "json"))
        return try JSONDecoder().decode([Exercise].self, from: Data(contentsOf: url))
    }

    /// The real Steps 1-7 pipeline at a fixed clock, so the transcripts below are reproducible.
    private func generate() throws -> Workout {
        SessionAssembly.assemble(
            requestedMinutes: requestedMinutes,
            user: steadyUser(),
            library: try library(),
            recentLogs: history(),
            sessionPolicy: .default,
            asOf: asOf,
            calendar: calendar
        )
    }

    private func player(_ workout: Workout, engine: any WorkoutEngineProtocol) -> ActiveSessionViewModel {
        ActiveSessionViewModel(
            workout: workout, swapEngine: engine, user: steadyUser(), recentLogs: history(),
            sessionPolicy: .default, now: { self.asOf }, feedback: SilentRestFeedback()
        )
    }

    private struct SilentRestFeedback: RestTimerFeedback {
        func restDidComplete() {}
    }

    /// The planned wall-clock of an arbitrary lineup, measured with the engine's own model.
    /// `plannedSeconds` flattens the blocks, so one carrier block is enough to measure a swapped lineup.
    private func plannedSeconds(of prescriptions: [PrescribedExercise], like workout: Workout) -> Int {
        SessionAssembly.plannedSeconds(
            of: Workout(
                id: workout.id, createdAt: workout.createdAt, shape: workout.shape,
                focusPillar: workout.focusPillar, requestedMinutes: workout.requestedMinutes,
                wasReturn: workout.wasReturn,
                blocks: [WorkoutBlock(id: UUID(), title: "Session", category: .strength, exercises: prescriptions)]
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
            abs(planned - requestedMinutes * 60), 60,
            "the session has to land within ±1 minute of the request"
        )
    }

    // MARK: - Swapping a per-side slot mid-session

    /// The end-user swap path: start the real player on a real session, walk to a per-side slot the way a
    /// user does (finishing sets), tap Swap, and print what changed. The substitute has to stay a
    /// same-pillar/pattern peer, carry its own honest per-side label, and leave the session inside the
    /// ±1 minute it promised.
    func testPlayerSwapAtAPerSideSlotKeepsCopyAndBudget() async throws {
        let workout = try generate()
        let viewModel = player(workout, engine: MockWorkoutEngine(exerciseService: try MockExerciseService()))
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
        XCTAssertLessThanOrEqual(
            abs(plannedAfter - requestedMinutes * 60), 60,
            "the swap left the session outside the ±1 minute it promised"
        )
    }

    /// Swapping every slot of a real session in turn - not just the one the walk happens to land on - so
    /// the "keep the slot's set count, re-pick only to hold the budget" rule is exercised in the
    /// non-adjustable warm-up/cooldown shapes as well as the adjustable training blocks. One printed line
    /// per slot is the reviewable sweep.
    func testSwappingEverySlotKeepsBudgetAndRespectsTheSetLever() async throws {
        let workout = try generate()
        let engine = MockWorkoutEngine(exerciseService: try MockExerciseService())
        let slotCount = workout.blocks.reduce(0) { $0 + $1.exercises.count }

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
                  + (moved ? "re-picked" : "kept") + " · planned \(planned)s")

            XCTAssertEqual(after.prescription.exercise.pillar, before.prescription.exercise.pillar)
            XCTAssertEqual(after.prescription.exercise.movementPattern, before.prescription.exercise.movementPattern)
            XCTAssertTrue(after.prescription.exercise.equipment.isEmpty, "Zero-Equipment Floor")
            XCTAssertLessThanOrEqual(
                abs(planned - requestedMinutes * 60), 60,
                "swapping slot \(index + 1) (\(before.prescription.exercise.id) -> "
                + "\(after.prescription.exercise.id)) left the session at \(planned)s, outside ±1 minute"
            )
            // Warm-up and cooldown slots are 1 set with set adjustment disabled, so their set count can
            // never move; only the adjustable training blocks may re-pick.
            if before.prescription.sets == 1 {
                XCTAssertEqual(after.prescription.sets, 1, "a 1-set slot has no set lever to pull")
            }
        }
        print("swept \(slotCount) slots: \(substituted) substituted (\(rePicked) with a re-picked set count), "
              + "\(noAlternative) with no alternative")
        XCTAssertGreaterThan(substituted, 0)
    }

    // MARK: - Rendered-UI evidence

    /// Renders a production surface to a PNG in the evidence directory.
    private func render<V: View>(_ view: V, size: CGSize, fileName: String) throws {
        let host = UIHostingController(rootView: view)
        host.overrideUserInterfaceStyle = .dark
        host.view.frame = CGRect(origin: .zero, size: size)

        // A real key window makes the view actually lay out and draw its layers.
        let window = UIWindow(frame: host.view.frame)
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()

        // Let SwiftUI finish its asynchronous layout/draw passes (including the view's own `.task`).
        let deadline = Date().addingTimeInterval(2.5)
        while Date() < deadline {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()

        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let image = renderer.image { ctx in host.view.layer.render(in: ctx.cgContext) }
        let data = try XCTUnwrap(image.pngData())

        try? FileManager.default.createDirectory(atPath: evidenceDir, withIntermediateDirectories: true)
        let path = (evidenceDir as NSString).appendingPathComponent(fileName)
        try data.write(to: URL(fileURLWithPath: path))
        XCTAssertGreaterThan(data.count, 8000, "rendered PNG unexpectedly small - the surface may not have drawn")
        print("SNAPSHOT_WRITTEN \(path) bytes=\(data.count)")
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
            workoutEngine: MockWorkoutEngine(exerciseService: try MockExerciseService()),
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
            fileName: "player-per-side-hold.png"
        )
        try render(
            try playerView(state).environment(\.dynamicTypeSize, .accessibility3),
            size: CGSize(width: 393, height: 852),
            fileName: "player-per-side-hold-accessibility-type.png"
        )
    }

    /// The player on a per-side *rep* movement, where the suffix lands on a count rather than a clock.
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
            fileName: "player-per-side-reps.png"
        )
    }

    /// The swap as the user sees it: the player before the tap and after it, both rendered from the real
    /// view model's own snapshot - so the "after" frame is the state the swap actually produced (peer in
    /// place, its own per-side label, the slot's set count, set counter back to 1), not a hand-built one.
    func testRenderPlayerBeforeAndAfterSwappingAPerSideSlot() async throws {
        let workout = try generate()
        let viewModel = player(workout, engine: MockWorkoutEngine(exerciseService: try MockExerciseService()))
        viewModel.start()
        var guardRail = 0
        while let step = viewModel.currentStep, guardRail < 200,
              !(step.prescription.exercise.sidesPerSet > 1 && step.prescription.exercise.isHold) {
            viewModel.completeSet()
            guardRail += 1
        }
        let before = try XCTUnwrap(viewModel.currentStep)
        try render(
            try playerView(renderable(viewModel.snapshot())),
            size: CGSize(width: 393, height: 852),
            fileName: "player-swap-before.png"
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
            fileName: "player-swap-after.png"
        )
    }

    /// The Ready Screen the user reads *before* starting: the whole lineup with its targets, so the
    /// "per side" rows can be reviewed where they are first seen. Wired to the same services the app's
    /// mock container uses, with a user whose learned default is the 30 minutes the transcripts use.
    func testRenderReadyScreenWithPerSideRows() throws {
        let exerciseService = try MockExerciseService()
        let userService = MockUserService(user: steadyUser())
        let policyStore = InMemorySessionPolicyStore()
        let consistencyService = ConsistencyScoreService(now: { self.asOf }, calendar: self.calendar)
        let workoutLogService = MockWorkoutLogService(logs: history())
        let services = ServiceContainer(
            exerciseService: exerciseService,
            workoutEngine: MockWorkoutEngine(exerciseService: exerciseService),
            sessionPolicyService: DeterministicSessionPolicyService(
                store: policyStore, exerciseService: exerciseService, userService: userService
            ),
            consistencyService: consistencyService,
            phaseService: PhaseEvaluatorService(exerciseService: exerciseService),
            userService: userService,
            workoutLogService: workoutLogService,
            activeSessionStore: InMemoryActiveSessionStore(),
            sessionCompletionService: SessionCompletionService(
                workoutLogService: workoutLogService, userService: userService,
                consistencyService: consistencyService, policyStore: policyStore
            ),
            healthKitService: MockHealthKitService(),
            subscriptionService: MockSubscriptionService(),
            authService: MockAuthService()
        )

        try render(
            ReadyView(services: services),
            size: CGSize(width: 393, height: 1420),
            fileName: "ready-screen-per-side-rows.png"
        )
    }
}
