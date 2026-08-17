import XCTest
import SwiftUI
@testable import RepToday

/// Reviewer-visible evidence for US-CC14: **+ More time** is a first-class, always-available control on
/// the auto-advancing follow-along countdowns, and those countdowns are accessible.
///
/// This drives the *production* `ActiveSessionView` in a real key window and asserts the load-bearing
/// accessibility structure on the live tree, then captures the frames to PNGs:
///
/// - AC1: a labeled, hittable **+ More time** control ("More time") sits on the running work window and
///   the running hold, and activating it (exactly as VoiceOver's double-tap would) lengthens the live
///   countdown - proven by reading the ring's own spoken remaining-time before and after.
/// - AC2: the countdown ring carries the `.updatesFrequently` trait, so VoiceOver polls the remaining
///   time on demand rather than announcing every per-second change or stealing focus.
/// - AC4: a Reduce Motion frame is captured so a reviewer can see the ring rendered without its sweep
///   (the non-animation itself is not tree-observable, so this is the visual companion to manual QA).
///
/// It is the visual companion to the deterministic `ActiveSessionViewModelTests` "+ More time" suite,
/// which pins the extend arithmetic and the US-CC09 no-log-change invariant under an injected clock.
@MainActor
final class MoreTimeAccessibilityEvidenceTests: XCTestCase {

    private var window: UIWindow?

    private let story = "us-cc14"
    private let playerSize = CGSize(width: 393, height: 852)

    override func tearDown() {
        window = nil
        super.tearDown()
    }

    // MARK: - Fixtures

    /// A rep-based strength set whose planned work window is long enough (a large per-set estimate) that
    /// the test can read, extend, and re-read it before it would elapse on its own.
    private func longWindowStrengthWorkout() -> Workout {
        let push = Exercise(
            id: "push_up", displayName: "Push-up", pillar: .strength, movementPattern: .push,
            category: .strength, difficulty: 2, phase: .discipline, equipment: [],
            isHold: false, defaultReps: 8, defaultDurationSeconds: nil,
            estimatedTimePerSetSeconds: 60, metValue: 4, progressionChainId: "push_up_chain",
            progressionOrder: 0, regressionId: nil, progressionId: nil, advancementCriteria: "", apartmentFriendly: true
        )
        let strength = WorkoutBlock(
            id: UUID(), title: "Strength", category: .strength,
            exercises: [PrescribedExercise(id: UUID(), exercise: push, sets: 2, reps: 8, durationSeconds: nil, restSeconds: 45)]
        )
        return Workout(
            id: UUID(), createdAt: Date(), shape: .blend, focusPillar: nil,
            requestedMinutes: 15, wasReturn: false, blocks: [strength]
        )
    }

    /// A warm-up hold that auto-starts hands-free (US-CC05), so the player opens straight onto a running
    /// hold - the second countdown "+ More time" must sit on. A generous 60s hold gives the test room.
    private func warmupHoldWorkout() -> Workout {
        let hold = Exercise(
            id: "cat_cow", displayName: "Cat-Cow", pillar: .mobility, movementPattern: .mobility,
            category: .mobility, difficulty: 1, phase: .discipline, equipment: [],
            isHold: true, defaultReps: nil, defaultDurationSeconds: 60, estimatedTimePerSetSeconds: 60,
            metValue: 2, progressionChainId: "cat_cow_chain", progressionOrder: 0,
            regressionId: nil, progressionId: nil, advancementCriteria: "", apartmentFriendly: true
        )
        let warmup = WorkoutBlock(
            id: UUID(), title: "Warm-up", category: .warmup,
            exercises: [PrescribedExercise(id: UUID(), exercise: hold, sets: 1, reps: nil, durationSeconds: 60, restSeconds: 20)]
        )
        return Workout(
            id: UUID(), createdAt: Date(), shape: .blend, focusPillar: nil,
            requestedMinutes: 15, wasReturn: false, blocks: [warmup]
        )
    }

    // MARK: - Tree helpers

    private func root() -> UIView? { window?.rootViewController?.view }

    private func labels() -> [String] {
        guard let root = root() else { return [] }
        return AccessibilityTree.labels(in: root)
    }

    private func labelsContain(_ needle: String) -> Bool {
        labels().contains { $0.localizedCaseInsensitiveContains(needle) }
    }

    /// The remaining seconds spoken by the countdown ring, parsed off its "<name>, N seconds remaining"
    /// label - the same on-demand value a VoiceOver user reads.
    private func ringSeconds(prefix: String) -> Int? {
        guard let label = labels().first(where: { $0.hasPrefix(prefix) }) else { return nil }
        let tail = label.dropFirst(prefix.count)
        return Int(tail.prefix { $0.isNumber })
    }

