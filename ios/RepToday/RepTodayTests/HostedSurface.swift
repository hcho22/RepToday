import SwiftUI
import UIKit

/// The one place that hosts a production SwiftUI surface in a real key window and lets it settle, so
/// that whatever a test reads next - the pixels or the accessibility tree - comes off a view that has
/// actually laid out and drawn.
///
/// Hosting is worth sharing because getting it wrong fails silently rather than loudly: a surface read
/// before SwiftUI has finished its asynchronous layout and draw passes captures a blank image or an
/// empty accessibility tree, and the assertions over it pass on a screen that shows and says nothing.
/// Every evidence suite therefore hosts through `host(_:size:)` instead of carrying its own preamble,
/// so there is one settling policy rather than one per suite.
///
/// `OnboardingBasicsEvidenceTests` is the one suite that has not adopted it: it still builds its own
/// hosting controller, window, pump and accessibility lookup, captures at `format.scale = 2` rather
/// than `captureScale`, and resolves `REPTODAY_EVIDENCE_DIR` verbatim instead of through
/// `EvidenceOutput.directory(for:)`. That divergence is owed work, not a sanctioned second policy -
/// its scope is recorded under "Owed work" in `docs/implementation-log.md`.
@MainActor
enum HostedSurface {

    /// How long a freshly hosted surface is given to finish its asynchronous layout, draw and `.task`
    /// work. Deliberately generous: it is a ceiling for a loaded machine, not a target.
    ///
    /// `nonisolated` because `host(_:size:settleFor:)` uses it as a default argument, and a default
    /// argument expression is evaluated in the caller's context rather than the callee's isolation -
    /// an error in the Swift 6 language mode. An immutable `Sendable` constant is safe to read from
    /// anywhere, so opting it out of the enum's `@MainActor` isolation costs nothing.
    nonisolated static let settleInterval: TimeInterval = 2.5

    /// Hosts `view` at `size` in a real key window and returns it laid out, drawn and settled.
    ///
    /// The window is handed back rather than kept here because a released window takes the hosted view
    /// down with it: the caller has to hold it for as long as the surface is read.
    static func host<V: View>(
        _ view: V, size: CGSize, settleFor interval: TimeInterval = settleInterval
    ) -> (host: UIHostingController<V>, window: UIWindow) {
        let host = UIHostingController(rootView: view)
        host.overrideUserInterfaceStyle = .dark
        host.view.frame = CGRect(origin: .zero, size: size)

        // A real key window is what makes the view lay out and draw its layers at all; sizing the
        // window to the full content height lays out the whole of a scrolling surface rather than
        // just the screenful that would be visible.
        let window = UIWindow(frame: host.view.frame)
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()

        pump(for: interval)

        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        return (host, window)
    }

    /// The scale every committed evidence PNG is captured at. It lives here, in the one place that
    /// composites a hosted surface, so two suites' baselines cannot silently diverge on it.
    static let captureScale: CGFloat = 3

    /// Composites a hosted surface's whole layer tree to an image at `captureScale`.
    ///
    /// `layer.render(in:)` draws from the layer tree offscreen, so it captures content past the
    /// physical screen bounds - unlike `drawHierarchy(afterScreenUpdates:)`, which is limited to what
    /// is actually on screen. `size` is the region composited: a hosted surface cropped to its measured
    /// content simply drops the empty tail below it, because nothing above the crop moves.
    static func capture(_ view: UIView, size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = captureScale
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { ctx in view.layer.render(in: ctx.cgContext) }
    }

