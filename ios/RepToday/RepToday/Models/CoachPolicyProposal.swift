import Foundation

/// A closed, bounded proposal for a **coach-sourced policy nudge** (US-AC07): the one shape a request
/// to the premium AI coach ("focus my push", "I'm bored of squats", "take it a bit easier") is
/// converted into before it can touch the per-user `SessionPolicy`.
///
/// It names *raw proposed values* for the **three preference levers only** - per-pattern staleness
/// emphasis (US-AC05), a progression rate to ease toward (US-AC06), and a variety window to narrow
/// toward - and **nothing else**. The safety filters the coach must never touch (injuries, difficulty
/// cap, phase gate, zero-equipment, the cold-start contract, the Re-entry Ramp) are simply *not
/// expressible* in this type, so "the coach only writes preference levers" is a property of the data
/// model, not a runtime check that could be forgotten.
///
/// The values here are **untrusted and un-clamped by construction**: whatever produced the proposal (the
/// on-device intent mapper today, a proxy-emitted structured action tomorrow) may propose an out-of-range
/// or unsafe value. The on-device write path (`SessionPolicy.applyingCoachProposal` /
/// `CoachSessionPolicyService`) is solely responsible for clamping every value to the engine's rails and
/// enforcing direction safety (emphasis is disjoint from safety moves; the rate only eases *down*; the
/// window only narrows *in*), so even a hostile proposal can only ever yield a bounded, safety-preserving,
/// reversible write. Nothing is trusted about the proposal except its *shape*.
struct CoachPolicyProposal: Equatable {

    /// Per-`MovementPattern` proposed staleness emphasis (raw; the write path clamps each to
    /// `[SessionPolicy.minEmphasis, maxEmphasis]`). A pattern absent from the map is left at its current
    /// in-force emphasis - this is an overlay, never a replacement. Disjoint from every deterministic
    /// safety move, so it can be applied as a straight clamped overlay.
    var patternEmphasis: [MovementPattern: Double]

    /// A progression rate the coach wants to **ease toward** (raw; the write path clamps to the rate rail
    /// and then caps at the in-force/engine-earned rate - ease-down only, never above what the engine
    /// earned). `nil` leaves `progressionRate` untouched.
    var easedProgressionRate: Double?

    /// A variety window the coach wants to **narrow toward** (raw; the write path clamps to the window rail
    /// and then caps at the in-force window - narrow-only, never widened beyond the in-force value). `nil`
    /// leaves `varietyWindow` untouched.
    var narrowedVarietyWindow: Int?

    init(
        patternEmphasis: [MovementPattern: Double] = [:],
        easedProgressionRate: Double? = nil,
        narrowedVarietyWindow: Int? = nil
    ) {
        self.patternEmphasis = patternEmphasis
        self.easedProgressionRate = easedProgressionRate
        self.narrowedVarietyWindow = narrowedVarietyWindow
    }

    /// Whether this proposal names no lever at all - the honest "the coach recognized no tuning request"
    /// signal the intent mapper returns and the write path short-circuits on. An empty proposal is never a
    /// policy write.
    var isEmpty: Bool {
        patternEmphasis.isEmpty && easedProgressionRate == nil && narrowedVarietyWindow == nil
    }
}
