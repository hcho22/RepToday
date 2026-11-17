import XCTest
import SwiftUI
@testable import RepToday

/// Reviewer evidence for ADR-0020 on the production exercise screen: the Standard Push-Up's card carries
/// its one line naming the easier options, and a movement added without Trainer art (Wide Push-Up) shows
/// the card's icon fallback. Each runs on the default phone (393x852 pt) and the small phone (375x667 pt),
/// dark and light, asserts the live accessibility tree and that the timer still sits above the controls,
/// and writes a PNG per state under `artifacts/reports/ADR-0020/` only when run with
/// `REPTODAY_WRITE_EVIDENCE=1` (a temporary directory otherwise).
@MainActor
final class PushLegsCardEvidenceTests: XCTestCase {

    private let story = "ADR-0020"
    private var window: UIWindow?

    private struct Variant {
        let size: CGSize
        let style: UIUserInterfaceStyle
        var suffix: String { "\(Int(size.width))x\(Int(size.height))-\(style == .dark ? "dark" : "light")" }
        /// The small variant is an iPhone SE (3rd generation): a 20 pt status bar, no home indicator.
        var safeArea: UIEdgeInsets? { size.width < 390 ? UIEdgeInsets(top: 20, left: 0, bottom: 0, right: 0) : nil }
    }

    private let variants: [Variant] = [
        Variant(size: CGSize(width: 393, height: 852), style: .dark),
        Variant(size: CGSize(width: 393, height: 852), style: .light),
        Variant(size: CGSize(width: 375, height: 667), style: .dark),
        Variant(size: CGSize(width: 375, height: 667), style: .light),
    ]

    private let cue = "Can't do a full push-up yet? Do it against a wall, on an incline or on your knees."

    override func tearDown() {
        window = nil
        super.tearDown()
    }

    // MARK: - Fixtures

    private func prescription(_ id: String) async throws -> PrescribedExercise {
        let found = try await MockExerciseService().exercise(id: id)
        let exercise = try XCTUnwrap(found, "no \(id) in the offered catalog")
        return PrescribedExercise(id: UUID(), exercise: exercise, sets: 4, reps: 15, durationSeconds: nil, restSeconds: 30)
    }

    private func session(_ prescription: PrescribedExercise) -> Workout {
        Workout(
            id: UUID(), createdAt: Date(), shape: .blend, focusPillar: nil, requestedMinutes: 15, wasReturn: false,
            blocks: [WorkoutBlock(id: UUID(), title: "Strength", category: .strength, exercises: [prescription])],
            trainingDay: .push
        )
    }

    private func user() -> User {
        var user = MockPersistence.sampleUser
        user.profile.fitnessLevel = .beginner
        user.profile.sex = .female
        return user
    }

    // MARK: - Hosting

    private func labels() -> [String] {
        guard let root = window?.rootViewController?.view else { return [] }
        return AccessibilityTree.labels(in: root)
    }

    private func frame(_ predicate: (String) -> Bool) -> CGRect? {
        guard let root = window?.rootViewController?.view,
              let frame = AccessibilityTree.element(whereLabel: predicate, in: root)?.accessibilityFrame,
              let origin = window?.frame.origin else { return nil }
        return frame.offsetBy(dx: -origin.x, dy: -origin.y)
    }

    private func pump(until predicate: () -> Bool, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if predicate() { return true }
            HostedSurface.pump(for: 0.1)
        }
        return predicate()
    }

    private func host(_ workout: Workout, _ variant: Variant) {
        window = nil
        let (_, hosted) = HostedSurface.host(
            ActiveSessionView(workout: workout, user: user()),
            size: variant.size, settleFor: 1.5, style: variant.style, emulatingSafeArea: variant.safeArea
        )
        window = hosted
    }

    private func capture(_ name: String, _ variant: Variant) throws {
        guard let root = window?.rootViewController?.view else { return XCTFail("no hosted surface") }
        HostedSurface.pump(for: 0.6)
        let image = HostedSurface.capture(root, size: variant.size, afterScreenUpdates: true)
        let path = try EvidenceOutput.write(image, named: "\(name)-\(variant.suffix).png", for: story)
        print("ADR-0020 EVIDENCE: \(path)")
    }

    /// The timer opens whole above Done, below the movement's name.
    private func assertTimerAboveDone(_ variant: Variant, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(pump(until: { self.labels().contains { $0.hasPrefix("Work window, ") } }, timeout: 5),
                      "\(variant.suffix): \(labels())", file: file, line: line)
        guard let timer = frame({ $0.hasPrefix("Work window, ") }), let done = frame({ $0 == "Done" }) else {
            return XCTFail("\(variant.suffix): no timer or Done; tree reads \(labels())", file: file, line: line)
        }
        XCTAssertLessThanOrEqual(timer.maxY, done.minY, "\(variant.suffix): the timer must sit above Done", file: file, line: line)
    }

    // MARK: - Evidence

    /// The Standard Push-Up's card shows the easier options under its name, above the round tracker, and
    /// the timer still opens above Done on a small phone.
    func testStandardPushUpCardShowsTheEasierOptions() async throws {
        let workout = session(try await prescription("push_standard"))
        for variant in variants {
            host(workout, variant)
            XCTAssertTrue(pump(until: { self.labels().contains(self.cue) }, timeout: 5), "\(variant.suffix): \(labels())")
            guard let line = frame({ $0 == cue }),
                  let title = frame({ $0.hasPrefix("Standard Push-Up, ") }),
                  let tracker = frame({ $0.hasPrefix("Round ") || $0.hasPrefix("Set ") }) else {
                return XCTFail("\(variant.suffix): missing title, cue or tracker; tree reads \(labels())")
            }
            XCTAssertGreaterThanOrEqual(line.minY, title.maxY - 0.5, "\(variant.suffix): the line sits under the name")
            XCTAssertLessThanOrEqual(line.maxY, tracker.minY + 0.5, "\(variant.suffix): the line sits above the round tracker")
            assertTimerAboveDone(variant)
            try capture("01-standard-push-up-easier-options", variant)
        }
    }

    /// A movement added without Trainer art shows the card's icon, named for VoiceOver as a demonstration,
    /// and no cue line of its own.
    func testNewMovementWithoutArtShowsTheIcon() async throws {
        let workout = session(try await prescription("push_wide"))
        for variant in variants {
            host(workout, variant)
            XCTAssertTrue(pump(until: { self.labels().contains("Wide Push-Up demonstration") }, timeout: 5),
                          "\(variant.suffix): \(labels())")
            XCTAssertFalse(labels().contains { $0.contains("trainer showing") }, "\(variant.suffix): no pose art exists for it")
            XCTAssertFalse(labels().contains(cue), "\(variant.suffix): only Standard carries the line")
            assertTimerAboveDone(variant)
            try capture("02-wide-push-up-icon-fallback", variant)
        }
    }
}
