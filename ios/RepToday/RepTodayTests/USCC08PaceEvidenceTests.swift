import SwiftUI
import UIKit
import XCTest
@testable import RepToday

/// Reviewer-facing evidence for US-CC08 (generous runtime pace): a render of the production player
/// with its auto-advancing work window up on a real assembled session, plus a transcript that puts the
/// engine's planned per-set seconds and the player's on-screen window side by side for every step, the
/// catalog's per-rep cadence, and the fit across every session length.
///
/// Deliberately references no US-CC08-only symbol, so the same suite can be run against the pre-change
/// engine to produce the "before" half of the comparison.
@MainActor
final class USCC08PaceEvidenceTests: XCTestCase {

    private var renderWindow: UIWindow?
    private let story = "us-cc08"

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private var asOf: Date { calendar.date(from: DateComponents(year: 2026, month: 7, day: 30, hour: 12))! }

    private func date(daysAgo: Int) -> Date { calendar.date(byAdding: .day, value: -daysAgo, to: asOf)! }

    private func user(minutes: Int, level: FitnessLevel = .intermediate) -> User {
        User(
            id: "evidence-user",
            displayName: "Riley",
            createdAt: date(daysAgo: 120),
            profile: UserProfile(
                age: 34, sex: .female, heightCm: 168.5, weightKg: 62.0,
                fitnessLevel: level, primaryGoal: .stayActive,
                sitsLong: false, injuries: [], typicalAvailableMinutes: minutes
            ),
            phase: .discipline,
            subscription: .free,
            consistency: Consistency(
                weeklyGoal: 3, score: 78.0, workoutsThisWeek: 2,
                longestChain: 6, totalWorkoutsCompleted: 38, totalMinutesExercised: 540
            ),
            duration: User.Duration(
                defaultMinutes: minutes, onboardingSeedMinutes: minutes,
                completedDurationEWMA: Double(minutes)
            ),
            coldStart: User.ColdStart(sessionsLogged: 12, active: false)
        )
    }

    private func library() throws -> [Exercise] {
        let bundle = Bundle(for: AppState.self)
        let url = try XCTUnwrap(bundle.url(forResource: "Exercises", withExtension: "json"))
        return try JSONDecoder().decode([Exercise].self, from: Data(contentsOf: url))
    }

    private func assemble(minutes: Int, level: FitnessLevel = .intermediate) throws -> Workout {
        SessionAssembly.assemble(
            requestedMinutes: minutes,
            user: user(minutes: minutes, level: level),
            library: try library(),
            recentLogs: [],
            asOf: asOf,
            calendar: calendar
        )
    }

