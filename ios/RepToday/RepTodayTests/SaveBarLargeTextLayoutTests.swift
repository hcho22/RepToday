import XCTest
import SwiftUI
import UIKit
@testable import RepToday

/// Areas to protect and Focus Areas pin Save changes to the bottom of the screen. At the largest text
/// size on an iPhone SE (375x667 pt), with every area staged and a failed save showing, every switch or
/// area, the named change, the error and Save changes itself must each be reachable: brought fully into
/// the part of the screen the pinned bar and the navigation bar leave visible, never covered by the
/// button and never squeezed below the height it has with unlimited room.
@MainActor
final class SaveBarLargeTextLayoutTests: XCTestCase {

    private var window: UIWindow?

    override func tearDown() {
        window = nil
        super.tearDown()
    }

    private static let screen = CGSize(width: 375, height: 667)
    /// Pushed from Settings: a 20 pt status bar above, the 49 pt tab bar below.
    private static let pushedInsets = UIEdgeInsets(top: 20, left: 0, bottom: 49, right: 0)
    /// The coach's sheet on an iPhone SE: shorter than the screen, with no tab bar under it.
    private static let sheetSize = CGSize(width: 375, height: 627)
    private static let sheetInsets = UIEdgeInsets.zero

    private struct SaveFails: Error {}

    /// Reads succeed and writes fail, so a staged save can be shown failing.
    private actor SaveFailingUserService: UserServiceProtocol {
        private let user: User

        init(user: User) { self.user = user }

        func currentUser() async throws -> User? { user }
        func save(_ user: User) async throws { throw SaveFails() }
        func advancePhase(to earnedPhase: Phase, for userId: String) async throws -> User? { throw SaveFails() }
        func deleteCurrentUser() async throws { throw SaveFails() }
    }

    private static var userWithNothingFlagged: User {
        var user = MockPersistence.sampleUser
        user.profile.injuries = []
        user.profile.focusAreas = []
        return user
    }

    private func host<V: View>(_ view: V, size: CGSize, insets: UIEdgeInsets?) throws -> UIView {
        let (_, hostedWindow) = HostedSurface.host(
            view.environment(\.dynamicTypeSize, .accessibility5),
            size: size,
            emulatingSafeArea: insets
        )
        window = hostedWindow
        return try XCTUnwrap(hostedWindow.rootViewController?.view)
    }

    private func firstScrollView(in view: UIView) -> UIScrollView? {
        if let scrollView = view as? UIScrollView { return scrollView }
        return view.subviews.lazy.compactMap { self.firstScrollView(in: $0) }.first
    }

    private func frame(of label: String, in root: UIView) throws -> CGRect {
        try XCTUnwrap(AccessibilityTree.element(labeled: label, in: root),
                      "no \(label) element; tree reads \(AccessibilityTree.labels(in: root))").accessibilityFrame
    }

    /// The part of the scroll view nothing sits over: its frame less the navigation bar above and the
    /// pinned bar below, both of which reach it as its adjusted content inset.
    private func uncoveredRegion(of scrollView: UIScrollView) -> CGRect {
        let frame = scrollView.convert(scrollView.bounds, to: nil)
        let inset = scrollView.adjustedContentInset
        return CGRect(x: frame.minX, y: frame.minY + inset.top,
                      width: frame.width, height: frame.height - inset.top - inset.bottom)
    }

    /// Scrolls just far enough to bring `frame` into the uncovered region, within the scroll view's range.
    private func scroll(_ scrollView: UIScrollView, toReveal frame: CGRect) {
        let region = uncoveredRegion(of: scrollView)
        var offset = scrollView.contentOffset.y
        if frame.maxY > region.maxY { offset += frame.maxY - region.maxY }
        if frame.minY < region.minY { offset -= region.minY - frame.minY }
        let inset = scrollView.adjustedContentInset
        let lowest = -inset.top
        let highest = max(lowest, scrollView.contentSize.height - scrollView.bounds.height + inset.bottom)
        scrollView.setContentOffset(CGPoint(x: 0, y: min(max(offset, lowest), highest)), animated: false)
        HostedSurface.pump(for: 0.3)
    }

