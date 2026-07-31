import XCTest
import SwiftUI
@testable import RepToday

/// Evidence for the imperial basics step as the user actually meets it (US-O04).
///
/// The production `OnboardingView` is hosted in a real key window and driven to its basics step, so
/// the strings asserted here are the ones on screen and the ones VoiceOver speaks - not a
/// reimplementation of the layout. Three things are gated together because they are the same change:
/// the read-out is imperial, the spoken value is a sentence rather than an abbreviation, and no
/// metric unit survives anywhere on the step. A regression in any one of them is exactly the failure
/// this story exists to prevent (a cm slider re-appearing, or a "5 ft 7 in" that VoiceOver reads as
/// "5 ft 7 in").
///
/// The render is written to a per-run temporary directory unless `REPTODAY_WRITE_EVIDENCE=1` /
/// `REPTODAY_EVIDENCE_DIR` redirect it, matching `PerSideSwapEvidenceTests`, so a plain test run
/// never dirties the worktree.
@MainActor
final class OnboardingBasicsEvidenceTests: XCTestCase {

    private static let evidenceRoot: String = {
        let environment = ProcessInfo.processInfo.environment
        if let override = environment["REPTODAY_EVIDENCE_DIR"], !override.isEmpty { return override }
        if environment["REPTODAY_WRITE_EVIDENCE"] == "1" {
            return URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent() // RepTodayTests
                .deletingLastPathComponent() // RepToday
                .deletingLastPathComponent() // ios
                .deletingLastPathComponent() // the repo root
                .appendingPathComponent("artifacts")
                .appendingPathComponent("reports")
                .appendingPathComponent("us-o04")
                .path
        }
        return FileManager.default.temporaryDirectory
            .appendingPathComponent("RepTodayEvidence")
            .appendingPathComponent(UUID().uuidString)
            .path
    }()

    private let screenSize = CGSize(width: 393, height: 852)

    /// Held for the test's lifetime - a released window takes the hosted view down with it.
    private var renderWindow: UIWindow?

    // MARK: - Fixtures

    /// The production onboarding view, parked on the basics step with a name already typed (so the
    /// step reads the way it does once the user has answered the field above the measurements).
    private func basicsStep() -> OnboardingView {
        let viewModel = OnboardingViewModel(
            userService: MockUserService(),
            sessionPolicyService: MockSessionPolicyService()
        )
        viewModel.displayName = "Riley"
        while viewModel.step != .basics { viewModel.advance() }
        return OnboardingView(viewModel: viewModel)
    }

    // MARK: - What the step says and speaks

    func testBasicsStepReadsImperialAndSpeaksItAsASentence() throws {
        let host = hosted(basicsStep(), size: screenSize)
        let labels = accessibilityLabels(in: host.view)
        let values = accessibilityValues(in: host.view)

        print("=== Rep Today - onboarding basics, VoiceOver ===")
        for (label, value) in zip(labels, values) where !label.isEmpty {
            print("- \(label)\(value.map { ": \($0)" } ?? "")")
        }

        // Each row is named once and speaks its value as a sentence, with every noun agreeing with
        // its own count. The screen's own read-out stays terse ("5 ft 8 in") and is deliberately not
        // what VoiceOver reads - spoken, those abbreviations come out as letters.
        XCTAssertEqual(
            value(of: "Height", in: host.view), "5 feet 8 inches",
            "VoiceOver must speak the height as words, not the \"ft\"/\"in\" abbreviations; "
            + "the step reads \(labels)"
        )
        XCTAssertEqual(
            value(of: "Weight", in: host.view), "175 pounds",
            "the weight is not spoken as words; the step reads \(labels)"
        )

        // No metric unit survives anywhere on the step - the regression this story prevents.
        for reading in labels + values.compactMap({ $0 }) {
            XCTAssertFalse(
                reading.contains(" cm") || reading.contains(" kg"),
                "the basics step still speaks a metric unit: \"\(reading)\""
            )
        }
    }

    /// Every measurement row claims the app's 44pt minimum touch target, asserted on the laid-out
    /// frame rather than assumed from the source.
    ///
    /// Both controls this step has carried fail it: a bare `Slider` lays out at 20pt and a platform
    /// `Stepper`'s halves at 46.5 x 32pt, under the floor in the dimension a thumb is least accurate
    /// in. Age is measured alongside the two imperial rows because it shares the row - the fix is not
    /// specific to the units.
    func testMeasurementRowsMeetTheMinimumTouchTarget() throws {
        let host = hosted(basicsStep(), size: screenSize)

        for name in ["Age", "Height", "Weight"] {
            let element = try XCTUnwrap(
                accessibilityElement(labeledWithPrefix: name, in: host.view),
                "no \(name) control on the basics step"
            )
            XCTAssertGreaterThanOrEqual(
                element.accessibilityFrame.height, Theme.Spacing.minTouchTarget,
                "the \(name) row is \(element.accessibilityFrame.height)pt tall, under the 44pt floor"
            )
        }
    }

