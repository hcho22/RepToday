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
/// *Where* the finger was is deliberately not this type's business, and that is the whole point of the
/// split. A press has two possible ends and the button reports them separately: `pressReleased` is a
/// finger lifting on the control - it comes from a real `Button`'s action, so the bounds deciding it
/// are the platform's own touch-up-inside, the same hit testing every other control in the app gets,
/// touch slop and all - while `pressEnded` is the press merely ceasing to be tracked (stolen by the
/// scroll view, carried clear of the button, the row disappearing) and commits nothing. They are safe
/// to call in either order for one release, and a press that only ever ends commits nothing at all.
///
/// Inheriting those bounds means a press stays with the button it *landed* on: a finger that lands on
/// `+` and lifts a little over the adjacent `-` is still within `+`'s touch-up slop, so it steps `+`,
/// and only travel past that slop stops it committing. Two adjacent buttons anywhere else in iOS
/// behave the same way, and matching them is exactly why the decision is not made here. Earlier
/// versions did make it here, from how far the finger had travelled since it landed - but a radius
/// drawn around a landing point is not a button's bounds however it is tuned.
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

    /// Set the moment the press outlives the hold delay. The release reads it to know the repeat
    /// already owns this press - which is the one thing that keeps a hold from ending a step past
    /// what it showed - and it has to survive `pressEnded`, since a single release delivers both
    /// calls in an order the gesture layer decides.
    ///
    /// Both ways a hold can finish clear it, so a `true` never outlives the press that set it and no
    /// later tap is swallowed by one. `pressReleased` clears it once it has read it; the repeat
    /// clears it itself when a refused `step` ends the loop, which is the case no release ever
    /// reports - a hold that walks the value into the bound disables its own button under the finger,
    /// so the lift fires no action. Clearing there is safe precisely because the value is pinned:
    /// a release arriving anyway would step, and that step would be refused too.
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
                guard step() else {
                    self?.didBecomeHold = false
                    return
                }
                do { try await sleep(repeatInterval) } catch { return }
            }
        }
    }

    /// The finger lifted on the control: one step, unless the press had already become a hold and
    /// taken its own.
    @MainActor
    func pressReleased(step: () -> Bool) {
        let wasHold = didBecomeHold
        didBecomeHold = false
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

    /// The repeat loop touches nothing on `self`, so it would happily outlive the button that started
    /// it and keep stepping the binding with no finger on screen. `.onDisappear` is the ordinary way
    /// this ends; this is the backstop for the teardown paths that never deliver one.
    deinit {
        task?.cancel()
    }
}
