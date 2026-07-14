import Foundation

/// The honest, templated note the on-device AI Programmer attaches to a re-program (Epic F,
/// US-F04): a plain-language line naming *what actually changed and why*, always
/// `source == .template` (offline-safe, never blocking).
///
/// The note is built from the **real diff** between the policy before and after re-weighting (plus
/// any Default Duration change), never from the trigger's *intent*. That is the whole discipline of
/// this module: the copy may only name a change the sessions will actually reflect. It never claims
/// a lever moved that did not, and it never invokes the user's `why` - a hollow callback to
/// "get on the floor with your grandkids" is exactly the dishonesty US-F04 forbids. The "why" the
/// note gives is the *mechanical* reason the diff encodes (you're clearing sessions -> more
/// challenge; sessions are a stretch -> less intensity), which is always true because it is read
/// straight off the change.
///
/// Pure and deterministic over its inputs (no clock, no persistence). The re-weighting service
/// (US-F03) computes the before/after policy and duration, calls `templated(...)`, and stores the
/// result on `SessionPolicy.note`. When nothing observable changed the builder returns `nil` - the
/// honest outcome, since a note would otherwise claim a change that is not there. The LLM Variety
/// Language slice (US-G03) is the only other note source and always falls back to this template.
enum PolicyNote {

    /// The before/after Ready-Screen default the Default Duration learning produced (US-F04), so
    /// the note can name a shortened (or lengthened) default alongside any lever change. `changed`
    /// is the only thing the note reads - an unchanged default contributes no clause.
    struct DurationChange: Equatable {
        var before: Int
        var after: Int

        var changed: Bool { before != after }
    }

    /// Build the templated note for a re-program, or `nil` when neither a lever nor the default
    /// duration actually moved.
    ///
    /// Reads only the observable diff: the direction of `progressionRate` and `varietyWindow`
    /// between `before` and `after`, and whether `durationChange` moved the default. The resulting
    /// `SessionPolicy.Note` is always `source == .template`.
    static func templated(
        policyBefore before: SessionPolicy,
        policyAfter after: SessionPolicy,
        durationChange: DurationChange? = nil
    ) -> SessionPolicy.Note? {
        var sentences: [String] = []
        if let challenge = challengeSentence(before: before, after: after) {
            sentences.append(challenge)
        }
        if let change = durationChange, change.changed {
            sentences.append(durationSentence(minutes: change.after))
        }
        guard !sentences.isEmpty else { return nil }
        return SessionPolicy.Note(text: sentences.joined(separator: " "), source: .template)
    }

    // MARK: - Clauses

    /// The sentence describing how challenge moved, driven by the `progressionRate` /
    /// `varietyWindow` diff. Progression leads (it is the difficulty lever the user feels most);
    /// variety, when it also moved, is folded in as a trailing clause. Returns `nil` when neither
    /// lever changed, so a duration-only re-program says nothing untrue about difficulty.
    private static func challengeSentence(before: SessionPolicy, after: SessionPolicy) -> String? {
        let progressionUp = after.progressionRate > before.progressionRate
        let progressionDown = after.progressionRate < before.progressionRate
        let varietyUp = after.varietyWindow > before.varietyWindow
        let varietyDown = after.varietyWindow < before.varietyWindow

        if progressionUp {
            var sentence = "You've been clearing your sessions, so I stepped up the challenge"
            if varietyUp { sentence += " and mixed in fresher movement" }
            else if varietyDown { sentence += " while staying with moves you know" }
            return sentence + "."
        }
        if progressionDown {
            var sentence = "To keep your sessions winnable, I eased the intensity"
            if varietyDown { sentence += " and stayed closer to moves you know" }
            else if varietyUp { sentence += " while adding some fresher movement" }
            return sentence + "."
        }
        // Progression held: report only a standalone variety move, if any.
        if varietyUp { return "I mixed fresher movement into your sessions." }
        if varietyDown { return "I kept your sessions closer to moves you know." }
        return nil
    }

    /// The sentence naming the new learned default session length, framed to what the user
    /// actually finishes (never what they requested), per US-D02/US-F04.
    private static func durationSentence(minutes: Int) -> String {
        "Your go-to session is now \(minutes) minutes, matched to what you actually finish."
    }
}
