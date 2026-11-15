import XCTest
import SwiftUI
import UIKit
@testable import RepToday

/// The visual direction on Today, the Welcome Page and onboarding: the wrapping `FlowLayout` the chips
/// use at accessibility sizes, and the layouts that rely on it holding the screen's width at the
/// largest text size on the narrowest phone, with VoiceOver's words unchanged.
@MainActor
final class TodayOnboardingVisualDirectionTests: XCTestCase {

    private func frames(_ labels: [String], in root: UIView) throws -> [CGRect] {
        try labels.map { label in
            try XCTUnwrap(AccessibilityTree.element(labeled: label, in: root), "\(label) missing").accessibilityFrame
        }
    }

    private func block(_ label: String, width: CGFloat) -> some View {
        Color.gray
            .frame(width: width, height: 44)
            .accessibilityElement()
            .accessibilityLabel(label)
    }

    // MARK: - FlowLayout

    func testFlowLayoutFillsALineThenWrapsTheRestOntoTheNext() throws {
        let labels = (0..<5).map { "chip \($0)" }
        let (host, window) = HostedSurface.host(
            FlowLayout(spacing: 8, lineSpacing: 10) {
                ForEach(labels, id: \.self) { self.block($0, width: 100) }
            }
            .frame(width: 335)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading),
            size: CGSize(width: 335, height: 400)
        )
        defer { withExtendedLifetime(window) {} }
        let rects = try frames(labels, in: host.view)

        // Three 100 pt chips and two 8 pt gaps fit 335 pt; the fourth starts the next line.
        XCTAssertEqual(rects[0].minY, rects[2].minY, accuracy: 0.5)
        XCTAssertEqual(rects[1].minX - rects[0].maxX, 8, accuracy: 0.5)
        XCTAssertEqual(rects[3].minX, rects[0].minX, accuracy: 0.5, "the next line starts at the leading edge")
        XCTAssertEqual(rects[3].minY - rects[0].maxY, 10, accuracy: 0.5, "lines sit lineSpacing apart")
        XCTAssertEqual(rects[4].minY, rects[3].minY, accuracy: 0.5)
    }

    func testFlowLayoutGivesAChildWiderThanTheLineTheWholeLine() throws {
        let (host, window) = HostedSurface.host(
            FlowLayout {
                self.block("narrow", width: 80)
                Text("A label far too long to sit on one line of a narrow column at all")
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("wide")
            }
            .frame(width: 200)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading),
            size: CGSize(width: 200, height: 600)
        )
        defer { withExtendedLifetime(window) {} }
        let rects = try frames(["narrow", "wide"], in: host.view)

        XCTAssertGreaterThan(rects[1].minY, rects[0].maxY, "the wide child moves to its own line")
        XCTAssertLessThanOrEqual(rects[1].width, 200.5, "and wraps inside it rather than running off")
    }

    // MARK: - Today at the largest text size

    private func services() -> ServiceContainer {
        let services = ServiceContainer.mock()
        let saved = expectation(description: "a user to build today's session for")
        Task {
            try await services.userService.save(MockPersistence.sampleUser)
            saved.fulfill()
        }
        wait(for: [saved], timeout: 5)
        return services
    }

    private func waitFor(_ label: String, in root: UIView, timeout: TimeInterval = 8) {
        let deadline = Date().addingTimeInterval(timeout)
        while AccessibilityTree.element(labeled: label, in: root) == nil, Date() < deadline {
            HostedSurface.pump(for: 0.1)
        }
        HostedSurface.pump(for: 0.3)
    }

    func testTodayWrapsItsDurationChipsInsideANarrowScreenAtTheLargestTextSize() throws {
        let size = CGSize(width: 375, height: 3600)
        let (host, window) = HostedSurface.host(
            ReadyView(services: services()).environment(\.dynamicTypeSize, .accessibility5), size: size
        )
        defer { withExtendedLifetime(window) {} }
        let root = host.view!
        waitFor("5 minute session", in: root)

        let chips = try frames(["5", "10", "15", "20", "30", "45", "60"].map { "\($0) minute session" }, in: root)
        for chip in chips {
            XCTAssertGreaterThanOrEqual(chip.minX, window.frame.minX, "a chip runs off the leading edge")
            XCTAssertLessThanOrEqual(chip.maxX, window.frame.maxX, "a chip runs off the trailing edge")
            XCTAssertGreaterThanOrEqual(chip.height, Theme.Spacing.minTouchTarget - 0.01)
        }
        XCTAssertGreaterThan(Set(chips.map { Int($0.minY.rounded()) }).count, 1, "the chips wrap onto more lines")
    }

    func testTodaysHeadlineStillReadsAsDayAndLength() throws {
        let (host, window) = HostedSurface.host(ReadyView(services: services()), size: CGSize(width: 402, height: 1600))
        defer { withExtendedLifetime(window) {} }
        let root = host.view!
        waitFor("5 minute session", in: root)

        let headline = AccessibilityTree.element(whereLabel: { label in
            TrainingDay.allCases.contains { label.hasPrefix("\($0.displayName): ") } && label.hasSuffix(" min")
        }, in: root)
        XCTAssertNotNil(headline, "VoiceOver reads the two-line headline as \"<Day>: <n> min\": \(AccessibilityTree.labels(in: root))")
        XCTAssertTrue(headline?.accessibilityTraits.contains(.staticText) ?? false)
    }

    // MARK: - Onboarding at the largest text size

    func testTheSexChoiceStacksAndStaysInsideTheScreenAtTheLargestTextSize() throws {
        let viewModel = OnboardingViewModel(
            userService: MockUserService(),
            sessionPolicyService: MockSessionPolicyService()
        )
        viewModel.advance()
        XCTAssertEqual(viewModel.step, .basics)
        let (host, window) = HostedSurface.host(
            OnboardingView(viewModel: viewModel).environment(\.dynamicTypeSize, .accessibility5),
            size: CGSize(width: 375, height: 2400)
        )
        defer { withExtendedLifetime(window) {} }
        let root = host.view!
        waitFor("Female", in: root)

        let segments = try frames(["Male", "Female", "Other"], in: root)
        for segment in segments {
            XCTAssertGreaterThanOrEqual(segment.minX, window.frame.minX)
            XCTAssertLessThanOrEqual(segment.maxX, window.frame.maxX)
        }
        XCTAssertLessThan(segments[0].maxY, segments[1].minY + 0.5, "the segments stack at accessibility sizes")
    }
}
