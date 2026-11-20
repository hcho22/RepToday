import XCTest
import SwiftUI
@testable import RepToday

/// Reviewer evidence for the "couldn't finish" follow-up after "too hard" (ADR-0022): on the production
/// completion screen, a Fixed Target move's card (Forearm Plank, Dead Bug) says its target stays the same
/// and the session just won't count toward moving up, while every other move keeps today's ease-off
/// wording. Light and dark (the app is dark-only, so they share a palette); PNGs go to a temporary
/// directory unless `REPTODAY_EVIDENCE_DIR` or `REPTODAY_WRITE_EVIDENCE=1` sends them elsewhere.
@MainActor
final class FixedTargetFinishCheckEvidenceTests: XCTestCase {

    private var window: UIWindow?
    private let size = CGSize(width: 393, height: 1500)
    private let easeOff = "Tap them and only those ease off next time. Tap none and everything eases off a little."

    override func tearDown() {
        window = nil
        super.tearDown()
    }

    private func labels() -> [String] {
        guard let root = window?.rootViewController?.view else { return [] }
        return AccessibilityTree.labels(in: root)
    }

    private func pump(until predicate: () -> Bool, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if predicate() { return true }
            HostedSurface.pump(for: 0.1)
        }
        return predicate()
    }

    /// A one-round circuit of Standard Push-Up, Dead Bug and Forearm Plank, parked on the plank's last
    /// set with the first two done.
    private func parkedOnTheLastSet() async throws -> ActiveSessionState {
        let service = try MockExerciseService()
        var prescriptions: [PrescribedExercise] = []
        for (id, value) in [("push_standard", 15), ("core_dead_bug", 15), ("core_forearm_plank", 60)] {
            let found = try await service.exercise(id: id)
            let exercise = try XCTUnwrap(found)
            prescriptions.append(PrescribedExercise(
                id: UUID(), exercise: exercise, sets: 1,
                reps: exercise.isHold ? nil : value, durationSeconds: exercise.isHold ? value : nil,
                restSeconds: 15, role: id.hasPrefix("core") ? .core : .main
            ))
        }
        let workout = Workout(
            id: UUID(), createdAt: Date(), shape: .blend, focusPillar: nil, requestedMinutes: 15, wasReturn: false,
            blocks: [WorkoutBlock(id: UUID(), title: "Push Day", category: .strength, exercises: prescriptions)],
            trainingDay: .push
        )
        let fresh = ActiveSessionState(fresh: workout)
        var completed: [UUID: [CompletedSet]] = [:]
        for slot in fresh.slots.prefix(2) {
            completed[slot.prescription.id] = [CompletedSet(reps: slot.prescription.reps, durationSeconds: slot.prescription.durationSeconds)]
        }
        return ActiveSessionState(
            workout: fresh.workout, slots: fresh.slots, currentStepIndex: 2, currentSet: 1,
            completedSets: completed, skippedStepIDs: [], startedAt: Date().addingTimeInterval(-600), rest: nil
        )
    }

    func testAFixedTargetMoveSaysItsTargetStaysTheSame() async throws {
        let note = ActiveSessionView.finishCheckHoldNote
        for style in [UIUserInterfaceStyle.light, .dark] {
            let state = try await parkedOnTheLastSet()
            window = nil
            let (_, hosted) = HostedSurface.host(
                ActiveSessionView(resuming: state, user: MockPersistence.sampleUser),
                size: size, settleFor: 1.5, style: style
            )
            window = hosted
            let root = try XCTUnwrap(window?.rootViewController?.view)
            XCTAssertTrue(pump(until: { AccessibilityTree.element(labeled: "Finish session", in: root) != nil }, timeout: 10), "\(labels())")
            XCTAssertTrue(try XCTUnwrap(AccessibilityTree.element(labeled: "Finish session", in: root)).accessibilityActivate())
            XCTAssertTrue(pump(until: { AccessibilityTree.element(labeled: "Too hard", in: root) != nil }, timeout: 20), "\(labels())")
            XCTAssertTrue(try XCTUnwrap(AccessibilityTree.element(labeled: "Too hard", in: root)).accessibilityActivate())
            XCTAssertTrue(pump(until: { self.labels().contains("Any you couldn't finish?") }, timeout: 10), "\(labels())")

            let read = labels()
            XCTAssertTrue(read.contains("Forearm Plank, \(note)"), "\(read)")
            XCTAssertTrue(read.contains("Dead Bug, \(note)"), "\(read)")
            XCTAssertTrue(read.contains("Standard Push-Up"), "every other move keeps its plain card: \(read)")
            XCTAssertFalse(read.contains("Standard Push-Up, \(note)"), "\(read)")
            XCTAssertTrue(read.contains(easeOff), "the header keeps its ease-off line for the push-up: \(read)")

            HostedSurface.pump(for: 0.6)
            let image = HostedSurface.capture(root, size: size, afterScreenUpdates: true)
            let path = try EvidenceOutput.write(
                image, named: "06-couldnt-finish-\(style == .dark ? "dark" : "light").png", for: EvidenceOutput.Story.fixedTargets
            )
            print("FIXED TARGET EVIDENCE: \(path)")
        }
    }
}