    /// The rows are *adjustable* to VoiceOver - one element that reads its value and moves on a
    /// swipe, rather than two unlabeled buttons - and the adjustment moves by that row's own step.
    func testMeasurementRowsAreAdjustableByTheirOwnStep() throws {
        let host = hosted(basicsStep(), size: screenSize)

        let height = try XCTUnwrap(accessibilityElement(labeledWithPrefix: "Height", in: host.view))
        XCTAssertTrue(
            height.accessibilityTraits.contains(.adjustable),
            "the height row is not an adjustable value control"
        )
        height.accessibilityIncrement()
        settle(host)
        XCTAssertEqual(
            accessibilityElement(labeledWithPrefix: "Height", in: host.view)?.accessibilityValue,
            "5 feet 9 inches",
            "one increment must move the height by a single inch"
        )

        let weight = try XCTUnwrap(accessibilityElement(labeledWithPrefix: "Weight", in: host.view))
        XCTAssertTrue(weight.accessibilityTraits.contains(.adjustable))
        weight.accessibilityDecrement()
        settle(host)
        XCTAssertEqual(
            accessibilityElement(labeledWithPrefix: "Weight", in: host.view)?.accessibilityValue,
            "170 pounds",
            "one decrement must move the weight by its 5lb step"
        )
    }

    /// The reviewable artifact: the step as it is drawn, at the default type size and at the largest
    /// accessibility one - the measurement row lays its name, value, and buttons out on a single
    /// line, so an accessibility type size is exactly where it would overflow.
    func testRenderBasicsStep() throws {
        try renderBasicsStep(at: .large, on: screenSize, named: "onboarding-basics-imperial.png")
        // At AX5 the step is taller than a phone, so it is captured on a canvas the whole scrolling
        // content fits: the width - where the row would overflow - is the device's either way.
        try renderBasicsStep(
            at: .accessibility5,
            on: CGSize(width: screenSize.width, height: 1800),
            named: "onboarding-basics-imperial-ax5.png"
        )
    }

    private func renderBasicsStep(at size: DynamicTypeSize, on canvas: CGSize, named fileName: String) throws {
        let host = hosted(basicsStep().dynamicTypeSize(size), size: canvas)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        let renderer = UIGraphicsImageRenderer(size: canvas, format: format)
        let image = renderer.image { ctx in host.view.layer.render(in: ctx.cgContext) }
        let data = try XCTUnwrap(image.pngData())

        try FileManager.default.createDirectory(
            atPath: Self.evidenceRoot, withIntermediateDirectories: true
        )
        let path = (Self.evidenceRoot as NSString).appendingPathComponent(fileName)
        try data.write(to: URL(fileURLWithPath: path))
        XCTAssertGreaterThan(data.count, 8000, "rendered PNG unexpectedly small - the step may not have drawn")
        print("SNAPSHOT_WRITTEN \(path) bytes=\(data.count)")
    }

    // MARK: - Hosting & accessibility-tree helpers

    private func hosted<V: View>(_ view: V, size: CGSize) -> UIHostingController<V> {
        let host = UIHostingController(rootView: view)
        host.overrideUserInterfaceStyle = .dark
        host.view.frame = CGRect(origin: .zero, size: size)

        let window = UIWindow(frame: host.view.frame)
        window.rootViewController = host
        window.makeKeyAndVisible()
        renderWindow = window
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()

        let deadline = Date().addingTimeInterval(1.5)
        while Date() < deadline {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        return host
    }

    /// Lets SwiftUI re-run its layout and rebuild the accessibility tree after the view was driven.
    private func settle(_ host: UIViewController) {
        let deadline = Date().addingTimeInterval(0.6)
        while Date() < deadline {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
    }

    /// SwiftUI only builds its accessibility tree once an assistive client is attached, so the walk
    /// below has to ask for one first - otherwise it silently reports an empty screen.
    private func attachAssistiveClient() {
        _ = UIApplication.shared.accessibilityActivate()
        UIAccessibility.post(notification: .screenChanged, argument: nil)
        RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.5))
    }

    private func walkElements(in root: UIView, _ visit: (NSObject) -> Void) {
        attachAssistiveClient()
        var visited = Set<ObjectIdentifier>()

        func walk(_ node: NSObject) {
            guard visited.insert(ObjectIdentifier(node)).inserted else { return }
            if node.isAccessibilityElement { visit(node) }
            let count = node.accessibilityElementCount()
            if count != NSNotFound {
                for index in 0..<count {
                    if let child = node.accessibilityElement(at: index) as? NSObject { walk(child) }
                }
            }
            if let view = node as? UIView { view.subviews.forEach(walk) }
        }

        walk(root)
    }

    private func accessibilityLabels(in root: UIView) -> [String] {
        var labels: [String] = []
        walkElements(in: root) { labels.append($0.accessibilityLabel ?? "") }
        return labels
    }

    private func accessibilityValues(in root: UIView) -> [String?] {
        var values: [String?] = []
        walkElements(in: root) { values.append($0.accessibilityValue) }
        return values
    }

    /// The first element whose label starts with `prefix` - a stepper composes its label out of its
    /// whole row ("Height, 5 feet 8 inches, Increment"), so it is named by how it opens.
    private func accessibilityElement(labeledWithPrefix prefix: String, in root: UIView) -> NSObject? {
        var found: NSObject?
        walkElements(in: root) { node in
            if found == nil, node.accessibilityLabel?.hasPrefix(prefix) == true { found = node }
        }
        return found
    }

    private func value(of label: String, in root: UIView) -> String? {
        accessibilityElement(labeledWithPrefix: label, in: root)?.accessibilityValue
    }
}
