import XCTest
import SwiftUI
import UIKit
@testable import RepToday

/// Areas to protect and Focus Areas pin Save changes to the bottom of the screen, with what the last save
/// did (the Saved line or the error) right above it. At the largest text size on an iPhone SE (375x667 pt),
/// with every area staged, that result must be on screen above the button as soon as it appears, without
/// scrolling, and the pinned block must still leave room to scroll every switch or area (and, on Areas to
/// protect, the named change, which joins the scrolling column at these sizes) clear of the bars - whole,
/// or top and then bottom for one taller than that room.
/// Nothing is squeezed below the height it has with unlimited room.
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

    /// Hosts the view `makeView` builds (once with unlimited room, once on the phone), lets `afterHosting` drive it (a tap on Save changes, say), and checks the layout:
    /// every `pinned` label is fully on screen above `button` without scrolling, and every `scrolled` label
    /// can be brought clear of the navigation bar and the pinned block, with nothing squeezed.
    private func assertLayout<V: View>(
        scrolled: [String], pinned: [String], button: String, in makeView: () async -> V, size: CGSize, insets: UIEdgeInsets,
        afterHosting: (UIView) async throws -> Void = { _ in },
        file: StaticString = #filePath, line: UInt = #line
    ) async throws {
        let unlimited = try host(await makeView(), size: CGSize(width: size.width, height: 4000), insets: nil)
        try await afterHosting(unlimited)
        var natural: [String: CGFloat] = [:]
        for label in scrolled + pinned + [button] {
            natural[label] = try frame(of: label, in: unlimited).height
        }

        let root = try host(await makeView(), size: size, insets: insets)
        try await afterHosting(root)
        let scrollView = try XCTUnwrap(firstScrollView(in: root), "the screen should scroll", file: file, line: line)
        let screen = CGRect(origin: .zero, size: size).insetBy(dx: -0.5, dy: -0.5)

        let buttonFrame = try frame(of: button, in: root)
        XCTAssertTrue(screen.contains(buttonFrame), "\(button) at \(buttonFrame) is off the screen", file: file, line: line)
        XCTAssertEqual(buttonFrame.height, natural[button] ?? 0, accuracy: 0.5,
                       "\(button) is squeezed", file: file, line: line)

        for label in pinned {
            let frame = try frame(of: label, in: root)
            XCTAssertTrue(screen.contains(frame), "\(label) at \(frame) is not on screen without scrolling", file: file, line: line)
            XCTAssertGreaterThanOrEqual(frame.minY, uncoveredRegion(of: scrollView).maxY - 0.5,
                                        "\(label) at \(frame) is not in the pinned block", file: file, line: line)
            XCTAssertLessThanOrEqual(frame.maxY, buttonFrame.minY + 0.5,
                                     "\(label) at \(frame) is not above \(button) at \(buttonFrame)", file: file, line: line)
            XCTAssertEqual(frame.height, natural[label] ?? 0, accuracy: 0.5,
                           "\(label) is squeezed or clipped", file: file, line: line)
        }

        for label in scrolled {
            let start = try frame(of: label, in: root)
            XCTAssertEqual(start.height, natural[label] ?? 0, accuracy: 0.5,
                           "\(label) is squeezed or clipped", file: file, line: line)
            // One taller than the space the bars leave is scrolled through: its top, then its bottom.
            let edges = start.height <= uncoveredRegion(of: scrollView).height
                ? [(name: "whole", reveal: { (frame: CGRect) in frame })]
                : [(name: "top", reveal: { (frame: CGRect) in CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: 1) }),
                   (name: "bottom", reveal: { (frame: CGRect) in CGRect(x: frame.minX, y: frame.maxY - 1, width: frame.width, height: 1) })]
            for edge in edges {
                scroll(scrollView, toReveal: edge.reveal(try frame(of: label, in: root)))
                let shown = edge.reveal(try frame(of: label, in: root))
                let region = uncoveredRegion(of: scrollView).insetBy(dx: -0.5, dy: -0.5)
                XCTAssertTrue(region.contains(shown),
                              "\(label)'s \(edge.name) at \(shown) cannot be brought clear of the bars (visible: \(region))",
                              file: file, line: line)
                XCTAssertLessThanOrEqual(shown.maxY, buttonFrame.minY + 0.5,
                                         "\(label)'s \(edge.name) at \(shown) sits under \(button) at \(buttonFrame)",
                                         file: file, line: line)
            }
        }
    }

    private func injuryScreenWithEverythingStaged(savingTo userService: any UserServiceProtocol) async -> InjuryFlagsViewModel {
        let viewModel = InjuryFlagsViewModel(userService: userService)
        await viewModel.load()
        for area in InjuryOption.allCases { viewModel.set(area, to: true) }
        await viewModel.save()
        return viewModel
    }

    private func injuryScreenAfterAFailedSave() async throws -> (InjuryFlagsViewModel, scrolled: [String]) {
        let viewModel = await injuryScreenWithEverythingStaged(
            savingTo: SaveFailingUserService(user: Self.userWithNothingFlagged))
        XCTAssertEqual(viewModel.errorMessage, InjuryFlagsViewModel.saveFailureMessage)
        XCTAssertTrue(viewModel.hasUnsavedChanges)
        let summary = try XCTUnwrap(viewModel.changeSummary)
        return (viewModel, InjuryOption.allCases.map(\.label) + [summary])
    }

    func testAreasToProtectPushedFromSettingsAfterAFailedSaveAtTheLargestTextOnAnIPhoneSE() async throws {
        let (viewModel, scrolled) = try await injuryScreenAfterAFailedSave()
        try await assertLayout(
            scrolled: scrolled, pinned: [InjuryFlagsViewModel.saveFailureMessage], button: InjuryFlagsCopy.confirm,
            in: { NavigationStack { InjuryFlagsView(viewModel: viewModel) } },
            size: Self.screen, insets: Self.pushedInsets
        )
    }

    func testAreasToProtectAsTheCoachsSheetAfterAFailedSaveAtTheLargestTextOnAnIPhoneSE() async throws {
        let (viewModel, scrolled) = try await injuryScreenAfterAFailedSave()
        try await assertLayout(
            scrolled: scrolled, pinned: [InjuryFlagsViewModel.saveFailureMessage], button: InjuryFlagsCopy.confirm,
            in: { NavigationStack { InjuryFlagsView(viewModel: viewModel, preselect: .knees, dismissesOnSave: true) } },
            size: Self.sheetSize, insets: Self.sheetInsets
        )
    }

    func testAreasToProtectPushedFromSettingsAfterASuccessfulSaveAtTheLargestTextOnAnIPhoneSE() async throws {
        let viewModel = await injuryScreenWithEverythingStaged(savingTo: MockUserService(user: Self.userWithNothingFlagged))
        XCTAssertTrue(viewModel.didSave)
        try await assertLayout(
            scrolled: InjuryOption.allCases.map(\.label), pinned: [InjuryFlagsCopy.saved], button: InjuryFlagsCopy.confirm,
            in: { NavigationStack { InjuryFlagsView(viewModel: viewModel) } },
            size: Self.screen, insets: Self.pushedInsets
        )
    }

    private func focusScreenWithEverythingStaged(savingTo userService: any UserServiceProtocol) async -> FocusAreasViewModel {
        let viewModel = FocusAreasViewModel(userService: userService)
        await viewModel.load()
        for area in FocusArea.allCases { viewModel.toggle(area) }
        return viewModel
    }

    func testFocusAreasAfterAFailedSaveAtTheLargestTextOnAnIPhoneSE() async throws {
        let viewModel = await focusScreenWithEverythingStaged(
            savingTo: SaveFailingUserService(user: Self.userWithNothingFlagged))
        let saved = await viewModel.save()
        XCTAssertFalse(saved)
        XCTAssertEqual(viewModel.errorMessage, FocusAreasCopy.saveFailed)
        try await assertLayout(
            scrolled: FocusArea.allCases.map(\.label), pinned: [FocusAreasCopy.saveFailed], button: FocusAreasCopy.save,
            in: { NavigationStack { FocusAreasView(viewModel: viewModel) } },
            size: Self.screen, insets: Self.pushedInsets
        )
    }

    /// The Saved line is the screen's own state, set when its Save changes lands, so the save is tapped
    /// on the hosted screen, the way VoiceOver would.
    func testFocusAreasAfterASuccessfulSaveAtTheLargestTextOnAnIPhoneSE() async throws {
        let user = Self.userWithNothingFlagged
        try await assertLayout(
            scrolled: FocusArea.allCases.map(\.label), pinned: [FocusAreasCopy.saved], button: FocusAreasCopy.save,
            in: {
                let viewModel = await self.focusScreenWithEverythingStaged(savingTo: MockUserService(user: user))
                return NavigationStack { FocusAreasView(viewModel: viewModel) }
            },
            size: Self.screen, insets: Self.pushedInsets,
            afterHosting: { root in
                let save = try XCTUnwrap(AccessibilityTree.element(labeled: FocusAreasCopy.save, in: root))
                _ = save.accessibilityActivate()
                try await HostedSurface.settle(until: {
                    AccessibilityTree.element(labeled: FocusAreasCopy.saved, in: root) != nil
                })
            }
        )
    }
}
