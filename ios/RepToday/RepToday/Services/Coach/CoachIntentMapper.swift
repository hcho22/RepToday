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

        // Cue positions are found once and each named pattern takes the *nearest* cue's direction, so a
        // mixed request ("more push but less core") honors each pattern's own direction rather than
        // letting one cue win globally.
        let moreOffsets = cueOffsets(of: emphasizeMoreCues, in: text)
        // The bare "less " emphasis cue is a substring of the multi-word ease/variety phrases ("less
        // intense", "less variety"), so first consume those phrase spans and drop any "less " cue that
        // falls inside one - a request to reduce variety or intensity must never de-emphasize a pattern
        // it merely mentions nearby ("keep push but less variety" leaves push alone).
        let phraseSpans = cueSpans(of: easeCues + narrowVarietyCues, in: text)
        let lessOffsets = cueOffsets(of: emphasizeLessCues, in: text).filter { offset in
            !phraseSpans.contains { $0.contains(offset) }
        }

        var emphasis: [MovementPattern: Double] = [:]
        for pattern in foundationalPatterns {
            let mentions = mentionOffsets(for: pattern, in: text)
            guard !mentions.isEmpty else { continue }
            if let value = nearestEmphasis(forMentionsAt: mentions, moreAt: moreOffsets, lessAt: lessOffsets) {
                emphasis[pattern] = value
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

    /// The character offsets at which any of `pattern`'s keywords appear as a whole word, so a keyword
    /// only matches on word boundaries - `core` matches "core"/"cores" but not "score", `abs` matches
    /// "abs" but not "absolutely", `press` matches "press"/"pressing" but not "impression". A common
    /// inflectional suffix (plural/verb ending) is allowed so everyday plurals still match.
    private static func mentionOffsets(for pattern: MovementPattern, in text: String) -> [Int] {
        keywords(for: pattern).flatMap { wordMatchOffsets(of: $0, in: text) }
    }

    /// The character offsets of every occurrence of any needle, substring-based (cues include stems like
    /// "prioriti" and phrases like "work on", so word-boundary matching would be wrong for them).
    private static func cueOffsets(of needles: [String], in text: String) -> [Int] {
        var offsets: [Int] = []
        for needle in needles {
            var searchStart = text.startIndex
            while let range = text.range(of: needle, range: searchStart..<text.endIndex) {
                offsets.append(text.distance(from: text.startIndex, to: range.lowerBound))
                searchStart = range.upperBound
            }
        }
        return offsets
    }

    /// The half-open character-offset spans every occurrence of any needle occupies, used to consume a
    /// multi-word phrase (e.g. "less variety") so a bare cue nested inside it ("less ") is not
    /// double-counted as its own intent.
    private static func cueSpans(of needles: [String], in text: String) -> [Range<Int>] {
        var spans: [Range<Int>] = []
        for needle in needles {
            var searchStart = text.startIndex
            while let range = text.range(of: needle, range: searchStart..<text.endIndex) {
                let lower = text.distance(from: text.startIndex, to: range.lowerBound)
                let upper = text.distance(from: text.startIndex, to: range.upperBound)
                spans.append(lower..<upper)
                searchStart = range.upperBound
            }
        }
        return spans
    }

    /// Given a pattern's mention offsets and the more/less cue offsets, pick the direction of the cue
    /// nearest to any mention. Ties favor "more" (mirrors the prior more-precedence). `nil` when no cue
    /// exists, so a bare pattern mention ("how do I do a squat?") never tunes.
    private static func nearestEmphasis(forMentionsAt mentions: [Int], moreAt: [Int], lessAt: [Int]) -> Double? {
        var best: (distance: Int, value: Double)?
        for mention in mentions {
            for offset in moreAt {
                let distance = abs(offset - mention)
                if best == nil || distance < best!.distance { best = (distance, emphasizeMoreValue) }
            }
            for offset in lessAt {
                let distance = abs(offset - mention)
                if best == nil || distance < best!.distance { best = (distance, emphasizeLessValue) }
            }
        }
        return best?.value
    }

    private static let inflectionSuffixes: Set<String> = ["s", "es", "ed", "ing", "er", "ers"]

    /// The lower-bound character offsets where `needle` appears as a whole word - preceded by a word
    /// boundary and followed either by a boundary or by an allowed inflectional suffix.
    private static func wordMatchOffsets(of needle: String, in text: String) -> [Int] {
        var offsets: [Int] = []
        var searchStart = text.startIndex
        while let range = text.range(of: needle, range: searchStart..<text.endIndex) {
            if isWholeWord(range, in: text) {
                offsets.append(text.distance(from: text.startIndex, to: range.lowerBound))
            }
            searchStart = range.lowerBound < text.endIndex ? text.index(after: range.lowerBound) : text.endIndex
        }
        return offsets
    }

    private static func isWholeWord(_ range: Range<String.Index>, in text: String) -> Bool {
        if range.lowerBound > text.startIndex, isWordCharacter(text[text.index(before: range.lowerBound)]) {
            return false
        }
        if range.upperBound == text.endIndex { return true }
        if !isWordCharacter(text[range.upperBound]) { return true }
        var index = range.upperBound
        var suffix = ""
        while index < text.endIndex, isWordCharacter(text[index]) {
            suffix.append(text[index])
            index = text.index(after: index)
        }
        return inflectionSuffixes.contains(suffix)
    }

    private static func isWordCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber
    }
}
