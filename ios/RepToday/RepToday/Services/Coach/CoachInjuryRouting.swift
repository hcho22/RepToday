import Foundation

/// What the coach may do with a health/injury signal (US-AC08): **route the user to the real injury
/// control**, and nothing else.
///
/// The safety boundary is a property of this type, not of a runtime check. It names an area from the
/// app's one closed injury vocabulary (`InjuryOption`) and carries no tag string, no "set" verb, and no
/// reference to `UserProfile.injuries` - so the only thing a caller can do with a value of this type is
/// *offer* to take the user somewhere. Setting the flag is unreachable from here; it happens in the
/// injury control the user is routed to, under their own explicit, confirmed, reversible action.
///
/// This is the deliberate sibling of `CoachPolicyProposal` (US-AC07), which can name only *preference*
/// levers: safety filters stay inexpressible on the coach's write path, permanently. Injury routing is
/// not a second write path - it is a pointer to the user's own control.
struct CoachInjuryRoutingProposal: Equatable {
    /// The area the message sounded like it was about, from the closed onboarding vocabulary the
    /// engine's `InjuryContraindication` map already recognizes. It is the *destination* of a route,
    /// never a value to be written.
    let area: InjuryOption
}

/// Recognizes a health/injury signal in a free-text coach message, on-device (US-AC08).
///
/// It mirrors `CoachIntentMapper`'s shape and its bar for false positives: a pure, deterministic,
/// closed function of the message (no clock, no state, no I/O) that returns a routing proposal or
/// `nil`. A mention of a body part is never enough - the message must carry a **complaint cue**
/// ("hurts", "sore", "cranky", ...) near a **recognized area**, so "how do I do a pistol squat?" and
/// "is my form on knee push-ups okay?" route nothing.
///
/// Being wrong in either direction is bounded and safe: a missed signal just means the coach talks
/// without offering (the user can always open the control from Settings), and a spurious offer changes
/// nothing on its own - it is a question with a decline affordance, and the flag is only ever set by
/// the user in the control itself.
enum CoachInjurySignalMapper {

    /// The routing proposal a message maps to, or `nil` when it is not a health/injury signal.
    static func routing(for message: String) -> CoachInjuryRoutingProposal? {
        let text = message.lowercased()

        // Complaint cues that are inside a negation window ("my knee doesn't hurt", "no pain in my
        // shoulder any more") are dropped: the conservative reading of a negated complaint is that
        // there is nothing to offer to flag.
        let complaints = wordOffsets(of: complaintCues, in: text).filter { !isNegated(at: $0, in: text) }
        guard !complaints.isEmpty else { return nil }

        // Phrases where "back" is a direction rather than a body part ("back off", "get back to
        // squats") are consumed first, so a nearby complaint about something else cannot be read as a
        // back complaint. Same technique the emphasis mapper uses for nested cue phrases.
        let directionalBackSpans = phraseSpans(of: directionalBackPhrases, in: text)

        // Every recognized area mention, in `InjuryOption.allCases` order, so ties resolve
        // deterministically.
        let mentions: [(offset: Int, area: InjuryOption)] = InjuryOption.allCases.flatMap { area in
            wordOffsets(of: keywords(for: area), in: text)
                .filter { offset in area != .lowerBack || !directionalBackSpans.contains { $0.contains(offset) } }
                .map { (offset: $0, area: area) }
        }
        guard !mentions.isEmpty else { return nil }

        // Each complaint is attributed to the area it is *about*, which in English is almost always the
        // nearest one before it ("my shoulder hurts, wrists are fine" is about the shoulder), falling
        // back to the nearest one after it for a lead-in phrasing ("sore wrist", "I tweaked my back").
        var best: (distance: Int, area: InjuryOption)?
        for complaint in complaints {
            var attributed: (offset: Int, area: InjuryOption)?
            for mention in mentions where mention.offset <= complaint {
                if attributed == nil || mention.offset > attributed!.offset { attributed = mention }
            }
            if attributed == nil {
                for mention in mentions where mention.offset > complaint {
                    if attributed == nil || mention.offset < attributed!.offset { attributed = mention }
                }
            }
            guard let attributed else { continue }
            let distance = abs(complaint - attributed.offset)
            guard distance <= proximityWindow else { continue }
            if best == nil || distance < best!.distance {
                best = (distance, attributed.area)
            }
        }

        return best.map { CoachInjuryRoutingProposal(area: $0.area) }
    }

