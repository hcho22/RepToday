import XCTest
import SwiftUI
@testable import RepToday

/// The workout player and its rest overlay at every Dynamic Type size on the smallest supported screen
/// (375x667 pt, an iPhone SE), in light and dark.
///
/// Hosts the **production** `ActiveSessionView` over real catalog movements and asserts on the live
/// accessibility tree that every control is on screen, overlaps no other control, never breaks a word
/// of its title in two, and - where the player's secondary controls move into its scrolling column at
/// large sizes - is reached by scrolling it. At the default size the secondary row keeps its single
/// row and the rest controls sit side by side, as they always have. A PNG per state, size and
/// appearance goes under `artifacts/reports/player-large-text/` when run with
/// `REPTODAY_WRITE_EVIDENCE=1` (a temporary directory otherwise).
@MainActor
final class PlayerLargeTextFitEvidenceTests: XCTestCase {

    private let story = "player-large-text"
    private let screen = CGSize(width: 375, height: 667)
    /// An iPhone SE (3rd generation): a 20 pt status bar, no home indicator.
    private let statusBar: CGFloat = 20
    private var window: UIWindow?

    private let sizes: [DynamicTypeSize] = [.large, .xLarge, .xxxLarge, .accessibility1, .accessibility3, .accessibility5]
    private let styles: [UIUserInterfaceStyle] = [.light, .dark]
    /// The sizes a PNG is kept for: the default and the largest.
    private let captured: Set<DynamicTypeSize> = [.large, .accessibility5]

    /// The secondary controls by accessibility label, with the title each one shows.
    private let secondaryTitles: [String: String] = [
        "More time": "+ More time",
        "Swap this exercise": "Swap",
        "Complete set": "Complete set",
        "Finish exercise": "Finish exercise",
        "Skip this exercise": "Skip",
    ]

    override func tearDown() {
        window = nil
        super.tearDown()
    }

    // MARK: - Player

    /// A rep-based set: Done pinned, + More time / Swap / Skip in the secondary row.
    func testWorkWindowControlsFitAtEveryTextSize() throws {
        let session = workout([("Strength", .strength, [try prescription("push_wall", sets: 2), try prescription("squat_bodyweight", sets: 2)])])
        try assertPlayerFits(session, primary: "Done", ring: "Work window, ", name: "work-window")
    }

    /// A running training hold on a non-final set: the widest secondary row - + More time, Swap,
    /// Complete set and Skip.
    func testRunningHoldControlsFitAtEveryTextSize() throws {
        let session = workout([("Strength", .strength, [try prescription("core_forearm_plank", sets: 2), try prescription("push_wall", sets: 2)])])
        try assertPlayerFits(session, primary: "Stop hold", ring: "Hold, ", name: "running-hold")
    }

    private func assertPlayerFits(_ session: Workout, primary: String, ring: String, name: String,
                                  file: StaticString = #filePath, line: UInt = #line) throws {
        for size in sizes {
            for style in styles {
                let look = "\(size)-\(style == .dark ? "dark" : "light")"
                // A swap engine wired, so Swap is offered as it is in the app.
                let engine = OnDeviceWorkoutEngine(exerciseService: try MockExerciseService())
                host(ActiveSessionView(workout: session, workoutEngine: engine, user: user()), style, size: size)
                XCTAssertTrue(pump(until: { self.labels().contains { $0.hasPrefix(ring) } }, timeout: 5),
                              "\(look): no running countdown; tree reads \(labels())", file: file, line: line)
                HostedSurface.pump(for: 0.5) // let the card settle on its fitted height

                let secondary = secondaryTitles.keys.filter { frame(of: $0) != nil }
                XCTAssertTrue(secondary.contains("Swap this exercise") && secondary.count >= 3, "\(look): missing secondary controls; tree reads \(labels())", file: file, line: line)
                for label in secondary {
                    assertNoWordBreak(label, look, file: file, line: line)
                }
                if size == .large {
                    let rows = Set(secondary.compactMap { frame(of: $0)?.minY.rounded() })
                    XCTAssertEqual(rows.count, 1, "\(look): the default size keeps the secondary controls in one row", file: file, line: line)
                }
                if captured.contains(size) { try capture("\(name)-\(look)", style) }

                // Scrolled to the end, every control - the pinned ones and any the column carries - is
                // on screen, whole, and clear of every other.
                scrollPlayerToEnd()
                let controls = ["End session", "Pause session", primary] + secondary
                assertOnScreenAndApart(controls, look, file: file, line: line)
                if let visible = visibleScrollArea(), let pinned = frame(of: primary) {
                    for label in secondary {
                        guard let control = frame(of: label) else { continue }
                        let inColumn = visible.insetBy(dx: 0, dy: -0.5).contains(control)
                        let inPinnedRow = control.minY >= pinned.maxY - 0.5
                        XCTAssertTrue(inColumn || inPinnedRow,
                                      "\(look): \"\(label)\" is cut by the scroll area's edge at \(control)", file: file, line: line)
                    }
                }
                if size == .accessibility5 {
                    try capture("\(name)-\(look)-scrolled", style)
                }
            }
        }
    }

