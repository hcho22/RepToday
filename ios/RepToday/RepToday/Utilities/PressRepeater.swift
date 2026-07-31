import Foundation

/// The press-and-hold behaviour behind a hand-drawn step button: one step the moment the finger
/// lands, then a steady repeat for as long as it stays down.
///
/// A press is one event stream - began, ended - and this type is the only thing that turns it into
/// steps, which is the point of it existing outside the view. Driving the same button from a tap
/// gesture *and* a long-press gesture gives a held press two sources of increments, and it ends one
/// step past what the read-out showed while it was held; there is nowhere for that to happen here.
///
/// `step` reports whether the value actually moved, and a `false` ends the repeat. Holding `+` at the
/// top of a range therefore stops, rather than writing the same clamped value back through a binding
/// ~11 times a second - Observation notifies on every write regardless of equality, so that is a real
/// invalidation loop for no visible change.
///
/// The clock is injectable so `PressRepeaterTests` can drive a whole hold without waiting on one.
final class PressRepeater {

    /// How long the finger must stay down before the repeat starts, so a tap is a single step.
    static let defaultHoldDelay: Duration = .milliseconds(400)

    /// Time between repeats once the hold has started.
    static let defaultRepeatInterval: Duration = .milliseconds(90)

    private let holdDelay: Duration
    private let repeatInterval: Duration
    private let sleep: (Duration) async throws -> Void
    private var task: Task<Void, Never>?

    init(
        holdDelay: Duration = PressRepeater.defaultHoldDelay,
        repeatInterval: Duration = PressRepeater.defaultRepeatInterval,
        sleep: @escaping (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.holdDelay = holdDelay
        self.repeatInterval = repeatInterval
        self.sleep = sleep
    }

    /// A finger landed: step once now, then keep stepping while it stays down.
    @MainActor
    func pressBegan(step: @escaping () -> Bool) {
        cancel()
        guard step() else { return }
        task = Task { [holdDelay, repeatInterval, sleep] in
            do { try await sleep(holdDelay) } catch { return }
            while !Task.isCancelled {
                guard step() else { return }
                do { try await sleep(repeatInterval) } catch { return }
            }
        }
    }

    /// The finger lifted, the press was cancelled, or the row went away.
    @MainActor
    func pressEnded() {
        cancel()
    }

    @MainActor
    private func cancel() {
        task?.cancel()
        task = nil
    }
}