    /// Spins the main run loop for `interval`.
    ///
    /// `RunLoop.run(mode:before:)` returns as soon as it has processed a single input source, so one
    /// call is a *turn* of the run loop and not a wait. Settling therefore has to be a loop against a
    /// deadline; a lone call hands back control the moment any event fires, which is how a surface
    /// gets read half-drawn and a test passes locally and fails under load.
    static func pump(for interval: TimeInterval) {
        let deadline = Date().addingTimeInterval(interval)
        while Date() < deadline {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
    }
}

/// Reads the accessibility tree of a hosted surface: what VoiceOver would speak, and the elements it
/// would activate.
///
/// SwiftUI only builds its accessibility tree once an assistive client is attached, so a test process
/// has to ask for one first; without the activation below the hierarchy comes back empty and an
/// assertion over it silently passes on a screen that speaks nothing at all.
///
/// Reading stays cheap on purpose. Settling is `HostedSurface.host(_:size:)`'s job, and these are also
/// called from tight polling loops driving a live surface - a fixed wait per read would step straight
/// past the state the loop is waiting for.
@MainActor
enum AccessibilityTree {

    /// Every accessibility label in `root`, in traversal order - the strings VoiceOver reads as the
    /// user swipes down the screen.
    static func labels(in root: UIView) -> [String] {
        activate()

        var labels: [String] = []
        walk(root) { node in
            if node.isAccessibilityElement, let label = node.accessibilityLabel {
                labels.append(label)
            }
            return true
        }
        return labels
    }

    /// Every string VoiceOver would speak in `root` - each element's label *and* its hint, in
    /// traversal order.
    ///
    /// `labels(in:)` cannot answer "is this sentence announced once?", because a sentence attached
    /// to one element as a label and to another as a hint is spoken twice while appearing once in
    /// the labels. Counting over both is what makes that duplication assertable.
    static func spokenStrings(in root: UIView) -> [String] {
        activate()

        var spoken: [String] = []
        walk(root) { node in
            guard node.isAccessibilityElement else { return true }
            if let label = node.accessibilityLabel { spoken.append(label) }
            if let hint = node.accessibilityHint { spoken.append(hint) }
            return true
        }
        return spoken
    }

    /// The element carrying `label`, so a test can activate it exactly the way VoiceOver's double-tap
    /// does - driving the production control rather than reaching past it into the view model.
    static func element(labeled label: String, in root: UIView) -> NSObject? {
        activate()

        var found: NSObject?
        walk(root) { node in
            guard node.isAccessibilityElement, node.accessibilityLabel == label else { return true }
            found = node
            return false
        }
        return found
    }

    /// The first accessibility element whose label satisfies `predicate`, so a test can reach an element
    /// whose label carries live-changing text (a countdown's "N seconds remaining") by matching its
    /// stable prefix - and then read its traits or value. Used by US-CC14 to assert the countdown ring
    /// carries `.updatesFrequently`.
    static func element(whereLabel predicate: (String) -> Bool, in root: UIView) -> NSObject? {
        activate()

        var found: NSObject?
        walk(root) { node in
            guard node.isAccessibilityElement, let label = node.accessibilityLabel, predicate(label) else { return true }
            found = node
            return false
        }
        return found
    }

    /// Attaches an assistive client and gives the run loop a turn to build the tree behind it.
    private static func activate() {
        _ = UIApplication.shared.accessibilityActivate()
        UIAccessibility.post(notification: .screenChanged, argument: nil)
        RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.5))
    }

    /// Depth-first over both halves of the hierarchy - the accessibility children a node vends and the
    /// UIKit subviews under it - visiting each node once. `visit` returns `false` to stop the walk.
    private static func walk(_ root: NSObject, _ visit: (NSObject) -> Bool) {
        var visited = Set<ObjectIdentifier>()
        var stopped = false

        func descend(_ node: NSObject) {
            guard !stopped, visited.insert(ObjectIdentifier(node)).inserted else { return }
            guard visit(node) else {
                stopped = true
                return
            }
            let count = node.accessibilityElementCount()
            if count != NSNotFound {
                for index in 0..<count where !stopped {
                    if let child = node.accessibilityElement(at: index) as? NSObject { descend(child) }
                }
            }
            if let view = node as? UIView {
                for subview in view.subviews where !stopped { descend(subview) }
            }
        }
        descend(root)
    }
}
