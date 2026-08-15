import XCTest
import SwiftUI
@testable import RepToday

/// Reviewer-visible evidence for US-CC05: a warm-up / cooldown **bookend** stretch hold auto-starts
/// hands-free (no "Start hold" tap), and a per-side bookend flows side 1 -> a brief "Switch sides"
/// beat -> side 2 with no tap.
///
/// This drives the *production* `ActiveSessionView` in a real key window and lets its own real-time
/// tickers advance the flow (the same `Timer.publish` that runs in the app), then captures the three
/// load-bearing frames to PNGs. It is the visual companion to the deterministic in-process state-machine
/// tests in `ActiveSessionViewModelTests` (US-CC05 section): those pin the timing under an injected
/// clock; this shows a reviewer the actual pixels a user would see, and asserts the hard hands-free
/// invariant on the live accessibility tree - no "Start hold" control is ever present on a bookend.
///
/// The hold duration is deliberately short so the real-time flow completes quickly; the mechanic is
/// identical at any duration.
@MainActor
final class HandsFreeBookendEvidenceTests: XCTestCase {

    private var window: UIWindow?

    private let story = "us-cc05"
    private let playerSize = CGSize(width: 393, height: 852)

    override func tearDown() {
        window = nil
        super.tearDown()
    }

    /// A single per-side warm-up stretch hold, then a strength set so the stretch has somewhere to
    /// advance to. `.warmup` block category is what makes it a *bookend* hold (auto-start), the exact
    /// complement of the strength/primal work-window gate.
    private func perSideWarmupBookendWorkout(seconds: Int) -> Workout {
        let stretch = Exercise(
            id: "kneeling_hip_flexor_stretch",
            displayName: "Kneeling Hip Flexor Stretch",
            pillar: .mobility,
            movementPattern: .hinge,
            category: .strength, // exercise-level; the *block* category (.warmup) is what gates the bookend
            difficulty: 1,
            phase: .discipline,
            equipment: [],
            isHold: true,
            defaultReps: nil,
            defaultDurationSeconds: seconds,
            estimatedTimePerSetSeconds: seconds + 10,
            metValue: 3,
            progressionChainId: "kneeling_hip_flexor_stretch_chain",
            progressionOrder: 0,
            regressionId: nil,
            progressionId: nil,
            advancementCriteria: "",
            apartmentFriendly: true
        )
        var perSideStretch = stretch
        perSideStretch.isPerSide = true

        let pushUp = Exercise(
            id: "push_up",
            displayName: "Push-up",
            pillar: .strength,
            movementPattern: .push,
            category: .strength,
            difficulty: 2,
            phase: .discipline,
            equipment: [],
            isHold: false,
            defaultReps: 10,
            defaultDurationSeconds: nil,
            estimatedTimePerSetSeconds: 40,
            metValue: 4,
            progressionChainId: "push_up_chain",
            progressionOrder: 0,
            regressionId: nil,
            progressionId: nil,
            advancementCriteria: "",
            apartmentFriendly: true
        )

        let warmup = WorkoutBlock(
            id: UUID(), title: "Warm-up", category: .warmup,
            exercises: [
                PrescribedExercise(
                    id: UUID(), exercise: perSideStretch,
                    sets: 1, reps: nil, durationSeconds: seconds, restSeconds: 15
                )
            ]
        )
        let strength = WorkoutBlock(
            id: UUID(), title: "Strength", category: .strength,
            exercises: [
                PrescribedExercise(
                    id: UUID(), exercise: pushUp, sets: 1, reps: 10, durationSeconds: nil, restSeconds: 30
                )
            ]
        )
        return Workout(
            id: UUID(), createdAt: Date(), shape: .blend, focusPillar: nil,
            requestedMinutes: 20, wasReturn: false, blocks: [warmup, strength]
        )
    }

    private func labels() -> [String] {
        guard let root = window?.rootViewController?.view else { return [] }
        return AccessibilityTree.labels(in: root)
    }