    private func assertReachable<V: View>(
        _ labels: [String], button: String, in view: V, size: CGSize, insets: UIEdgeInsets,
        file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let unlimited = try host(view, size: CGSize(width: size.width, height: 4000), insets: nil)
        var natural: [String: CGFloat] = [:]
        for label in labels + [button] {
            natural[label] = try frame(of: label, in: unlimited).height
        }

        let root = try host(view, size: size, insets: insets)
        let scrollView = try XCTUnwrap(firstScrollView(in: root), "the screen should scroll", file: file, line: line)
        let screen = CGRect(origin: .zero, size: size).insetBy(dx: -0.5, dy: -0.5)

        let buttonFrame = try frame(of: button, in: root)
        XCTAssertTrue(screen.contains(buttonFrame), "\(button) at \(buttonFrame) is off the screen", file: file, line: line)
        XCTAssertEqual(buttonFrame.height, natural[button] ?? 0, accuracy: 0.5,
                       "\(button) is squeezed", file: file, line: line)

        for label in labels {
            scroll(scrollView, toReveal: try frame(of: label, in: root))
            let frame = try frame(of: label, in: root)
            let region = uncoveredRegion(of: scrollView).insetBy(dx: -0.5, dy: -0.5)
            XCTAssertTrue(region.contains(frame),
                          "\(label) at \(frame) cannot be brought clear of the bars (visible: \(region))", file: file, line: line)
            XCTAssertLessThanOrEqual(frame.maxY, buttonFrame.minY + 0.5,
                                     "\(label) at \(frame) sits under \(button) at \(buttonFrame)", file: file, line: line)
            XCTAssertEqual(frame.height, natural[label] ?? 0, accuracy: 0.5,
                           "\(label) is squeezed or clipped", file: file, line: line)
        }
    }

    private func injuryScreenWithEverythingStagedAndASaveFailure() async throws -> (InjuryFlagsViewModel, [String]) {
        let viewModel = InjuryFlagsViewModel(userService: SaveFailingUserService(user: Self.userWithNothingFlagged))
        await viewModel.load()
        for area in InjuryOption.allCases { viewModel.set(area, to: true) }
        await viewModel.save()
        let summary = try XCTUnwrap(viewModel.changeSummary)
        let error = try XCTUnwrap(viewModel.errorMessage)
        XCTAssertTrue(viewModel.hasUnsavedChanges)
        return (viewModel, InjuryOption.allCases.map(\.label) + [summary, error])
    }

    func testAreasToProtectPushedFromSettingsKeepsEverythingReachableAtTheLargestTextOnAnIPhoneSE() async throws {
        let (viewModel, labels) = try await injuryScreenWithEverythingStagedAndASaveFailure()
        try assertReachable(
            labels, button: InjuryFlagsCopy.confirm,
            in: NavigationStack { InjuryFlagsView(viewModel: viewModel) },
            size: Self.screen, insets: Self.pushedInsets
        )
    }

    func testAreasToProtectAsTheCoachsSheetKeepsEverythingReachableAtTheLargestTextOnAnIPhoneSE() async throws {
        let (viewModel, labels) = try await injuryScreenWithEverythingStagedAndASaveFailure()
        try assertReachable(
            labels, button: InjuryFlagsCopy.confirm,
            in: NavigationStack { InjuryFlagsView(viewModel: viewModel, preselect: .knees, dismissesOnSave: true) },
            size: Self.sheetSize, insets: Self.sheetInsets
        )
    }

    func testFocusAreasKeepsEverythingReachableAtTheLargestTextOnAnIPhoneSE() async throws {
        let viewModel = FocusAreasViewModel(userService: SaveFailingUserService(user: Self.userWithNothingFlagged))
        await viewModel.load()
        for area in FocusArea.allCases { viewModel.toggle(area) }
        let saved = await viewModel.save()
        XCTAssertFalse(saved)
        XCTAssertEqual(viewModel.errorMessage, FocusAreasCopy.saveFailed)
        try assertReachable(
            FocusArea.allCases.map(\.label) + [FocusAreasCopy.saveFailed], button: FocusAreasCopy.save,
            in: NavigationStack { FocusAreasView(viewModel: viewModel) },
            size: Self.screen, insets: Self.pushedInsets
        )
    }
}
