import XCTest
import SwiftUI
@testable import RepToday

/// Reviewer-visible evidence for US-CC11: the rep-based **work window is visual-primary** - it shows a
/// clear static movement illustration *together with* the countdown ring (a text-and-ring-only window is
/// rejected as too bare), and the between-station **transition beat** leads with a prominent
/// "Next: <exercise>" cue, the visual substitute for a spoken "next up".
///
/// This drives the *production* `ActiveSessionView` in a real key window and lets its own real-time
/// tickers advance the flow, then asserts the load-bearing structure on the live accessibility tree and
/// captures the two frames to PNGs. It is the visual companion to the deterministic
/// `ActiveSessionViewModelTests` (`testTransitionBeatIsDistinctFromRoundRest`), which pins the
/// transition-vs-round-rest distinction under an injected clock; this shows a reviewer the actual pixels.
///
/// The per-set work seconds are kept short (small `estimatedTimePerSetSeconds`) so the real-time window
/// elapses quickly into the transition; the mechanic is identical at any duration.
@MainActor
final class VisualWorkWindowEvidenceTests: XCTestCase {

    private var window: UIWindow?

    private let story = "us-cc11"
    private let playerSize = CGSize(width: 393, height: 852)

    override func tearDown() {
        window = nil
        super.tearDown()
    }

    private func repExercise(id: String, name: String, pattern: MovementPattern, estimate: Int) -> Exercise {
        Exercise(
            id: id, displayName: name, pillar: .strength, movementPattern: pattern,
            category: .strength, difficulty: 2, phase: .discipline, equipment: [],
            isHold: false, defaultReps: 8, defaultDurationSeconds: nil,
            estimatedTimePerSetSeconds: estimate, metValue: 4,
            progressionChainId: "\(id)_chain", progressionOrder: 0,
            regressionId: nil, progressionId: nil, advancementCriteria: "", apartmentFriendly: true
        )
    }

    /// A strength-only two-station circuit so the first step is a rep-based work window (no warm-up to
    /// wait through) and completing it crosses a between-station transition to the second station.
    private func strengthCircuitWorkout() -> Workout {
        let strength = WorkoutBlock(
            id: UUID(), title: "Strength", category: .strength,
            exercises: [
                PrescribedExercise(
                    id: UUID(),
                    exercise: repExercise(id: "push_up", name: "Push-up", pattern: .push, estimate: 6),
                    sets: 2, reps: 8, durationSeconds: nil, restSeconds: 45
                ),
                PrescribedExercise(
                    id: UUID(),
                    exercise: repExercise(id: "squat", name: "Bodyweight Squat", pattern: .squat, estimate: 6),
                    sets: 2, reps: 8, durationSeconds: nil, restSeconds: 45
                )
            ]
        )
        return Workout(
            id: UUID(), createdAt: Date(), shape: .blend, focusPillar: nil,
            requestedMinutes: 15, wasReturn: false, blocks: [strength]
        )
    }

    private func labels() -> [String] {
        guard let root = window?.rootViewController?.view else { return [] }
        return AccessibilityTree.labels(in: root)
    }

    private func labelsContain(_ needle: String) -> Bool {
        labels().contains { $0.localizedCaseInsensitiveContains(needle) }
    }

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
        print("US-CC11 EVIDENCE: \(fileName) -> \(path); labels=\(labels())")
    }

    /// Hosts the real player on a strength circuit and asserts the two US-CC11 invariants on the live
    /// tree: the work window shows illustration **and** ring (not ring-only), and the transition beat
    /// leads with a prominent "Next: <exercise>".
    func testVisualWorkWindowAndTransitionBeatRenderTwoFrames() throws {
        let view = ActiveSessionView(workout: strengthCircuitWorkout())
        let (_, hostedWindow) = HostedSurface.host(view, size: playerSize)
        window = hostedWindow

        // Frame 1 - the visual-primary work window. The hard invariant: the countdown ring is present
        // (a "Work window," label) *and* the movement illustration is present alongside it (a
        // "<name> demonstration" label). Text-and-ring-only is rejected (US-CC11 AC), so the
        // demonstration label proves the illustration is not gone.
        XCTAssertTrue(
            pump(until: { self.labelsContain("Work window,") }, timeout: 8),
            "the work window countdown ring never appeared; tree reads \(labels())"
        )
        XCTAssertTrue(
            labelsContain("Push-up demonstration"),
            "the work window must show the movement illustration beside the ring, not ring-only (US-CC11); tree reads \(labels())"
        )
        settle()
        try capture("01-visual-work-window.png")

        // Frame 2 - the between-station transition beat. Push-up's window elapses hands-free and the
        // player crosses into the transition, which must lead with the prominent "Next: <exercise>" cue
        // naming the next station.
        XCTAssertTrue(
            pump(until: { self.labelsContain("Next: Bodyweight Squat") }, timeout: 20),
            "the transition beat never surfaced a prominent 'Next: <exercise>' cue; tree reads \(labels())"
        )
        settle()
        try capture("02-transition-beat-next-cue.png")
    }
}
