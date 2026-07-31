import Foundation

/// The press-and-hold behaviour behind a hand-drawn step button: nothing commits while the finger is
/// down, a release commits one step, and a press that outlives `holdDelay` repeats instead - the
/// release then adds nothing on top of what the read-out already showed while it was held.
///
/// Committing on *release* is what every other control in the app does, and it is what makes the
/// stepper safe inside a scrolling step: a finger that lands on `+` on its way to a scroll has moved
/// nothing, and the only recovery from a stray step would be the opposite button. Stepping on touch
/// -down feels a shade snappier, but it charges an accidental brush to the user's own body
/// measurements, which nothing downstream lets them correct yet.
///
/// A press has three possible ends and this type names them separately, because the gesture layer
/// cannot: `pressReleased` is a finger lifting on the control, `pressEnded` is the press merely
/// ceasing to be tracked (dragged off, stolen by the scroll view, the row disappearing) and commits
/// nothing. They are safe to call in either order for one release, and a press that only ever ends
/// commits nothing at all.
///
/// `step` reports whether the value actually moved, and a `false` ends the repeat. Holding `+` at the
/// top of a range therefore stops, rather than writing the same clamped value back through a binding
/// ~11 times a second - Observation notifies on every write regardless of equality, so that is a real
/// invalidation loop for no visible change.
///
/// The clock is injectable so `PressRepeaterTests` can drive a whole hold without waiting on one.
final class PressRepeater {

    /// How long the finger must stay down before the repeat takes over from the release.
    static let defaultHoldDelay: Duration = .milliseconds(400)

    /// Time between repeats once the hold has started.
    static let defaultRepeatInterval: Duration = .milliseconds(90)

    private let holdDelay: Duration
    private let repeatInterval: Duration
    private let sleep: (Duration) async throws -> Void
    private var task: Task<Void, Never>?

    /// Set the moment the press outlives the hold delay, and only cleared by the next press. The
    /// release reads it to know the repeat already owns this press - which is the one thing that
    /// keeps a hold from ending a step past what it showed - and it has to survive `pressEnded`,
    /// since a single release delivers both calls in an order the gesture layer decides.
    private var didBecomeHold = false

    init(
        holdDelay: Duration = PressRepeater.defaultHoldDelay,
        repeatInterval: Duration = PressRepeater.defaultRepeatInterval,
        sleep: @escaping (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.holdDelay = holdDelay
        self.repeatInterval = repeatInterval
        self.sleep = sleep
    }

    /// A finger landed. Nothing commits yet: this only starts the clock that decides whether the
    /// press is a tap or a hold.
    @MainActor
    func pressBegan(step: @escaping () -> Bool) {
        cancel()
        didBecomeHold = false
        task = Task { [weak self, holdDelay, repeatInterval, sleep] in
            do { try await sleep(holdDelay) } catch { return }
            guard !Task.isCancelled else { return }
            self?.didBecomeHold = true
            while !Task.isCancelled {
                guard step() else { return }
                do { try await sleep(repeatInterval) } catch { return }
            }
        }
    }

    /// The finger lifted on the control: one step, unless the press had already become a hold and
    /// taken its own.
    @MainActor
    func pressReleased(step: () -> Bool) {
        let wasHold = didBecomeHold
        cancel()
        guard !wasHold else { return }
        _ = step()
    }

    /// The press stopped being tracked - it was released, dragged off, taken over by an ancestor
    /// scroll view, or the row went away. Stops the repeat and commits nothing on its own.
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
