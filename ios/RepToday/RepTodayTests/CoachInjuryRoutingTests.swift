import XCTest
@testable import RepToday

/// Tests US-AC08's detector: `CoachInjurySignalMapper`, the pure on-device function that turns a coach
/// message into a **routing proposal** naming an area - or into nothing at all.
///
/// Two failure modes matter and both are covered: missing a real complaint (the user says their knee
/// hurts and is never offered the control), and firing on a message that merely mentions a body part
/// (a form question turning into an unprompted safety prompt). The second is the one the surrounding
/// design cares most about, since the whole story exists to keep safety filters explicit.
///
/// The write-freeness of the proposal is not asserted here because it is not assertable: it is a
/// property of the type. `CoachInjuryRoutingProposal` names an `InjuryOption` and carries nothing that
/// could set a flag.
final class CoachInjuryRoutingTests: XCTestCase {

    // MARK: - Real signals

    func testKneeComplaintRoutesToKnees() {
        XCTAssertEqual(CoachInjurySignalMapper.routing(for: "my knee hurts on squats")?.area, .knees,
                       "the PRD's validation message must be recognized")
    }

    func testColloquialComplaintsAreRecognized() {
        let cases: [(String, InjuryOption)] = [
            ("my knee's cranky today", .knees),
            ("shoulder is really sore after yesterday", .shoulders),
            ("I tweaked my lower back moving a couch", .lowerBack),
            ("is planking safe with a sore wrist?", .wrists),
            ("my ankle has been aching all week", .ankles),
            ("hip flexor pain when I squat", .hips),
        ]
        for (message, expected) in cases {
            XCTAssertEqual(CoachInjurySignalMapper.routing(for: message)?.area, expected,
                           "\"\(message)\" should read as a \(expected) signal")
        }
    }

    func testDetectionIsCaseInsensitive() {
        XCTAssertEqual(CoachInjurySignalMapper.routing(for: "MY KNEE HURTS")?.area, .knees)
    }

    /// Every area the injury control offers must be reachable from everyday language, or the coach
    /// could notice a complaint it has no way to name. Driven through the public API rather than the
    /// private keyword table, so it pins behavior rather than implementation.
    func testEveryInjuryOptionIsReachableFromAPlainComplaint() {
        for option in InjuryOption.allCases {
            let message = "my \(option.label.lowercased()) hurts"
            XCTAssertEqual(CoachInjurySignalMapper.routing(for: message)?.area, option,
                           "\"\(message)\" must route to \(option) - a protectable area the coach cannot name is unreachable")
        }
    }

    // MARK: - Not signals (the false-positive bar)

    /// The bar `CoachIntentMapper` set and this must hold too: a movement question that mentions a body
    /// part is not a health signal.
    func testFormQuestionsNeverRoute() {
        let messages = [
            "how do I do a pistol squat?",
            "how do I do knee push-ups?",
            "is my form on wrist-friendly planks okay?",
            "why did I get squats today?",
            "I'm bored - why does it feel repetitive?",
            "focus my push for a while",
            "take it easier this week",
        ]
        for message in messages {
            XCTAssertNil(CoachInjurySignalMapper.routing(for: message),
                         "\"\(message)\" must not be read as an injury signal")
        }
    }

    /// A complaint cue with no area, or an area with no complaint, is not a signal either.
    func testHalfASignalIsNotASignal() {
        XCTAssertNil(CoachInjurySignalMapper.routing(for: "everything hurts today"),
                     "a complaint naming no area has nothing to route to")
        XCTAssertNil(CoachInjurySignalMapper.routing(for: "tell me about knees and hips"),
                     "naming an area is not complaining about it")
    }

    /// A negated complaint is the conservative case: there is nothing to offer to flag.
    func testNegatedComplaintsDoNotRoute() {
        let messages = [
            "my knee doesn't hurt any more",
            "no pain in my shoulder now",
            "my wrist is no longer sore",
            "my ankle used to hurt but it's fine",
        ]
        for message in messages {
            XCTAssertNil(CoachInjurySignalMapper.routing(for: message),
                         "\"\(message)\" reports a resolved complaint, not a live one")
        }
    }

