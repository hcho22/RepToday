import XCTest
import SwiftUI
import UIKit
@testable import RepToday

/// A count's noun agrees with the count - "1 session", "0 sessions", "3 sessions" - in `CountWording`,
/// on the Progress tab's count copy that reads through it, both on screen and to VoiceOver, and in the
/// remaining time a session's countdown ring speaks.
@MainActor
final class CountWordingTests: XCTestCase {

    // MARK: - CountWording

    func testZeroTakesThePlural() {
        XCTAssertEqual(CountWording.noun(for: 0, singular: "session", plural: "sessions"), "sessions")
        XCTAssertEqual(CountWording.phrase(0, singular: "minute moved", plural: "minutes moved"), "0 minutes moved")
    }

    func testOneTakesTheSingular() {
        XCTAssertEqual(CountWording.noun(for: 1, singular: "session", plural: "sessions"), "session")
        XCTAssertEqual(CountWording.phrase(1, singular: "minute moved", plural: "minutes moved"), "1 minute moved")
    }

    func testManyTakesThePlural() {
        XCTAssertEqual(CountWording.noun(for: 2, singular: "session", plural: "sessions"), "sessions")
        XCTAssertEqual(CountWording.phrase(45, singular: "minute moved", plural: "minutes moved"), "45 minutes moved")
    }

    // MARK: - Progress tab

    private var window: UIWindow?

    override func tearDown() {
        window = nil
        super.tearDown()
    }

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 1
        return calendar
    }()

    private var asOf: Date {
        calendar.date(from: DateComponents(year: 2026, month: 7, day: 8, hour: 12))!
    }

    /// A completed session of `minutes`, logging one push-up set of `reps`.
    private func log(daysAgo: Int, minutes: Int, reps: Int) -> WorkoutLog {
        WorkoutLog(
            id: UUID(), workoutId: UUID(),
            completedAt: calendar.date(byAdding: .day, value: -daysAgo, to: asOf)!,
            requestedMinutes: minutes, durationMinutes: minutes, wasReturn: false,
            shape: .singleFocus, focusPillar: .strength, perceivedDifficulty: nil,
            exercises: [
                LoggedExercise(id: UUID(), exerciseId: "push_wall", pillar: .strength, movementPattern: .push,
                               completedSets: [CompletedSet(reps: reps, durationSeconds: nil)], skipped: false)
            ]
        )
    }

    /// Hosts the production Progress tab over `logs` and returns its accessibility labels.
    private func progressLabels(for logs: [WorkoutLog]) async throws -> [String] {
        let viewModel = ProgressViewModel(
            userService: MockUserService(user: MockPersistence.sampleUser),
            workoutLogService: MockWorkoutLogService(logs: logs),
            exerciseService: try MockExerciseService(),
            subscriptionService: MockSubscriptionService(subscription: .free),
            consistencyService: ConsistencyScoreService(now: { self.asOf }, calendar: calendar),
            now: { self.asOf },
            calendar: calendar
        )
        await viewModel.load()
        let (_, hostedWindow) = HostedSurface.host(ProgressTabView(viewModel: viewModel),
                                                   size: CGSize(width: 393, height: 3400))
        window = hostedWindow
        let root = try XCTUnwrap(hostedWindow.rootViewController?.view)
        return AccessibilityTree.labels(in: root)
    }

    private func assertContains(_ labels: [String], _ needle: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(labels.contains { $0.contains(needle) }, "expected '\(needle)'; tree reads \(labels)",
                      file: file, line: line)
    }

    func testOneSessionReadsSingularOnTheProgressTab() async throws {
        let labels = try await progressLabels(for: [log(daysAgo: 1, minutes: 1, reps: 1)])

        assertContains(labels, "1 session, 1 minute moved.")
        assertContains(labels, "1, session logged")
        assertContains(labels, "1 rep, best set")
        for flaw in ["1 sessions", "1 minutes", "1 reps", "1, sessions logged"] {
            XCTAssertFalse(labels.contains { $0.contains(flaw) }, "'\(flaw)' should not appear; tree reads \(labels)")
        }
    }

    func testManySessionsReadPluralOnTheProgressTab() async throws {
        let logs = (1...3).map { log(daysAgo: $0, minutes: 15, reps: 12) }
        let labels = try await progressLabels(for: logs)

        assertContains(labels, "3 sessions, 45 minutes moved.")
        assertContains(labels, "3, sessions logged")
        assertContains(labels, "12 reps, best set")
    }

    // MARK: - Countdown ring

    /// Every countdown the player shows speaks its last second in the singular, and any other count in
    /// the plural - read off the real ring's accessibility element, the value VoiceOver reads on demand.
    func testCountdownRingSpeaksOneSecondInTheSingular() throws {
        let names = ["Hold", "Work window", "Rest", "Switch sides"]
        let (_, hostedWindow) = HostedSurface.host(
            VStack(spacing: Theme.Spacing.sm) {
                ForEach(names, id: \.self) { name in
                    CountdownRing(remaining: 1, fraction: 0.05, name: name, diameter: CountdownRing.compactDiameter)
                }
                CountdownRing(remaining: 2, fraction: 0.1, name: "Rest", diameter: CountdownRing.compactDiameter)
                CountdownRing(remaining: 0, fraction: 0, name: "Hold", diameter: CountdownRing.compactDiameter)
            },
            size: CGSize(width: 393, height: 852)
        )
        window = hostedWindow
        let labels = AccessibilityTree.labels(in: try XCTUnwrap(hostedWindow.rootViewController?.view))

        for name in names {
            XCTAssertTrue(labels.contains("\(name), 1 second remaining"), "the \(name) ring should read one second; tree reads \(labels)")
        }
        XCTAssertTrue(labels.contains("Rest, 2 seconds remaining"), "tree reads \(labels)")
        XCTAssertTrue(labels.contains("Hold, 0 seconds remaining"), "tree reads \(labels)")
        XCTAssertFalse(labels.contains { $0.contains("1 seconds") }, "'1 seconds' should not appear; tree reads \(labels)")
    }
}
