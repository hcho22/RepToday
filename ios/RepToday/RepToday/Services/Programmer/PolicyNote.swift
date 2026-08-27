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

    // MARK: - Coach-authored note (US-AC07)

    /// The honest note a **coach-sourced** policy write attaches (US-AC07), built from the same real
    /// before/after diff discipline as `templated(...)` but in the coach's second-person, identity-framed
    /// voice ("You asked to focus your push - I'm leading with it more this week") rather than the
    /// deterministic Programmer's first-person one.
    ///
    /// It may only name a lever the write actually moved: a per-pattern emphasis that rose or fell, a pace
    /// the coach eased, or a variety window it narrowed. It never names the levers a coach cannot move
    /// (upward pace, a widened window - those are impossible by construction) and never claims a change the
    /// policy does not reflect. Returns `nil` when nothing the coach can move actually moved, so the write
    /// path can treat "no note" as "no real change" and persist nothing. Always `source == .template`
    /// (offline-safe; the coach's *reply* is separate LLM text, but the durable policy note is a local,
    /// honest template).
    static func coachTemplated(
        policyBefore before: SessionPolicy,
        policyAfter after: SessionPolicy
    ) -> SessionPolicy.Note? {
        var sentences: [String] = []
        if let emphasis = emphasisSentence(before: before, after: after) {
            sentences.append(emphasis)
        }
        if let easing = easingSentence(before: before, after: after) {
            sentences.append(easing)
        }
        guard !sentences.isEmpty else { return nil }
        return SessionPolicy.Note(text: sentences.joined(separator: " "), source: .template)
    }

    /// The sentence naming which patterns the coach leaned toward or away from, driven by the
    /// `patternEmphasis` diff. Reads every pattern whose emphasis moved (in the evaluator's stable
    /// `MovementPattern.allCases` order so the copy is deterministic) and separates the ones that rose
    /// ("more") from the ones that fell ("less"). Returns `nil` when no pattern's emphasis changed.
    private static func emphasisSentence(before: SessionPolicy, after: SessionPolicy) -> String? {
        var raised: [MovementPattern] = []
        var lowered: [MovementPattern] = []
        for pattern in MovementPattern.allCases {
            let old = before.patternEmphasis[pattern] ?? SessionPolicy.neutralEmphasis
            let new = after.patternEmphasis[pattern] ?? SessionPolicy.neutralEmphasis
            if new > old { raised.append(pattern) }
            else if new < old { lowered.append(pattern) }
        }
        guard !raised.isEmpty || !lowered.isEmpty else { return nil }

        var clauses: [String] = []
        if !raised.isEmpty {
            clauses.append("you asked to focus your \(list(raised)), so I'm leading with \(raised.count == 1 ? "it" : "them") more")
        }
        if !lowered.isEmpty {
            clauses.append("you wanted less \(list(lowered)) for now, so I've eased off")
        }
        // Sentence-case the first clause and close it off.
        let joined = clauses.joined(separator: ", and ")
        return joined.prefix(1).uppercased() + joined.dropFirst() + " this week."
    }

    /// The sentence naming a coach easing move - a lowered `progressionRate` and/or a narrowed
    /// `varietyWindow`. A coach can only ever ease *down* / narrow *in* (US-AC06/AC07), so this never
    /// reports a step-up or a widened window. Returns `nil` when neither eased.
    private static func easingSentence(before: SessionPolicy, after: SessionPolicy) -> String? {
        let easedPace = after.progressionRate < before.progressionRate
        let narrowedVariety = after.varietyWindow < before.varietyWindow
        switch (easedPace, narrowedVariety) {
        case (true, true):
            return "I eased your pace and kept you closer to moves you know, to keep sessions winnable."
        case (true, false):
            return "I eased your pace to keep your sessions winnable."
        case (false, true):
            return "I kept your sessions closer to moves you know."
        case (false, false):
            return nil
        }
    }

    /// Join movement-pattern names into a readable inline list ("push", "push and squat", "push, squat,
    /// and hinge"), lowercased so the clause reads as running prose.
    private static func list(_ patterns: [MovementPattern]) -> String {
        let names = patterns.map(displayName)
        switch names.count {
        case 0: return ""
        case 1: return names[0]
        case 2: return "\(names[0]) and \(names[1])"
        default: return names.dropLast().joined(separator: ", ") + ", and " + names.last!
        }
    }

    /// The plain, lowercase movement-pattern name used in coach copy. Kept local to the note so a
    /// user-facing wording tweak never has to touch the wire-stable `MovementPattern.rawValue`.
    private static func displayName(_ pattern: MovementPattern) -> String {
        switch pattern {
        case .push: return "push"
        case .squat: return "squat"
        case .hinge: return "hinge"
        case .core: return "core"
        case .pull: return "pull"
        case .mobility: return "mobility"
        case .locomotion: return "locomotion"
        }
    }
}