    /// Pumps the real run loop (so the production tickers fire) until `predicate` holds or `timeout`
    /// elapses. Returns whether it held.
    @discardableResult
    private func pump(until predicate: () -> Bool, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if predicate() { return true }
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.05))
            window?.rootViewController?.view.setNeedsLayout()
            window?.rootViewController?.view.layoutIfNeeded()
        }
        return predicate()
    }

    private func labelsContain(_ needle: String) -> Bool {
        labels().contains { $0.localizedCaseInsensitiveContains(needle) }
    }

    /// Settles the run loop briefly so a just-entered overlay has actually drawn (the accessibility
    /// tree flips a frame before the cross-fade finishes), keeping the capture off a transition frame.
    private func settle(_ interval: TimeInterval = 0.7) {
        let deadline = Date().addingTimeInterval(interval)
        while Date() < deadline {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.05))
            window?.rootViewController?.view.setNeedsLayout()
            window?.rootViewController?.view.layoutIfNeeded()
        }
    }

    private func capture(_ fileName: String) throws {
        guard let root = window?.rootViewController?.view else { return XCTFail("no hosted surface") }
        let image = HostedSurface.capture(root, size: playerSize)
        let path = try EvidenceOutput.write(image, named: fileName, for: story)
        print("US-CC05 EVIDENCE: \(fileName) -> \(path); labels=\(labels())")
    }

    /// Hosts the real player on a per-side warm-up bookend and captures the three US-CC05 frames as the
    /// production tickers carry it hands-free through side 1 -> Switch sides -> side 2.
    func testHandsFreeBookendFlowRendersThreeFrames() throws {
        // Legs long enough that the real-time flow lands each of the three frames distinctly (side 1
        // for ~12s, then the 5s beat, then side 2) rather than racing past them under the pump cadence.
        let holdSeconds = 12
        let view = ActiveSessionView(workout: perSideWarmupBookendWorkout(seconds: holdSeconds))
        let (_, hostedWindow) = HostedSurface.host(view, size: playerSize)
        window = hostedWindow

        // Frame 1 - side 1 auto-started hands-free. `onAppear` calls `start()`, which auto-starts the
        // bookend hold with no tap. The hard invariant: a "Hold" countdown is on screen, the tracker
        // reads side 1 of 2, and *no* "Start hold" control exists anywhere.
        XCTAssertTrue(
            pump(until: { self.labelsContain("Hold,") && self.labelsContain("side 1 of 2") }, timeout: 8),
            "the bookend hold never auto-started on side 1; tree reads \(labels())"
        )
        XCTAssertFalse(
            labelsContain("Start hold"),
            "a bookend hold must offer no Start-hold tap - it is hands-free (US-CC05); tree reads \(labels())"
        )
        settle()
        try capture("01-bookend-hold-side1-autostarted.png")

        // Frame 2 - the brief "Switch sides" beat. Side 1's real-time countdown elapses and a
        // hands-free get-ready pause bridges the two legs, naming itself so the user changes position.
        // Require the hold view's own control ("Stop hold") to be gone so the capture lands on the
        // fully-drawn rest overlay rather than the cross-fade frame the tree flips one step ahead of.
        XCTAssertTrue(
            pump(until: { self.labelsContain("Switch sides") && !self.labelsContain("Stop hold") }, timeout: 20),
            "the per-side bookend never reached the hands-free Switch sides beat; tree reads \(labels())"
        )
        XCTAssertFalse(labelsContain("Start hold"), "no Start-hold tap on the Switch sides beat either")
        settle()
        try capture("02-switch-sides-beat.png")

        // Frame 3 - side 2 auto-started. The beat ends and side 2's hold auto-starts with no tap; the
        // beat is gone and a fresh "Hold" countdown is back on side 2, still with no Start-hold control.
        XCTAssertTrue(
            pump(
                until: { self.labelsContain("Hold,") && self.labelsContain("side 2 of 2")
                    && !self.labelsContain("Switch sides") },
                timeout: 12
            ),
            "side 2 never auto-started after the Switch sides beat; tree reads \(labels())"
        )
        XCTAssertFalse(labelsContain("Start hold"), "side 2 must not wait for a Start-hold tap either")
        settle()
        try capture("03-bookend-hold-side2-autostarted.png")
    }
}