    // MARK: - Rest overlay

    /// The rest overlay keeps its top bar, + 15s and Skip rest on screen and apart at every size, with
    /// neither title cut, and Skip rest works the way VoiceOver activates it.
    func testRestControlsFitAtEveryTextSize() throws {
        let session = workout([("Strength", .strength, [try prescription("push_wall", sets: 2), try prescription("squat_bodyweight", sets: 2)])])
        for size in sizes {
            for style in styles {
                let look = "\(size)-\(style == .dark ? "dark" : "light")"
                host(ActiveSessionView(workout: session, user: user()), style, size: size)
                XCTAssertTrue(pump(until: { self.labels().contains("Done") }, timeout: 5), "\(look): \(labels())")
                activate("Done")
                XCTAssertTrue(pump(until: { self.labels().contains("Skip rest") }, timeout: 5), "\(look): no rest; \(labels())")
                HostedSurface.pump(for: 0.5)

                let extend = "Extend rest by \(ActiveSessionViewModel.restExtension) seconds"
                assertOnScreenAndApart(["End session", "Pause session", extend, "Skip rest"], look)
                if let skip = frame(of: "Skip rest"), let more = frame(of: extend) {
                    for (control, title) in [(skip, "Skip rest"), (more, "+\(ActiveSessionViewModel.restExtension)s")] {
                        let needed = ActiveSessionView.textWidth(title, style: .headline, size: size)
                        XCTAssertGreaterThanOrEqual(control.width, needed, "\(look): \"\(title)\" is wider than its button", file: #filePath, line: #line)
                    }
                    if size == .large {
                        XCTAssertEqual(skip.minY, more.minY, accuracy: 0.5, "\(look): the default size keeps the rest controls side by side")
                    }
                }
                if captured.contains(size) { try capture("rest-\(look)", style) }

                activate("Skip rest")
                XCTAssertTrue(pump(until: { !self.labels().contains("Skip rest") }, timeout: 5),
                              "\(look): Skip rest did not end the rest; tree reads \(labels())")
            }
        }
    }

    // MARK: - Assertions

    /// Every control is inside the screen below the status bar and overlaps no other.
    private func assertOnScreenAndApart(_ labels: [String], _ look: String, file: StaticString = #filePath, line: UInt = #line) {
        let frames = labels.compactMap { label in frame(of: label).map { (label, $0) } }
        XCTAssertEqual(frames.count, labels.count, "\(look): missing controls; tree reads \(self.labels())", file: file, line: line)
        for (label, control) in frames {
            XCTAssertGreaterThanOrEqual(control.minY, statusBar - 0.5, "\(look): \"\(label)\" runs above the screen at \(control)", file: file, line: line)
            XCTAssertLessThanOrEqual(control.maxY, screen.height + 0.5, "\(look): \"\(label)\" runs below the screen at \(control)", file: file, line: line)
        }
        for (index, (label, control)) in frames.enumerated() {
            for (otherLabel, other) in frames[(index + 1)...] {
                let overlap = control.intersection(other)
                XCTAssertTrue(overlap.isNull || overlap.width < 0.5 || overlap.height < 0.5,
                              "\(look): \"\(label)\" overlaps \"\(otherLabel)\"", file: file, line: line)
            }
        }
    }

    /// A secondary control is at least as wide as the longest word of its title, so the word is never
    /// broken across lines.
    private func assertNoWordBreak(_ label: String, _ look: String, file: StaticString, line: UInt) {
        guard let control = frame(of: label), let title = secondaryTitles[label] else { return }
        let size = hostedSize
        let longest = title.split(separator: " ").map { ActiveSessionView.textWidth(String($0), style: .body, size: size) }.max() ?? 0
        XCTAssertGreaterThanOrEqual(control.width, longest, "\(look): \"\(title)\" breaks a word in its \(control.width) pt control", file: file, line: line)
    }

    // MARK: - Fixtures

    /// The Dynamic Type size of the surface hosted now.
    private var hostedSize: DynamicTypeSize = .large

    private func catalog() throws -> [String: Exercise] {
        let url = try XCTUnwrap(Bundle(for: AppState.self).url(forResource: "Exercises", withExtension: "json"))
        let list = try JSONDecoder().decode([Exercise].self, from: Data(contentsOf: url))
        return Dictionary(uniqueKeysWithValues: list.map { ($0.id, $0) })
    }

    private func prescription(_ id: String, sets: Int) throws -> PrescribedExercise {
        let exercise = try XCTUnwrap(try catalog()[id], "no \(id) in the catalog")
        return PrescribedExercise(
            id: UUID(), exercise: exercise, sets: sets,
            reps: exercise.isHold ? nil : exercise.defaultReps,
            durationSeconds: exercise.isHold ? exercise.defaultDurationSeconds : nil,
            restSeconds: 30
        )
    }

    private func workout(_ blocks: [(String, ExerciseCategory, [PrescribedExercise])]) -> Workout {
        Workout(
            id: UUID(), createdAt: Date(), shape: .blend, focusPillar: nil, requestedMinutes: 15,
            wasReturn: false,
            blocks: blocks.map { WorkoutBlock(id: UUID(), title: $0.0, category: $0.1, exercises: $0.2) }
        )
    }

    private func user() -> User {
        var user = MockPersistence.sampleUser
        user.profile.sex = .female
        return user
    }

    // MARK: - Hosting

    /// Hosts `view` on the small screen at `size` and `style`.
    private func host<V: View>(_ view: V, _ style: UIUserInterfaceStyle, size: DynamicTypeSize) {
        window = nil
        hostedSize = size
        let (_, hosted) = HostedSurface.host(
            view.environment(\.dynamicTypeSize, size), size: screen, settleFor: 1.5, style: style,
            emulatingSafeArea: UIEdgeInsets(top: statusBar, left: 0, bottom: 0, right: 0)
        )
        window = hosted
    }

    private func root() -> UIView? { window?.rootViewController?.view }

    private func labels() -> [String] {
        guard let root = root() else { return [] }
        return AccessibilityTree.labels(in: root)
    }

    /// An element's frame in the hosted window's own coordinates.
    private func frame(of label: String) -> CGRect? {
        guard let root = root(), let origin = window?.frame.origin,
              let frame = AccessibilityTree.element(labeled: label, in: root)?.accessibilityFrame else { return nil }
        return frame.offsetBy(dx: -origin.x, dy: -origin.y)
    }

    private func activate(_ label: String, file: StaticString = #filePath, line: UInt = #line) {
        guard let root = root(), let control = AccessibilityTree.element(labeled: label, in: root) else {
            return XCTFail("no \"\(label)\" control; tree reads \(labels())", file: file, line: line)
        }
        XCTAssertTrue(control.accessibilityActivate(), "\"\(label)\" did not activate", file: file, line: line)
    }

    private func pump(until predicate: () -> Bool, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if predicate() { return true }
            HostedSurface.pump(for: 0.1)
        }
        return predicate()
    }

    private func scrollView() -> UIScrollView? {
        func find(in view: UIView) -> UIScrollView? {
            if let scroll = view as? UIScrollView { return scroll }
            return view.subviews.lazy.compactMap { find(in: $0) }.first
        }
        return root().flatMap { find(in: $0) }
    }

    /// The player's scroll area in the hosted window's coordinates: what shows without scrolling.
    private func visibleScrollArea() -> CGRect? {
        guard let window, let scroll = scrollView() else { return nil }
        return scroll.convert(scroll.bounds, to: window)
    }

    private func scrollPlayerToEnd() {
        guard let scroll = scrollView() else { return }
        let end = max(0, scroll.contentSize.height + scroll.adjustedContentInset.bottom - scroll.bounds.height)
        scroll.setContentOffset(CGPoint(x: 0, y: end), animated: false)
        HostedSurface.pump(for: 0.4)
    }

    private func capture(_ name: String, _ style: UIUserInterfaceStyle) throws {
        guard let root = root() else { return XCTFail("no hosted surface") }
        HostedSurface.pump(for: 0.3)
        let image = HostedSurface.capture(root, size: screen, afterScreenUpdates: true)
        _ = try EvidenceOutput.write(image, named: "\(name).png", for: story)
    }
}
