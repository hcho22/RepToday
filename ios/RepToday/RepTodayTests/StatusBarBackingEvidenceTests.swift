import XCTest
import SwiftUI
import UIKit
@testable import RepToday

/// Content scrolled up past the top of a tab is never drawn under the status bar, where it would sit
/// behind the clock and battery: every scrolling tab (Today, Progress, Profile) and the full-screen
/// session-complete screen is hosted on an iPhone SE
/// (375x667 pt, a 20 pt status bar above, a 49 pt tab bar below), scrolled, and the status-bar band of
/// the rendered screen is read pixel by pixel. It must be nothing but the screen's own background, at the
/// default and the largest text size, in light and dark. The renders land under
/// `artifacts/reports/status-bar-backing/`.
///
/// The system draws the status bar in its own window, so a hosted capture shows the band exactly as the
/// app paints it underneath the clock: plain background is what keeps the clock legible.
@MainActor
final class StatusBarBackingEvidenceTests: XCTestCase {

    private var window: UIWindow?

    override func tearDown() {
        window?.isHidden = true
        window = nil
        super.tearDown()
    }

    private static let screen = CGSize(width: 375, height: 667)
    private static let insets = UIEdgeInsets(top: 20, left: 0, bottom: 49, right: 0)

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 1
        return calendar
    }()

    private var asOf: Date {
        calendar.date(from: DateComponents(year: 2026, month: 7, day: 8, hour: 12))!
    }

    private enum Look: CaseIterable {
        case defaultLight, defaultDark, largestLight, largestDark

        var dynamicTypeSize: DynamicTypeSize {
            switch self {
            case .defaultLight, .defaultDark: return .large
            case .largestLight, .largestDark: return .accessibility5
            }
        }

        var style: UIUserInterfaceStyle {
            switch self {
            case .defaultLight, .largestLight: return .light
            case .defaultDark, .largestDark: return .dark
            }
        }

        var name: String {
            switch self {
            case .defaultLight: return "default-light"
            case .defaultDark: return "default-dark"
            case .largestLight: return "ax5-light"
            case .largestDark: return "ax5-dark"
            }
        }
    }

    // MARK: - Tabs

    func testTodayTabKeepsTheStatusBarClearWhenScrolled() throws {
        let services = ServiceContainer.mock()
        let saved = expectation(description: "a user to build today's session for")
        Task {
            try await services.userService.save(MockPersistence.sampleUser)
            saved.fulfill()
        }
        wait(for: [saved], timeout: 5)

        for look in Look.allCases {
            try assertStatusBarClear(
                ReadyView(services: services), look: look, named: "today-\(look.name)",
                arrive: { root in try self.waitFor("Start", in: root) }
            )
        }
    }

    func testProgressTabKeepsTheStatusBarClearWhenScrolled() async throws {
        for look in Look.allCases {
            let viewModel = ProgressViewModel(
                userService: MockUserService(user: MockPersistence.sampleUser),
                workoutLogService: MockWorkoutLogService(logs: (1...6).map { log(daysAgo: $0 * 2) }),
                exerciseService: try MockExerciseService(),
                subscriptionService: MockSubscriptionService(subscription: .free),
                consistencyService: ConsistencyScoreService(now: { self.asOf }, calendar: calendar),
                now: { self.asOf },
                calendar: calendar
            )
            await viewModel.load()
            try assertStatusBarClear(ProgressTabView(viewModel: viewModel), look: look, named: "progress-\(look.name)")
        }
    }

    /// Profile only scrolls once large text makes it taller than the screen, so the default size has
    /// nothing to scroll under the status bar and is not a case.
    func testProfileTabKeepsTheStatusBarClearWhenScrolled() throws {
        for look in [Look.largestLight, .largestDark] {
            try assertStatusBarClear(
                ProfileTabView().environment(\.services, ServiceContainer.mock()), look: look,
                named: "profile-\(look.name)"
            )
        }
    }

    /// The session-complete screen is a full-screen cover rather than a tab, but it scrolls under the
    /// same status bar: the celebration and summary run past an iPhone SE's screen at either text size.
    func testSessionCompleteScreenKeepsTheStatusBarClearWhenScrolled() throws {
        let exercise = try catalogExercise("push_wall")
        for look in Look.allCases {
            let workout = Workout(
                id: UUID(), createdAt: Date(), shape: .singleFocus, focusPillar: .strength, requestedMinutes: 5,
                wasReturn: false,
                blocks: [WorkoutBlock(id: UUID(), title: "Strength", category: .strength, exercises: [
                    PrescribedExercise(id: UUID(), exercise: exercise, sets: 1, reps: exercise.defaultReps,
                                       durationSeconds: nil, restSeconds: 30)
                ])]
            )
            try assertStatusBarClear(
                ActiveSessionView(workout: workout, user: MockPersistence.sampleUser), look: look,
                named: "session-complete-\(look.name)",
                arrive: { root in
                    try self.waitFor("Done", in: root)
                    let done = try XCTUnwrap(AccessibilityTree.element(labeled: "Done", in: root))
                    XCTAssertTrue(done.accessibilityActivate(), "Done did not activate")
                    try self.waitFor("You showed up. That's the whole game.", in: root)
                }
            )
        }
    }

    // MARK: - Checking the band

    /// Hosts `view` as an iPhone SE in `look`, scrolls it so content passes behind the status bar, and
    /// asserts the status-bar band holds only the background - with the unscrolled and scrolled renders
    /// kept as evidence.
    private func assertStatusBarClear<V: View>(
        _ view: V, look: Look, named name: String, arrive: ((UIView) throws -> Void)? = nil,
        file: StaticString = #filePath, line: UInt = #line
    ) throws {
        // Each look is hosted in a fresh window; the last one is taken off screen first so a capture of
        // this one cannot show it through.
        window?.isHidden = true
        let (_, hostedWindow) = HostedSurface.host(
            view.environment(\.dynamicTypeSize, look.dynamicTypeSize),
            size: Self.screen, style: look.style, emulatingSafeArea: Self.insets
        )
        window = hostedWindow
        let root = try XCTUnwrap(hostedWindow.rootViewController?.view)
        try arrive?(root)

        try EvidenceOutput.write(HostedSurface.capture(root, size: Self.screen, afterScreenUpdates: true),
                                 named: "\(name)-top.png", for: EvidenceOutput.Story.statusBarBacking)

        let scrollView = try XCTUnwrap(primaryScrollView(in: root), "\(name) has no scroll view", file: file, line: line)
        let maxOffset = scrollView.contentSize.height + scrollView.adjustedContentInset.bottom - scrollView.bounds.height
        // Far enough that content has to pass behind the 20 pt band, whatever sits first on the screen.
        let offset = min(maxOffset, 160)
        XCTAssertGreaterThan(offset, Self.insets.top - scrollView.adjustedContentInset.top,
                             "\(name) does not scroll far enough to put content behind the status bar",
                             file: file, line: line)
        scrollView.setContentOffset(CGPoint(x: 0, y: offset - scrollView.adjustedContentInset.top), animated: false)
        HostedSurface.pump(for: 0.4)

        let image = HostedSurface.capture(root, size: Self.screen, afterScreenUpdates: true)
        try EvidenceOutput.write(image, named: "\(name)-scrolled.png", for: EvidenceOutput.Story.statusBarBacking)

        let unexpected = try pixelsUnlikeBackground(in: image, bandHeight: Self.insets.top)
        XCTAssertEqual(unexpected, 0,
                       "\(unexpected) pixels of scrolled content are drawn under the status bar on \(name)",
                       file: file, line: line)
    }

    /// Pumps until VoiceOver's tree carries `label`, failing if it never does.
    private func waitFor(_ label: String, in root: UIView, timeout: TimeInterval = 8) throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !AccessibilityTree.labels(in: root).contains(label), Date() < deadline { HostedSurface.pump(for: 0.1) }
        XCTAssertTrue(AccessibilityTree.labels(in: root).contains(label),
                      "\"\(label)\" never appeared; tree reads \(AccessibilityTree.labels(in: root))")
        HostedSurface.pump(for: 0.5)
    }

    private func catalogExercise(_ id: String) throws -> Exercise {
        let url = try XCTUnwrap(Bundle(for: AppState.self).url(forResource: "Exercises", withExtension: "json"))
        let list = try JSONDecoder().decode([Exercise].self, from: Data(contentsOf: url))
        return try XCTUnwrap(list.first { $0.id == id }, "no \(id) in the catalog")
    }

    /// The tallest scroll view on screen - the tab's own - rather than a horizontal strip inside it (the
    /// Today tab's duration chips).
    private func primaryScrollView(in view: UIView) -> UIScrollView? {
        var found: [UIScrollView] = []
        func walk(_ view: UIView) {
            if let scrollView = view as? UIScrollView { found.append(scrollView) }
            view.subviews.forEach(walk)
        }
        walk(view)
        return found.max { $0.bounds.height < $1.bounds.height }
    }

    /// Counts the pixels in the top `bandHeight` points of `image` that differ from the band's own
    /// top-left corner, which no tab ever draws content into. Anti-aliasing slack is a couple of levels,
    /// far below the contrast of any text or card edge. The band's last pixel row borders whatever has
    /// scrolled up to meet it, and the capture's resampling bleeds a few percent of that row into it
    /// (a 240-level edge reads as 15), so that one row is allowed a faint tint - still far short of
    /// drawn content, which differs by the full contrast of the row below.
    private func pixelsUnlikeBackground(in image: UIImage, bandHeight: CGFloat) throws -> Int {
        let cgImage = try XCTUnwrap(image.cgImage)
        let width = cgImage.width
        let height = Int((bandHeight * image.scale).rounded(.down))
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            // Core Graphics' origin is bottom-left: shift the image so its top rows land in the buffer.
            context.draw(cgImage, in: CGRect(x: 0, y: height - cgImage.height, width: width, height: cgImage.height))
            return true
        }
        XCTAssertTrue(drawn, "could not read the rendered band")

        let reference = Array(pixels[0..<4])
        let boundaryRow = height - 1
        var unlike = 0
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let tolerance = index / (width * 4) == boundaryRow ? 24 : 2
            for channel in 0..<3 where abs(Int(pixels[index + channel]) - Int(reference[channel])) > tolerance {
                unlike += 1
                break
            }
        }
        return unlike
    }

    private func log(daysAgo: Int) -> WorkoutLog {
        WorkoutLog(
            id: UUID(), workoutId: UUID(),
            completedAt: calendar.date(byAdding: .day, value: -daysAgo, to: asOf)!,
            requestedMinutes: 15, durationMinutes: 15, wasReturn: false,
            shape: .singleFocus, focusPillar: .strength, perceivedDifficulty: nil,
            exercises: [
                LoggedExercise(id: UUID(), exerciseId: "squat_bodyweight", pillar: .strength, movementPattern: .squat,
                               completedSets: [CompletedSet(reps: 12, durationSeconds: nil)], skipped: false)
            ]
        )
    }
}
