import XCTest
import SwiftUI
@testable import RepToday

/// End-to-end evidence for the prescription as the user meets it: the player *saying* "per side" on a
/// movement the engine charges both sides for, the in-session swap keeping the slot's own set count
/// unless moving it is what keeps the session inside the minutes the user asked for, and the spoken
/// form of that same target agreeing with its own counts on every slot of a real session.
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
            ?? "/var/folders/9t/k_yy9fqs5vd27rf12jx_rzqh0000gn/T/no-mistakes-evidence/01KYSP7F2TSE3ZKY9MYPCXDZVZ"
    }

    private let requestedMinutes = 30

    /// The window a hosted surface lives in while it is measured or captured.
    private var renderWindow: UIWindow?

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

    /// Hosts a production surface in a real key window and lets it settle, so what follows reads a
    /// laid-out, drawn view - whether that is its pixels or its accessibility tree.
    private func hosted<V: View>(_ view: V, size: CGSize) -> UIHostingController<V> {
        let host = UIHostingController(rootView: view)
        host.overrideUserInterfaceStyle = .dark
        host.view.frame = CGRect(origin: .zero, size: size)

        // A real key window makes the view actually lay out and draw its layers. It is held for the
        // lifetime of the test case, because a released window takes the hosted view down with it.
        let window = UIWindow(frame: host.view.frame)
        window.rootViewController = host
        window.makeKeyAndVisible()
        renderWindow = window
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()

        // Let SwiftUI finish its asynchronous layout/draw passes (including the view's own `.task`).
        let deadline = Date().addingTimeInterval(2.5)
        while Date() < deadline {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        return host
    }

    /// Renders a production surface to a PNG in the evidence directory.
    private func render<V: View>(_ view: V, size: CGSize, fileName: String) throws {
        let host = hosted(view, size: size)

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
        try render(
            ReadyView(services: try readyServices()),
            size: CGSize(width: 393, height: 1420),
            fileName: "ready-screen-per-side-rows.png"
        )
    }

    /// The container `ReadyView` is wired to - the same services the app's mock container uses.
    private func readyServices() throws -> ServiceContainer {
        let exerciseService = try MockExerciseService()
        let userService = MockUserService(user: steadyUser())
        let policyStore = InMemorySessionPolicyStore()
        let consistencyService = ConsistencyScoreService(now: { self.asOf }, calendar: self.calendar)
        let workoutLogService = MockWorkoutLogService(logs: history())
        return ServiceContainer(
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

        try write(transcript.joined(separator: "\n") + "\n", to: "voiceover-target-transcript.md")
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
        let host = hosted(ReadyView(services: try readyServices()), size: CGSize(width: 393, height: 1420))
        let labels = accessibilityLabels(in: host.view)

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
        try write(rows.map { "- \($0)" }.joined(separator: "\n") + "\n", to: "ready-screen-voiceover-labels.md")
    }

    /// The accessibility element carrying `label`, so a test can activate it exactly the way VoiceOver's
    /// double-tap does - driving the production control rather than reaching past it into the view model.
    private func accessibilityElement(labeled label: String, in root: UIView) -> NSObject? {
        _ = UIApplication.shared.accessibilityActivate()
        UIAccessibility.post(notification: .screenChanged, argument: nil)
        RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.5))

        var found: NSObject?
        var visited = Set<ObjectIdentifier>()

        func walk(_ node: NSObject) {
            guard found == nil, visited.insert(ObjectIdentifier(node)).inserted else { return }
            if node.isAccessibilityElement, node.accessibilityLabel == label {
                found = node
                return
            }
            let count = node.accessibilityElementCount()
            if count != NSNotFound {
                for index in 0..<count where found == nil {
                    if let child = node.accessibilityElement(at: index) as? NSObject { walk(child) }
                }
            }
            if let view = node as? UIView {
                for subview in view.subviews where found == nil { walk(subview) }
            }
        }

        walk(root)
        return found
    }

    /// Every accessibility label in a hosted hierarchy, in traversal order - the strings VoiceOver reads
    /// as the user swipes down the screen.
    ///
    /// SwiftUI only builds its accessibility tree once an assistive client is attached, so a test
    /// process has to ask for one first; without the activation below the hierarchy is empty and this
    /// would silently report that nothing on screen is spoken at all.
    private func accessibilityLabels(in root: UIView) -> [String] {
        _ = UIApplication.shared.accessibilityActivate()
        UIAccessibility.post(notification: .screenChanged, argument: nil)
        RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.5))

        var labels: [String] = []
        var visited = Set<ObjectIdentifier>()

        func walk(_ node: NSObject) {
            guard visited.insert(ObjectIdentifier(node)).inserted else { return }
            if node.isAccessibilityElement, let label = node.accessibilityLabel {
                labels.append(label)
            }
            let count = node.accessibilityElementCount()
            if count != NSNotFound {
                for index in 0..<count {
                    if let child = node.accessibilityElement(at: index) as? NSObject { walk(child) }
                }
            }
            if let view = node as? UIView {
                view.subviews.forEach(walk)
            }
        }

        walk(root)
        return labels
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
                fileName: fileName
            )
        }
    }

    // MARK: - Session timer redesign (US-O03)

    private var playerSize: CGSize { CGSize(width: 393, height: 852) }

    /// The same snapshot with a hold running - built through the production *restore* path, which is how
    /// the player can be rendered mid-countdown without reaching into its view model. The deadline is a
    /// real-time one because the hosted view reads it against `Date()`.
    private func holding(_ state: ActiveSessionState, seconds: Int, side: Int = 1) -> ActiveSessionState {
        var withHold = state
        withHold.hold = ActiveSessionState.Hold(
            totalSeconds: seconds,
            side: side,
            deadline: Date().addingTimeInterval(TimeInterval(seconds) * 0.7),
            remainingWhenPaused: nil,
            isRunning: true
        )
        return withHold
    }

    /// The player at a timed movement, idle then mid-hold, read off the live accessibility tree of the
    /// production surface (US-O03).
    ///
    /// Two things are gated together because they are the same change: a timed movement is now recorded
    /// by its own countdown rather than a "Complete set" tap, and the always-on elapsed clock that used
    /// to sit in the top bar is gone. The clock half is asserted on the tree rather than assumed from
    /// the source, so re-adding it - the regression this story exists to prevent - fails here.
    func testHoldTimerReplacesTheAlwaysOnSessionClock() throws {
        let workout = try generate()
        let slots = workout.blocks.flatMap(\.exercises)
        let holdIndex = try XCTUnwrap(
            slots.firstIndex { $0.exercise.isHold && ($0.durationSeconds ?? 0) > 0 },
            "the generated session carries no timed movement to hold"
        )
        let hold = slots[holdIndex]
        let sides = hold.exercise.sidesPerSet
        let seconds = try XCTUnwrap(hold.durationSeconds)
        print("=== Rep Today - the player at \(hold.exercise.id): \(seconds)s"
              + (sides > 1 ? " per side, two legs per set" : "") + " ===")

        // Idle: the Hold Timer is offered in place of the manual "Complete set".
        let idle = resumed(workout, at: holdIndex, currentSet: 1)
        let idleLabels = accessibilityLabels(in: hosted(try playerView(idle), size: playerSize).view)
        let expectedStart = sides > 1 ? "Start hold, side 1 of \(sides)" : "Start hold"
        XCTAssertTrue(
            idleLabels.contains(expectedStart),
            "the player should offer \"\(expectedStart)\"; it reads \(idleLabels)"
        )
        XCTAssertFalse(
            idleLabels.contains("Complete set"),
            "a timed movement is recorded by its countdown, not by a tap"
        )
        try render(try playerView(idle), size: playerSize, fileName: "player-hold-idle.png")

        // Running: the countdown takes the demo's place and speaks the seconds it has left.
        let running = holding(idle, seconds: seconds)
        let runningLabels = accessibilityLabels(in: hosted(try playerView(running), size: playerSize).view)
        XCTAssertTrue(
            runningLabels.contains { $0.hasPrefix("Hold, ") && $0.hasSuffix(" seconds remaining") },
            "a running hold should speak its remaining seconds; it reads \(runningLabels)"
        )
        XCTAssertTrue(runningLabels.contains("Stop hold"), "and offer the quiet way out of it")
        try render(try playerView(running), size: playerSize, fileName: "player-hold-running.png")

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

        let firstSide = resumed(workout, at: index, currentSet: 1)
        let firstLabels = accessibilityLabels(in: hosted(try playerView(firstSide), size: playerSize).view)
        XCTAssertTrue(
            firstLabels.contains("Start hold, side 1 of 2"),
            "the button should name the side it starts; it reads \(firstLabels)"
        )
        XCTAssertTrue(
            firstLabels.contains { $0.contains("side 1 of 2") && $0.hasPrefix("Set ") },
            "the set tracker should name the side the set is on; it reads \(firstLabels)"
        )
        XCTAssertTrue(
            firstLabels.contains("\(slot.exercise.displayName), \(ActiveSessionView.targetAccessibilityText(slot))"),
            "the spoken target still carries its per-side suffix; it reads \(firstLabels)"
        )
        try render(try playerView(firstSide), size: playerSize, fileName: "player-per-side-hold-side-1.png")

        // Parked between the legs - the state a relaunch restores to, so it must read as owing side 2.
        var secondSide = firstSide
        secondSide.hold = ActiveSessionState.Hold(
            totalSeconds: 0, side: 2, deadline: nil, remainingWhenPaused: nil, isRunning: false
        )
        let secondLabels = accessibilityLabels(in: hosted(try playerView(secondSide), size: playerSize).view)
        XCTAssertTrue(
            secondLabels.contains("Start hold, side 2 of 2"),
            "a restored between-legs hold owes side 2; it reads \(secondLabels)"
        )
        try render(try playerView(secondSide), size: playerSize, fileName: "player-per-side-hold-side-2.png")
    }

    /// The rest overlay lost its clock too (US-O03) - it kept the countdown that is *about* the rest and
    /// dropped the session total that was only ever pressure. Rendered beside the player for review.
    func testRestOverlayCarriesItsCountdownButNoSessionClock() throws {
        let workout = try generate()
        var state = resumed(workout, at: 1, currentSet: 1)
        state.rest = ActiveSessionState.Rest(
            totalSeconds: 45, deadline: Date().addingTimeInterval(28), remainingWhenPaused: nil
        )

        let labels = accessibilityLabels(in: hosted(try playerView(state), size: playerSize).view)

        XCTAssertTrue(
            labels.contains { $0.hasPrefix("Rest, ") && $0.hasSuffix(" seconds remaining") },
            "the rest keeps its own countdown; the overlay reads \(labels)"
        )
        XCTAssertFalse(
            labels.contains { $0.hasPrefix("Elapsed time") },
            "the always-on session clock is back on the rest overlay: \(labels)"
        )
        try render(try playerView(state), size: playerSize, fileName: "player-rest-overlay.png")
    }

    /// The Hold Timer driven the way a user drives it, in real time (US-O03).
    ///
    /// Everything else about the hold is asserted against an injected clock or a static render. This one
    /// hosts the production `ActiveSessionView`, taps its real "Start hold" control the way VoiceOver's
    /// double-tap does, and then lets the wall clock actually run out - so the `Timer` publisher, the
    /// deadline arithmetic, the auto-record and the hand-off to the rest overlay are all exercised as
    /// one live system rather than as pieces. The hold is authored short so the test does not have to
    /// wait out a real 30-second plank.
    func testHoldTimerRunsDownAndHandsOffToRestInTheLivePlayer() throws {
        let hold = Exercise(
            id: "evidence_short_hold", displayName: "Short Hold", pillar: .strength,
            movementPattern: .core, category: .strength, difficulty: 1, phase: .discipline,
            equipment: [], isHold: true, defaultReps: nil, defaultDurationSeconds: 2,
            estimatedTimePerSetSeconds: 10, metValue: 3, progressionChainId: "evidence_chain",
            progressionOrder: 0, regressionId: nil, progressionId: nil,
            advancementCriteria: "hold it", apartmentFriendly: true
        )
        let workout = Workout(
            id: UUID(), createdAt: asOf, shape: .blend, focusPillar: nil,
            requestedMinutes: 5, wasReturn: false,
            blocks: [
                WorkoutBlock(
                    id: UUID(), title: "Strength", category: .strength,
                    exercises: [
                        PrescribedExercise(id: UUID(), exercise: hold, sets: 1, reps: nil, durationSeconds: 2, restSeconds: 30),
                        PrescribedExercise(id: UUID(), exercise: hold, sets: 1, reps: nil, durationSeconds: 2, restSeconds: 30)
                    ]
                )
            ]
        )

        let host = hosted(ActiveSessionView(resuming: ActiveSessionState(fresh: workout)), size: playerSize)
        let start = try XCTUnwrap(
            accessibilityElement(labeled: "Start hold", in: host.view),
            "the live player offers no Start hold control; it reads \(accessibilityLabels(in: host.view))"
        )

        XCTAssertTrue(start.accessibilityActivate(), "the Start hold control did not activate")

        // Let the hold actually run out in wall-clock time, then let the view settle on what follows.
        let deadline = Date().addingTimeInterval(4)
        while Date() < deadline {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.1))
        }
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()

        let after = accessibilityLabels(in: host.view)
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

    /// Writes a text artifact next to the rendered PNGs.
    private func write(_ text: String, to fileName: String) throws {
        try? FileManager.default.createDirectory(atPath: evidenceDir, withIntermediateDirectories: true)
        let path = (evidenceDir as NSString).appendingPathComponent(fileName)
        try text.write(toFile: path, atomically: true, encoding: .utf8)
        print("TRANSCRIPT_WRITTEN \(path)")
    }
}
