import Foundation

/// Maps a free-text coach message to a bounded `CoachPolicyProposal` (US-AC07), on-device.
///
/// This is the "coach converts eligible requests into a policy nudge" seam. It is deliberately
/// **conservative and closed**: it recognizes only a small set of explicit tuning intents - "focus my
/// <pattern>", "less <pattern>" / "bored of <pattern>", "take it easier", "keep me on moves I know" - and
/// returns `nil` for everything else (a normal question is answered by the coach's talk, never a silent
/// policy change). A recognized request maps to *in-range* proposed values; the sovereign write path
/// (`CoachSessionPolicyService`) clamps and direction-checks regardless, so a mis-recognition can only ever
/// produce a bounded, safe, reversible nudge - never an unsafe one.
///
/// It is a pure, deterministic function of the message (no clock, no state), so it is unit-testable in
/// isolation, and it is the one place a future story could swap in a proxy-emitted structured proposal
/// without touching the write path or its safety guarantees: the mapper's *output type* is the contract,
/// not how it was produced.
enum CoachIntentMapper {

    /// The proposal an eligible message maps to, or `nil` when the message is not a recognized tuning
    /// request. An emphasis intent requires **both** an emphasis verb and a named pattern, so a message
    /// that merely mentions a pattern ("how do I do a pistol squat?") never triggers a write.
    static func proposal(for message: String) -> CoachPolicyProposal? {
        let text = message.lowercased()

        var emphasis: [MovementPattern: Double] = [:]
        for pattern in foundationalPatterns {
            guard mentions(pattern, in: text) else { continue }
            if containsAny(of: emphasizeMoreCues, in: text) {
                emphasis[pattern] = emphasizeMoreValue
            } else if containsAny(of: emphasizeLessCues, in: text) {
                emphasis[pattern] = emphasizeLessValue
            }
        }

        let easedRate: Double? = containsAny(of: easeCues, in: text) ? easeToRate : nil
        let narrowedWindow: Int? = containsAny(of: narrowVarietyCues, in: text) ? narrowToWindow : nil

        let proposal = CoachPolicyProposal(
            patternEmphasis: emphasis,
            easedProgressionRate: easedRate,
            narrowedVarietyWindow: narrowedWindow
        )
        return proposal.isEmpty ? nil : proposal
    }

    // MARK: - Recognized patterns

    /// The foundational patterns a coach tuning request can name. Non-foundational patterns
    /// (`pull`/`mobility`/`locomotion`) are not user-requestable levers on this surface.
    private static let foundationalPatterns: [MovementPattern] = [.push, .squat, .hinge, .core]

    /// The keywords that name each pattern in everyday language. Kept narrow to avoid false positives:
    /// e.g. `squat` deliberately does not claim the ambiguous word "legs".
    private static func mentions(_ pattern: MovementPattern, in text: String) -> Bool {
        containsAny(of: keywords(for: pattern), in: text)
    }

    private static func keywords(for pattern: MovementPattern) -> [String] {
        switch pattern {
        case .push: return ["push", "press", "chest", "upper body"]
        case .squat: return ["squat", "quad"]
        case .hinge: return ["hinge", "deadlift", "glute", "hamstring", "posterior"]
        case .core: return ["core", "abs", "midsection", "plank"]
        default: return []
        }
    }

    // MARK: - Recognized intent cues

    private static let emphasizeMoreCues = ["focus", "more ", "prioriti", "work on", "lean into", "want more"]
    private static let emphasizeLessCues = ["less ", "bored of", "tired of", "sick of", "avoid", "cut back", "ease off"]
    private static let easeCues = ["easier", "ease up", "take it easy", "go easy", "too hard", "back off", "lighter", "less intense"]
    private static let narrowVarietyCues = ["moves i know", "same moves", "familiar", "less variety", "stop changing", "keep it familiar"]

    // MARK: - Proposed (pre-clamp) values

    /// A firm-but-in-range "more of this pattern" emphasis. The write path clamps to
    /// `SessionPolicy.maxEmphasis` regardless, so this stays a nudge rather than a dictate.
    private static let emphasizeMoreValue = 1.6
    /// A firm-but-in-range "less of this pattern" emphasis.
    private static let emphasizeLessValue = 0.6
    /// The pace the coach eases toward on an "easier" request: the rail floor. The write path caps it at
    /// the in-force (engine-earned) rate, so it lowers pace as far as is safe without ever raising it.
    private static let easeToRate = SessionPolicy.minProgressionRate
    /// The window the coach narrows toward on a "keep it familiar" request: the rail floor. The write path
    /// caps it at the in-force window, so it only ever narrows.
    private static let narrowToWindow = SessionPolicy.minVarietyWindow

    // MARK: - Helpers

    private static func containsAny(of needles: [String], in haystack: String) -> Bool {
        needles.contains { haystack.contains($0) }
    }
}