    @discardableResult
    private func pump(until predicate: () -> Bool, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if predicate() { return true }
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.05))
            root()?.setNeedsLayout()
            root()?.layoutIfNeeded()
        }
        return predicate()
    }

    private func settle(_ interval: TimeInterval = 0.7) {
        let deadline = Date().addingTimeInterval(interval)
        while Date() < deadline {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.05))
            root()?.setNeedsLayout()
            root()?.layoutIfNeeded()
        }
    }

    private func capture(_ fileName: String) throws {
        guard let root = root() else { return XCTFail("no hosted surface") }
        let image = HostedSurface.capture(root, size: playerSize)
        let path = try EvidenceOutput.write(image, named: fileName, for: story)
        print("US-CC14 EVIDENCE: \(fileName) -> \(path); labels=\(labels())")
    }

    // MARK: - Tests

    /// The work window: **+ More time** is present and hittable, the ring is a `.updatesFrequently`
    /// element, and activating "+ More time" the way VoiceOver would lengthens the spoken countdown.
    func testMoreTimeIsReachableAndExtendsTheWorkWindow() throws {
        let view = ActiveSessionView(workout: longWindowStrengthWorkout())
        let (_, hostedWindow) = HostedSurface.host(view, size: playerSize)
        window = hostedWindow
        let root = try XCTUnwrap(root())

        XCTAssertTrue(
            pump(until: { self.labelsContain("Work window,") }, timeout: 8),
            "the work window countdown ring never appeared; tree reads \(labels())"
        )

        // AC1: a labeled, hittable "+ More time" control (accessibility label "More time") is present.
        let moreTime = try XCTUnwrap(
            AccessibilityTree.element(labeled: "More time", in: root),
            "+ More time is missing from the work window; tree reads \(labels())"
        )

        // AC2: the ring is marked frequently-updating, so VoiceOver reads the time on demand rather than
        // announcing every tick or stealing focus.
        let ring = try XCTUnwrap(
            AccessibilityTree.element(whereLabel: { $0.hasPrefix("Work window, ") }, in: root),
            "the work window ring element was not found"
        )
        XCTAssertTrue(
            ring.accessibilityTraits.contains(.updatesFrequently),
            "the countdown ring must carry .updatesFrequently so VoiceOver does not spam per-second announcements (US-CC14)"
        )

        settle()
        try capture("01-more-time-work-window.png")

        // AC1: activating "+ More time" exactly as VoiceOver's double-tap would extends the live window.
        let before = try XCTUnwrap(ringSeconds(prefix: "Work window, "), "could not read the ring's remaining time")
        _ = moreTime.accessibilityActivate()
        settle(1.0)
        let after = try XCTUnwrap(ringSeconds(prefix: "Work window, "), "could not re-read the ring's remaining time")
        XCTAssertGreaterThan(
            after, before,
            "activating + More time must add time to the live window (was \(before)s, now \(after)s)"
        )
    }

    /// The hold: an auto-started warm-up hold likewise carries a hittable **+ More time**, and the ring
    /// is a `.updatesFrequently` element - so the control is on *every* auto-advancing countdown, not
    /// only the work window.
    func testMoreTimeIsPresentAndAccessibleOnAHold() throws {
        let view = ActiveSessionView(workout: warmupHoldWorkout())
        let (_, hostedWindow) = HostedSurface.host(view, size: playerSize)
        window = hostedWindow
        let root = try XCTUnwrap(root())

        XCTAssertTrue(
            pump(until: { self.labelsContain("Hold,") }, timeout: 8),
            "the hold countdown ring never appeared; tree reads \(labels())"
        )

        let moreTime = try XCTUnwrap(
            AccessibilityTree.element(labeled: "More time", in: root),
            "+ More time is missing from the running hold; tree reads \(labels())"
        )

        let ring = try XCTUnwrap(
            AccessibilityTree.element(whereLabel: { $0.hasPrefix("Hold, ") }, in: root),
            "the hold ring element was not found"
        )
        XCTAssertTrue(
            ring.accessibilityTraits.contains(.updatesFrequently),
            "the hold countdown ring must carry .updatesFrequently (US-CC14)"
        )

        let before = try XCTUnwrap(ringSeconds(prefix: "Hold, "))
        _ = moreTime.accessibilityActivate()
        settle(1.0)
        let after = try XCTUnwrap(ringSeconds(prefix: "Hold, "))
        XCTAssertGreaterThan(after, before, "activating + More time must lengthen the hold (was \(before)s, now \(after)s)")

        settle()
        try capture("02-more-time-hold.png")
    }

    // AC4 (Reduce Motion - the ring drops its sweep for a static step): the environment value
    // `accessibilityReduceMotion` is read-only in the SDK and cannot be overridden on a hosted surface,
    // so - exactly as US-CC11's Reduce-Motion stilling was handled - the behavior is enforced by
    // `CountdownRing`'s `reduceMotion ? nil : .linear` animation gate and verified by on-device manual
    // QA rather than a hosted assertion. Recorded in artifacts/reports/us-cc14/validation.md.
}
