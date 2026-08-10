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
            fileName: "player-per-side-hold.png", story: Evidence.perSideSwap
        )
        try render(
            try playerView(state).environment(\.dynamicTypeSize, .accessibility3),
            size: CGSize(width: 393, height: 852),
            fileName: "player-per-side-hold-accessibility-type.png", story: Evidence.perSideSwap
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
            fileName: "player-per-side-reps.png", story: Evidence.perSideSwap
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
            ReadyView(services: try readyServices()),
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
            workoutEngine: MockWorkoutEngine(exerciseService: exerciseService, now: { self.asOf }),
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
                consistencyService: consistencyService, policyStore: policyStore
            ),
            healthKitService: MockHealthKitService(),
            subscriptionService: MockSubscriptionService(),
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
        let host = hosted(ReadyView(services: try readyServices()), size: CGSize(width: 393, height: 1420))
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

    /// A hosted player with its hold actually running, for rendering and reading mid-countdown.
    ///
    /// The leg is started by activating the real "Start hold" control, the way VoiceOver's double-tap
    /// does, because a running leg is deliberately unreachable any other way: a hold is never persisted
    /// (US-O03), so there is no snapshot that restores one. That is the point of the rule, and it means
    /// the only honest way to see this state is the one the user takes to reach it.
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
        let start = try XCTUnwrap(
            AccessibilityTree.element(labeled: "Start hold", in: host.view)
                ?? AccessibilityTree.element(labeled: "Start hold, side 1 of 2", in: host.view),
            "the player offers no Start hold control; it reads \(AccessibilityTree.labels(in: host.view))"
        )
        XCTAssertTrue(start.accessibilityActivate(), "the Start hold control did not activate")

        func pump(until end: Date) {
            RunLoop.main.run(mode: .default, before: end)
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
        }

        guard let settlingSeconds else {
            pump(until: Date().addingTimeInterval(0.6))
            return host
        }

        let target = "Hold, \(settlingSeconds) seconds remaining"
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
        let holdIndex = try XCTUnwrap(
            slots.firstIndex { $0.exercise.isHold && ($0.durationSeconds ?? 0) > 0 },
            "the generated session carries no timed movement to hold"
        )
        let hold = slots[holdIndex]
        let sides = hold.exercise.sidesPerSet
        let seconds = try XCTUnwrap(hold.durationSeconds)
        print("=== Rep Today - the player at \(hold.exercise.id): \(seconds)s"
              + (sides > 1 ? " per side, two legs per set" : "") + " ===")

        // Idle: the Hold Timer leads, with the manual completion kept as a quiet secondary.
        let idle = resumed(workout, at: holdIndex, currentSet: 1)
        let idleLabels = AccessibilityTree.labels(in: hosted(try playerView(idle), size: playerSize).view)
        let expectedStart = sides > 1 ? "Start hold, side 1 of \(sides)" : "Start hold"
        let manualTitle = hold.sets > 1
            ? "Complete set"
            : (holdIndex == slots.count - 1 ? "Finish session" : "Finish exercise")
        XCTAssertTrue(
            idleLabels.contains(expectedStart),
            "the player should offer \"\(expectedStart)\"; it reads \(idleLabels)"
        )
        XCTAssertTrue(
            idleLabels.contains(manualTitle),
            "an idle hold should still offer \"\(manualTitle)\" as the way to bank a set held off-timer; "
            + "it reads \(idleLabels)"
        )
        try render(try playerView(idle), size: playerSize, fileName: "player-hold-idle.png", story: Evidence.sessionTimer)

        // Running: the countdown takes the demo's place and speaks the seconds it has left. The leg is
        // started through the real control, since a hold is never persisted and so cannot be restored
        // into this state (US-O03).
        let runningHost = try hostedMidHold(try playerView(idle), size: playerSize, settlingAt: seconds - 1)
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
        let firstLabels = AccessibilityTree.labels(in: hosted(try playerView(firstSide), size: playerSize).view)
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
        try render(try playerView(firstSide), size: playerSize, fileName: "player-per-side-hold-side-1.png", story: Evidence.sessionTimer)

        // Parked between the legs - the state a relaunch restores to, so it must read as owing side 2.
        var secondSide = firstSide
        secondSide.hold = ActiveSessionState.Hold(side: 2)
        let secondLabels = AccessibilityTree.labels(in: hosted(try playerView(secondSide), size: playerSize).view)
        XCTAssertTrue(
            secondLabels.contains("Start hold, side 2 of 2"),
            "a restored between-legs hold owes side 2; it reads \(secondLabels)"
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
    /// hosts the production `ActiveSessionView`, taps its real "Start hold" control the way VoiceOver's
    /// double-tap does, and then lets the wall clock actually run out - so the `Timer` publisher, the
    /// deadline arithmetic, the auto-record and the hand-off to the rest overlay are all exercised as
    /// one live system rather than as pieces. The hold is authored short so the test does not have to
    /// wait out a real 30-second plank.
    func testHoldTimerRunsDownAndHandsOffToRestInTheLivePlayer() throws {
        let workout = shortHoldWorkout(seconds: 2, sets: 1)

        let host = hosted(ActiveSessionView(resuming: ActiveSessionState(fresh: workout)), size: playerSize)
        let start = try XCTUnwrap(
            AccessibilityTree.element(labeled: "Start hold", in: host.view),
            "the live player offers no Start hold control; it reads \(AccessibilityTree.labels(in: host.view))"
        )

        XCTAssertTrue(start.accessibilityActivate(), "the Start hold control did not activate")

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

    /// Banking the set by hand *while* a leg runs, driven through the real controls on the hosted
    /// production player (US-O03).
    ///
    /// This is the non-destructive way out of a running hold, and it has to be reachable in one tap from
    /// the running state: the alternatives are "Stop hold", which records nothing, and "Skip", which
    /// discards every set already banked for the exercise. The leg is started and then banked through
    /// the accessibility tree the way VoiceOver's double-tap does, so what is gated is the control a
    /// user can actually reach mid-plank rather than a view-model call.
    func testBankingASetByHandMidLegEndsTheLegAndOpensTheRestInTheLivePlayer() throws {
        // Long enough that the leg is unambiguously still running when the set is banked by hand.
        let workout = shortHoldWorkout(seconds: 120, sets: 2)

        let host = hosted(ActiveSessionView(resuming: ActiveSessionState(fresh: workout)), size: playerSize)
        let start = try XCTUnwrap(
            AccessibilityTree.element(labeled: "Start hold", in: host.view),
            "the live player offers no Start hold control; it reads \(AccessibilityTree.labels(in: host.view))"
        )
        XCTAssertTrue(start.accessibilityActivate(), "the Start hold control did not activate")
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
            after.contains { $0.contains("set 2 of 2") },
            "with the set counter advanced exactly one set, as it is when the timer runs out; "
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

    /// The secondary row at an accessibility Dynamic Type size (US-O03).
    ///
    /// A timed movement carries three columns - Swap, the manual completion, Skip - across a 393pt row,
    /// and the manual one carries the longest title in it ("Finish exercise"), which is the part that
    /// says what the tap actually does. At the largest type sizes that title needs more than one line,
    /// so the control grows and takes the row with it rather than pinning itself to the 60pt touch
    /// target and clipping the title away. Measured off the live accessibility tree at both sizes,
    /// because a render alone cannot tell a grown row from a clipped one.
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
        let atAccessibilitySize = try XCTUnwrap(
            AccessibilityTree.element(labeled: title, in: axHost.view),
            "the control is gone at accessibility type; the player reads \(AccessibilityTree.labels(in: axHost.view))"
        ).accessibilityFrame.height

        print("=== Rep Today - \"\(title)\" is \(atDefault)pt tall at default type, "
              + "\(atAccessibilitySize)pt at accessibility3 ===")
        XCTAssertGreaterThan(
            atAccessibilitySize, atDefault,
            "the row should grow to fit \"\(title)\" at accessibility type rather than hold 60pt and clip it"
        )
        try render(
            try playerView(state).environment(\.dynamicTypeSize, .accessibility3),
            size: playerSize,
            fileName: "player-hold-idle-accessibility-type.png", story: Evidence.sessionTimer
        )
    }

    /// Closing the player mid-hold leaves **no** countdown on disk at all (US-O03), driven through the
    /// real Start hold and End session controls on the hosted production player.
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
        let slots = workout.blocks.flatMap(\.exercises)
        let index = try XCTUnwrap(
            slots.indices.first { slots[$0].exercise.isHold && (slots[$0].durationSeconds ?? 0) > 0 },
            "the generated session carries no timed movement to hold"
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
        XCTAssertFalse(resumedPlayer.isHolding, "the resumed session offers Start hold, not a live countdown")
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