    // MARK: - Recognized vocabulary

    /// The everyday words that name each protectable area. Deliberately narrow, and deliberately the
    /// *same* closed set the injury control offers - the coach can never point at an area the user has
    /// no control for, and `OnboardingInjuryVocabularyTests` pins that every `InjuryOption` is both
    /// recognizable here and resolvable by `InjuryContraindication`.
    private static func keywords(for area: InjuryOption) -> [String] {
        switch area {
        case .knees: return ["knee", "kneecap"]
        case .lowerBack: return ["lower back", "low back", "lumbar", "back"]
        case .shoulders: return ["shoulder", "rotator cuff", "delt"]
        case .wrists: return ["wrist"]
        case .ankles: return ["ankle", "achilles"]
        case .hips: return ["hip", "hip flexor"]
        }
    }

    /// The complaint cues that turn a body-part mention into a health signal. Matched on word
    /// boundaries (with the usual inflections), so "sore" matches "sore"/"soreness" but "ache" never
    /// matches inside "stomachache", and "pain" never inside "painting".
    private static let complaintCues = [
        "hurt", "hurting", "pain", "painful", "sore", "soreness",
        "ache", "aching", "achy", "cranky", "tweak", "tweaked",
        "strain", "strained", "sprain", "sprained", "injured", "injury",
        "bother", "bothering", "acting up", "flaring", "flare up", "twinge",
    ]

    /// Phrases where "back" is a direction, not the lower back.
    private static let directionalBackPhrases = [
        "back off", "back to", "back up", "back down", "back into", "back in",
        "get back", "getting back", "come back", "coming back", "went back", "back at", "back on",
    ]

    /// The negation cues that disqualify a complaint cue when one appears just before it.
    private static let negationCues = ["no ", "not ", "n't", "never", "no longer", "used to", "without", "isn't"]

    /// How far before a complaint cue a negation is still taken to govern it. Short on purpose: long
    /// enough for "my knee doesn't hurt", short enough that an unrelated "not" earlier in a sentence
    /// does not silently swallow a real complaint.
    private static let negationWindow = 24

    /// How near a complaint cue must sit to an area mention to count as being about that area. This is
    /// what makes "my knee hurts on squats" a knee signal and keeps two unrelated clauses apart.
    private static let proximityWindow = 60

    // MARK: - Helpers

    private static func isNegated(at complaintOffset: Int, in text: String) -> Bool {
        let lower = max(0, complaintOffset - negationWindow)
        guard lower < complaintOffset else { return false }
        let start = text.index(text.startIndex, offsetBy: lower)
        let end = text.index(text.startIndex, offsetBy: complaintOffset)
        let window = String(text[start..<end])
        return negationCues.contains { window.contains($0) }
    }

    /// The character offsets where any needle appears as a whole word (allowing a common inflectional
    /// suffix), so a keyword never matches inside a longer, unrelated word.
    private static func wordOffsets(of needles: [String], in text: String) -> [Int] {
        needles.flatMap { needle -> [Int] in
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
    }

    /// The half-open offset spans every occurrence of any needle occupies, used to consume a phrase so
    /// a word nested inside it is not counted on its own.
    private static func phraseSpans(of needles: [String], in text: String) -> [Range<Int>] {
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

    private static let inflectionSuffixes: Set<String> = ["s", "es", "ed", "ing", "er", "ers"]

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
