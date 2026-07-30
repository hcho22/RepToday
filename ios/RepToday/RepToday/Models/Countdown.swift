import Foundation

/// A wall-clock countdown with pause semantics - the mechanism behind both timers the active-session
/// player runs: the rest between sets (US-K02) and the Hold Timer on a timed movement (US-O03).
///
/// It is scheduled against an absolute `deadline` rather than a ticking counter, so a view can read it
/// once a second without the model owning a timer, and it stays correct across a gap the app did not
/// observe. Backgrounding `pause`s it, which swaps the deadline for the frozen `remainingWhenPaused`
/// so the countdown holds instead of blowing past while the user is away; `resume` reschedules from
/// that remainder. Exactly one of the two is set while a countdown exists.
///
/// Every method is pure over an injected `date`, so the tests drive a countdown to zero, across a
/// pause, and back without real time passing.
///
/// This type exists because the two timers were written as line-for-line copies of each other, and a
/// bug fixed in one kept surviving in the other - the restore path fired a completion cue for a
/// countdown that had already run out while the app was gone, and closing that door for the hold left
/// it open for the rest. One implementation makes that a single fix rather than a coin flip. What the
/// timers do *with* a countdown stays distinct and lives in the view model: a hold has sides and banks
/// a set at zero, a rest has extend/skip and only fires a cue.
struct Countdown: Equatable {

    /// The full length in seconds, including any extension - the denominator a progress ring measures
    /// against.
    private(set) var total: Int

    /// The wall-clock instant a *running* countdown finishes. `nil` while paused.
    private(set) var deadline: Date?

    /// The seconds captured when the countdown was paused. `nil` while running.
    private(set) var remainingWhenPaused: Int?

    /// Start a countdown of `seconds`, running from `date`.
    init(seconds: Int, from date: Date) {
        self.total = seconds
        self.deadline = date.addingTimeInterval(TimeInterval(seconds))
        self.remainingWhenPaused = nil
    }

    /// Rebuild a countdown from persisted parts, for the restore path.
    init(total: Int, deadline: Date?, remainingWhenPaused: Int?) {
        self.total = total
        self.deadline = deadline
        self.remainingWhenPaused = remainingWhenPaused
    }

    /// Whether the countdown is frozen (the app is backgrounded) rather than running.
    var isPaused: Bool { remainingWhenPaused != nil }

    /// Seconds left as of `date`, floored at zero. While paused this is the frozen remainder, so time
    /// spent away never draws it down.
    func remaining(asOf date: Date) -> Int {
        if let remainingWhenPaused { return remainingWhenPaused }
        guard let deadline else { return 0 }
        return max(0, Int(ceil(deadline.timeIntervalSince(date))))
    }

    /// Whether a *running* countdown has reached zero as of `date`. False while paused, which is what
    /// keeps a completion cue from firing at a screen the user is away from, and what makes the check
    /// safe to call on every tick.
    func hasElapsed(asOf date: Date) -> Bool {
        !isPaused && remaining(asOf: date) == 0
    }

    /// Freeze the countdown at its current remainder. A no-op if already paused.
    mutating func pause(asOf date: Date) {
        guard !isPaused else { return }
        remainingWhenPaused = remaining(asOf: date)
        deadline = nil
    }

    /// Reschedule from the frozen remainder. A no-op if not paused.
    mutating func resume(asOf date: Date) {
        guard let remainingWhenPaused else { return }
        deadline = date.addingTimeInterval(TimeInterval(remainingWhenPaused))
        self.remainingWhenPaused = nil
    }

    /// Add `seconds`, moving both the remaining time and the total the ring measures against.
    mutating func extend(by seconds: Int) {
        guard seconds > 0 else { return }
        total += seconds
        if let remainingWhenPaused {
            self.remainingWhenPaused = remainingWhenPaused + seconds
        } else if let deadline {
            self.deadline = deadline.addingTimeInterval(TimeInterval(seconds))
        }
    }
}