    private func clock(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, abs(seconds) % 60)
    }

    /// A fixed-width table row (`String(format:)`'s `%-12@` does not pad an `NSString`).
    private func row(_ cells: [(String, Int)]) -> String {
        "    " + cells.map { text, width in
            text.count >= width ? text : text + String(repeating: " ", count: width - text.count)
        }.joined(separator: " ")
    }

    /// The seconds the model charges for one extra rep, measured as the marginal cost of ten more reps
    /// so the fixed per-set setup drops out and the rounding is amortised. This is the "cadence" the
    /// calibration is argued from, and it is measured the same way before and after the change.
    private func secondsPerRep(_ movement: Exercise) -> Double? {
        guard !movement.isHold, let baseline = movement.defaultReps, baseline > 0 else { return nil }
        let atBaseline = SessionAssembly.workSecondsPerSet(for: movement, reps: baseline, durationSeconds: nil)
        let atTen = SessionAssembly.workSecondsPerSet(for: movement, reps: baseline + 10, durationSeconds: nil)
        return Double(atTen - atBaseline) / 10.0
    }

    // MARK: - The screen the user actually sees

    /// The production player, hosted, with the work window running on the first auto-advancing set of a
    /// real assembled 20-minute session - so the countdown a reviewer sees on screen *is* the number the
    /// timing fit budgeted that set at.
    func testRenderPlayerWithTheWorkWindowRunning() throws {
        let workout = try assemble(minutes: 20)
        let slots = workout.blocks.flatMap(\.exercises)
        // The first position the player opens on an auto-advancing work window, found by asking the
        // production view model about each position rather than re-deriving its rule here.
        let index = try XCTUnwrap(
            (0..<slots.count).first { position in
                ActiveSessionViewModel(state: resumed(workout, at: position), now: { self.asOf })
                    .currentStepAutoAdvances
            },
            "no auto-advancing set in a 20-minute session"
        )
        let probe = ActiveSessionViewModel(state: resumed(workout, at: index), now: { self.asOf })
        let step = try XCTUnwrap(probe.currentStep)

        let planned = SessionAssembly.workSecondsPerSet(of: step.prescription)
        let state = resumed(workout, at: index)
        let host = hosted(ActiveSessionView(resuming: state), size: CGSize(width: 393, height: 852))
        let labels = AccessibilityTree.labels(in: host.view)
        let window = try XCTUnwrap(
            labels.first { $0.hasPrefix("Work window, ") },
            "the player is not showing a work window; it reads \(labels)"
        )

        print("EVIDENCE work-window step=\(step.prescription.exercise.id) "
              + "target=\"\(ActiveSessionView.targetText(step.prescription))\" "
              + "plannedWorkSeconds=\(planned) onScreen=\"\(window)\"")

        let image = HostedSurface.capture(host.view, size: CGSize(width: 393, height: 852))
        try EvidenceOutput.write(image, named: "player-work-window-running.png", for: story)
    }

    /// The report a reviewer reads beside the render.
    func testWritePaceReport() throws {
        let library = try library()
        var lines: [String] = []
        lines.append("US-CC08 - generous runtime pace: screen window == planned work-seconds")
        lines.append("")

        // 1. The screen window vs. the plan, step by step, on a real assembled 20-minute session.
        let workout = try assemble(minutes: 20)
        lines.append("[1] A real 20-minute session, walked step by step in the production player.")
        lines.append("    (\"window\" is ActiveSessionViewModel.workWindowSecondsPerSet - what counts down on screen;")
        lines.append("     \"planned\" is SessionAssembly.workSecondsPerSet - what the timing fit budgeted.)")
        lines.append("")
        lines.append(row([("BLOCK", 10), ("EXERCISE", 24), ("TARGET", 18),
                          ("PLANNED", 8), ("WINDOW", 12), ("MATCH", 5)]))
        let vm = ActiveSessionViewModel(workout: workout, now: { self.asOf })
        vm.start()
        var guardRail = 0
        var seenSteps = Set<UUID>()
        var mismatches = 0
        while !vm.isComplete, guardRail < 500 {
            guardRail += 1
            if let step = vm.currentStep, !seenSteps.contains(step.id) {
                seenSteps.insert(step.id)
                let planned = SessionAssembly.workSecondsPerSet(of: step.prescription)
                let window = vm.currentStepAutoAdvances ? vm.workWindowSecondsPerSet : nil
                let matches = window == nil || window == planned
                if !matches { mismatches += 1 }
                lines.append(row([
                    (step.blockTitle, 10),
                    (step.prescription.exercise.id, 24),
                    (ActiveSessionView.targetText(step.prescription), 18),
                    ("\(planned)s", 8),
                    (window.map { "\($0)s" } ?? "- (manual)", 12),
                    (window == nil ? "n/a" : (matches ? "yes" : "NO"), 5),
                ]))
            }
            if vm.isRunningWorkWindow {
                vm.finishWorkWindowEarly()
            } else if vm.isHolding {
                vm.cancelHold()
                vm.completeSet()
            } else if vm.isResting {
                vm.skipRest()
            } else {
                vm.completeSet()
            }
        }
        XCTAssertEqual(mismatches, 0, "a step's on-screen window disagreed with the engine's planned seconds")
        lines.append("")

        // 2. The calibration, read off the catalog's own fundamentals.
        lines.append("[2] Per-set seconds at each movement's default target (catalog fundamentals).")
        lines.append("    A rep-based set is priced above the authored typical-case estimate; a hold is not,")
        lines.append("    because its per-second cost is definitional (prescribed seconds are elapsed seconds).")
        lines.append("")
        lines.append(row([("MOVEMENT", 22), ("KIND", 5), ("AUTHORED", 9),
                          ("PRICED", 8), ("S/REP", 7), ("RATIO", 6)]))
        let showcase = ["hinge_glute_bridge", "push_wall", "squat_bodyweight", "squat_sumo",
                        "push_incline", "hinge_good_morning", "push_standard", "core_plank",
                        "core_side_plank", "mobility_cat_cow", "mobility_ankle_rocks"]
        var repRatios: [Double] = []
        var holdRatios: [Double] = []
        var cadences: [Double] = []
        for movement in library {
            guard let baseline = movement.isHold ? movement.defaultDurationSeconds : movement.defaultReps,
                  baseline > 0 else { continue }
            let priced = SessionAssembly.workSecondsPerSet(
                for: movement,
                reps: movement.isHold ? nil : baseline,
                durationSeconds: movement.isHold ? baseline : nil
            )
            let ratio = Double(priced) / Double(movement.estimatedTimePerSetSeconds)
            if movement.isHold { holdRatios.append(ratio) } else { repRatios.append(ratio) }
            let cadence = secondsPerRep(movement)
            if let cadence { cadences.append(cadence) }
            guard showcase.contains(movement.id) else { continue }
            lines.append(row([
                (movement.id, 22),
                (movement.isHold ? "hold" : "reps", 5),
                ("\(movement.estimatedTimePerSetSeconds)s", 9),
                ("\(priced)s", 8),
                (cadence.map { String(format: "%.2f", $0) } ?? "-", 7),
                (String(format: "x%.2f", ratio), 6),
            ]))
        }
        lines.append("")
        lines.append(String(format: "    rep-based movements (%d): ratio %.2f-%.2f, cadence %.2f-%.2f s/rep"
                            + " | holds (%d): ratio %.2f-%.2f",
                            repRatios.count, repRatios.min() ?? 0, repRatios.max() ?? 0,
                            cadences.min() ?? 0, cadences.max() ?? 0,
                            holdRatios.count, holdRatios.min() ?? 0, holdRatios.max() ?? 0))
        lines.append("")

        // 3. The accepted trade-off, measured: the fit still lands, at fewer rounds.
        lines.append("[3] The fit across every length (intermediate), after pacing every rep-based set.")
        lines.append("    tolerance = +/-\(SessionAssembly.toleranceSeconds)s")
        lines.append("")
        lines.append(row([("REQUEST", 8), ("PLANNED", 8), ("ERROR", 6),
                          ("TRAINING BLOCKS (rounds x stations)", 0)]))
        for minutes in [5, 10, 15, 20, 30, 45, 60] {
            let session = try assemble(minutes: minutes)
            let planned = SessionAssembly.plannedSeconds(of: session)
            let error = planned - minutes * 60
            let blocks = session.blocks
                .filter { SessionAssembly.isCircuit($0.category) }
                .map { "\($0.title) \($0.exercises.first?.sets ?? 0) x \($0.exercises.count)" }
                .joined(separator: ", ")
            XCTAssertLessThanOrEqual(abs(error), SessionAssembly.toleranceSeconds)
            lines.append(row([
                ("\(minutes) min", 8), (clock(planned), 8),
                ("\(error >= 0 ? "+" : "")\(error)s", 6), (blocks, 0),
            ]))
        }

        // 4. The knock-on the recalibration made visible: a desk worker's bookends now cost more, and
        //    that - not any change to the training middle - is what moves a round.
        lines.append("")
        lines.append("[4] The US-M03 desk-worker (sitsLong) bookend bias at 45 minutes, after pacing.")
        lines.append("    The bias reorders the bookend pools only; the training middle must hold the same")
        lines.append("    movements at the same per-set targets, with bookend seconds as the only channel.")
        lines.append("")
        for sitsLong in [false, true] {
            let session = SessionAssembly.assemble(
                requestedMinutes: 45,
                user: {
                    var person = user(minutes: 45)
                    person.profile.sitsLong = sitsLong
                    return person
                }(),
                library: library, recentLogs: [], asOf: asOf, calendar: calendar
            )
            let bookends = session.blocks.filter { !SessionAssembly.isCircuit($0.category) }
            let bookendSeconds = bookends.reduce(0) { total, block in
                total + block.exercises.reduce(0) {
                    $0 + $1.sets * SessionAssembly.workSecondsPerSet(of: $1)
                }
            }
            let training = session.blocks.filter { SessionAssembly.isCircuit($0.category) }
            lines.append("    sitsLong = \(sitsLong ? "true " : "false"):")
            lines.append(row([("      bookends", 16),
                              (bookends.flatMap { $0.exercises.map(\.exercise.id) }.joined(separator: ", "), 0)]))
            lines.append(row([("      cost", 16), ("\(bookendSeconds)s of work", 0)]))
            for block in training {
                lines.append(row([
                    ("      \(block.title)", 16),
                    ("\(block.exercises.first?.sets ?? 0) rounds x \(block.exercises.count) stations: "
                     + block.exercises.map { "\($0.exercise.id) \(ActiveSessionView.targetText($0))" }
                         .joined(separator: ", "), 0),
                ]))
            }
        }

        let report = lines.joined(separator: "\n") + "\n"
        print(report)
        try EvidenceOutput.write(report, named: "pace-report.txt", for: story)
    }

    // MARK: - Helpers

    private func resumed(_ workout: Workout, at index: Int) -> ActiveSessionState {
        let fresh = ActiveSessionState(fresh: workout)
        var completed: [UUID: [CompletedSet]] = [:]
        for slot in fresh.slots.prefix(index) {
            completed[slot.prescription.id] = (0..<slot.prescription.sets).map { _ in
                CompletedSet(reps: slot.prescription.reps, durationSeconds: slot.prescription.durationSeconds)
            }
        }
        return ActiveSessionState(
            workout: workout, slots: fresh.slots, currentStepIndex: index, currentSet: 1,
            completedSets: completed, skippedStepIDs: [],
            startedAt: Date().addingTimeInterval(-6 * 60 - 40), rest: nil
        )
    }

    private func hosted<V: View>(_ view: V, size: CGSize) -> UIHostingController<V> {
        let (host, window) = HostedSurface.host(view, size: size)
        renderWindow = window
        return host
    }
}