    /// A question about *staying* uninjured is not a report of being injured. Without this the bare
    /// noun cues ("injury"/"injured") turn every prevention question into an unprompted safety prompt
    /// about an area the user never complained about.
    func testPreventionQuestionsDoNotRoute() {
        let messages = [
            "how do I avoid knee injury?",
            "what should I do to prevent shoulder injury?",
            "any tips to protect my wrists from injury?",
            "how do I squat without knee pain?",
            "is there a risk of ankle injury with jumping?",
        ]
        for message in messages {
            XCTAssertNil(CoachInjurySignalMapper.routing(for: message),
                         "\"\(message)\" asks how to stay uninjured - it reports no complaint to flag")
        }
    }

    /// The other direction of the same matcher: a qualifier belongs to the clause it was written in,
    /// so an unrelated contraction one clause earlier must not swallow a live complaint. "can't squat,
    /// knee is sore" is the story's own headline shape.
    func testAQualifierInAnEarlierClauseDoesNotSwallowARealComplaint() {
        let cases: [(String, InjuryOption)] = [
            ("can't squat, knee is sore", .knees),
            ("I don't want to skip today, but my shoulder hurts", .shoulders),
            ("no equipment here, and my wrist aches", .wrists),
            ("I avoid running. my knee hurts anyway", .knees),
        ]
        for (message, expected) in cases {
            XCTAssertEqual(CoachInjurySignalMapper.routing(for: message)?.area, expected,
                           "\"\(message)\" is a live \(expected) complaint")
        }
    }

    /// And the negation still binds inside its own clause, at any sentence length - the fix must not
    /// buy the miss rate down by letting resolved complaints through.
    func testNegationStillBindsWithinItsOwnClause() {
        let messages = [
            "my knee doesn't hurt any more",
            "honestly, my shoulder is not sore at all today",
            "quick question - my hip never aches now",
        ]
        for message in messages {
            XCTAssertNil(CoachInjurySignalMapper.routing(for: message),
                         "\"\(message)\" reports a resolved complaint, not a live one")
        }
    }

    /// "back" as a direction is not the lower back, even beside a complaint about something else.
    func testDirectionalBackIsNotTheLowerBack() {
        XCTAssertNil(CoachInjurySignalMapper.routing(for: "can you back off the volume? nothing hurts, I'm just tired"),
                     "\"back off\" is not a body part")
        XCTAssertEqual(CoachInjurySignalMapper.routing(for: "getting back into it and my knee hurts")?.area, .knees,
                       "a directional \"back\" must not steal a real knee complaint")
    }

    // MARK: - Proximity and disambiguation

    /// A complaint far from the area mention is not attributed to it - two unrelated clauses stay
    /// unrelated.
    func testDistantComplaintDoesNotAttachToAnArea() {
        let message = "my knees are the strongest part of my training right now, and separately I want to "
            + "understand why my sessions feel so short lately, it is honestly painful to sit through"
        XCTAssertNil(CoachInjurySignalMapper.routing(for: message),
                     "a complaint sixty-plus characters from the area mention is not about that area")
    }

    /// When two areas are mentioned, the one the complaint sits nearest to wins, deterministically.
    func testNearestAreaToTheComplaintWins() {
        XCTAssertEqual(CoachInjurySignalMapper.routing(for: "squats are fine for my hips but my knee hurts")?.area,
                       .knees)
        XCTAssertEqual(CoachInjurySignalMapper.routing(for: "my shoulder hurts, wrists are fine")?.area,
                       .shoulders)
    }

    func testDetectionIsDeterministic() {
        let message = "my knee's been cranky since last week"
        let first = CoachInjurySignalMapper.routing(for: message)
        for _ in 0..<20 {
            XCTAssertEqual(CoachInjurySignalMapper.routing(for: message), first,
                           "the mapper is a pure function of the message")
        }
    }

    func testEmptyMessageRoutesNothing() {
        XCTAssertNil(CoachInjurySignalMapper.routing(for: ""))
        XCTAssertNil(CoachInjurySignalMapper.routing(for: "   "))
    }
}
