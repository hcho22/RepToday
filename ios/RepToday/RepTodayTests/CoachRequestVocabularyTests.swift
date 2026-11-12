import XCTest
import SwiftUI
import UIKit
@testable import RepToday

/// The app's half of one rule: the Coach model is never given a word the app does not show a user,
/// and the app never shows one either.
///
/// A model repeats the words it is given. A Coach reply once described a beginner's standing with
/// words the app never shows in that sense ("line", "unlocked"), and every one of them was in what the
/// model had been handed. The list of such words is `proxy/coach-internal-words.json`; "tier" is not
/// on it, because the Progress tab shows "Tier 2 of 4".
///
/// Since M4 the Coach runs on Convex, and the server writes the user's summary itself from their
/// records (`convex/coachPrompt.ts`); `convex/coachPrompt.test.ts` holds that summary and the
/// instructions to the list. This suite holds the app's side: every movement name the server can hand
/// the model, the Coach tab's own fixed copy, and the Premium Progress tab's "How it's felt" note
/// (`StrengthGraduationEvidenceTests` holds the Strength graduation reveal).
@MainActor
final class CoachRequestVocabularyTests: XCTestCase {

    // MARK: - Tests

    func testNoMovementNameTheAppCanSendIsAListedWord() async throws {
        let listed = try Self.listedForms()
        let library = try await MockExerciseService().exercises()
        XCTAssertFalse(library.isEmpty)

        // A movement's display name is the one piece of catalog text the Coach's summary and catalog pass
        // to the model unchanged (`convex/coachPrompt.ts`), so the whole catalog is checked.
        for exercise in library {
            let found = Self.forms(listed, foundIn: exercise.displayName)
            XCTAssertTrue(found.isEmpty, "\"\(exercise.displayName)\" contains \(found)")
        }
    }

    func testTheListIsReadAndLeavesTheAppsOwnWordTierAlone() throws {
        let listed = try Self.listedForms()

        // Positive controls: a vacuous list, or a matcher that cannot see inside camelCase, would let
        // every assertion above pass.
        XCTAssertTrue(listed.contains(["line"]))
        XCTAssertTrue(listed.contains(["discipline", "phase"]))
        XCTAssertEqual(Self.forms(listed, foundIn: "chainPositions"), ["chain"])
        XCTAssertEqual(Self.forms(listed, foundIn: "the hinge side has no harder one unlocked on that line"), ["line", "unlocked"])
        // Whole words only: "discipline" is not "line", and "Incline Push-Up" is a real movement.
        XCTAssertTrue(Self.forms(listed, foundIn: "discipline, Incline Push-Up, online").isEmpty)

        // "Tier" is the app's own word (the Progress tab shows "Tier 2 of 4"), so it is never listed.
        XCTAssertFalse(listed.contains(["tier"]))
        XCTAssertFalse(listed.contains(["tiers"]))
    }

    /// The Coach tab's own words - its notices, its cards, its reminder and disclosure copy - sit beside
    /// the model's replies, so they are held to the same list.
    func testTheCoachTabsOwnCopyCarriesNoListedWord() throws {
        let listed = try Self.listedForms()
        let copy = [
            CoachCopy.emptyTitle, CoachCopy.emptyBody, CoachCopy.couldNotAnswer, CoachCopy.limitReached,
            CoachCopy.unconfirmed, CoachCopy.noSubscriptionFound, CoachCopy.linkedToOtherAccount, CoachCopy.offline, CoachCopy.unavailable,
            CoachCopy.previewTitle, CoachCopy.previewBody, CoachCopy.unlock,
            CoachDataDisclosureCopy.intro, CoachDataDisclosureCopy.whatIsSent, CoachDataDisclosureCopy.leavesDevice,
            CoachDataDisclosureCopy.notStored, CoachDataDisclosureCopy.settingsFooter,
            CoachReminderCopy.settingsFooter, CoachReminderCopy.permissionDenied,
        ] + (1...7).map(CoachReminderCopy.notificationBody(weekday:))
            + CoachViewModel.quickActions.flatMap { [$0.title, $0.message] }
        for text in copy {
            let found = Self.forms(listed, foundIn: text)
            XCTAssertTrue(found.isEmpty, "the Coach tab says \"\(text)\", which contains \(found)")
        }
    }

    /// The Premium "How it's felt" note reads one of two wordings when a user's ratings lean one way.
    /// The Progress tab is hosted for a mostly-too-hard and a mostly-too-easy mix, and nothing it says
    /// carries a listed form of "engine", the word the Coach is told to replace with "Rep Today".
    func testThePremiumProgressTabNamesNoEngineForEitherLeaningMix() async throws {
        let engine = try Self.listedForms(of: "engine")
        let mixes: [(name: String, ratings: [PerceivedDifficulty], counts: String)] = [
            ("mostly too hard", [.tooHard, .tooHard, .tooHard, .tooEasy, .justRight], "1 too easy, 1 just right, 3 too hard"),
            ("mostly too easy", [.tooEasy, .tooEasy, .tooEasy, .tooHard, .justRight], "3 too easy, 1 just right, 1 too hard"),
        ]

        for mix in mixes {
            let logs = try mix.ratings.enumerated().map { index, rating in
                try Self.log(daysAgo: index + 1, now: Self.now, [], perceivedDifficulty: rating)
            }
            let viewModel = ProgressViewModel(
                userService: MockUserService(user: MockPersistence.sampleUser),
                workoutLogService: MockWorkoutLogService(logs: logs),
                exerciseService: try MockExerciseService(),
                subscriptionService: MockSubscriptionService(
                    subscription: Subscription(tier: .premium, provider: .apple, expiresAt: nil, trialEndsAt: nil)
                ),
                consistencyService: ConsistencyScoreService(now: { Self.now }, calendar: Self.calendar),
                now: { Self.now },
                calendar: Self.calendar
            )
            await viewModel.load()
            XCTAssertTrue(viewModel.isPremium, "\(mix.name): the deep layer is Premium-only")

            let (host, window) = HostedSurface.host(
                ProgressTabView(viewModel: viewModel), size: CGSize(width: 393, height: 4600)
            )
            defer { HostedSurface.dismantle(window) }
            let spoken = AccessibilityTree.spokenStrings(in: host.view)

            XCTAssertTrue(
                spoken.contains { $0.hasPrefix("How it's felt. \(mix.counts).") },
                "\(mix.name): the \"How it's felt\" card did not render this mix; the tab says \(spoken)"
            )
            for text in spoken {
                let found = Self.forms(engine, foundIn: text)
                XCTAssertTrue(found.isEmpty, "\(mix.name): the Progress tab says \"\(text)\", which contains \(found)")
            }
        }
    }

    // MARK: - Fixtures

    /// A fixed vantage and calendar, so the Progress tab's weeks do not depend on the day or the machine
    /// the suite runs on.
    private static let now = Date(timeIntervalSince1970: 1_791_000_000)

    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 1
        calendar.minimumDaysInFirstWeek = 1
        return calendar
    }()

    nonisolated private static func log(
        daysAgo: Int,
        now: Date,
        _ exercises: [LoggedExercise],
        perceivedDifficulty: PerceivedDifficulty? = nil
    ) throws -> WorkoutLog {
        WorkoutLog(
            id: UUID(),
            workoutId: UUID(),
            completedAt: now.addingTimeInterval(-Double(daysAgo) * 86_400),
            requestedMinutes: 15,
            durationMinutes: 15,
            shape: .blend,
            focusPillar: nil,
            perceivedDifficulty: perceivedDifficulty,
            exercises: exercises
        )
    }

    // MARK: - The shared list

    private struct WordList: Decodable {
        struct Entry: Decodable {
            let word: String
            let forms: [String]
        }

        let words: [Entry]
    }

    /// `<repo>/ios/RepToday/RepTodayTests/CoachRequestVocabularyTests.swift` -> `<repo>`, the same
    /// anchor `EvidenceOutput` and `UITestLaunchGuardTests` use.
    private static let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // RepTodayTests
        .deletingLastPathComponent() // RepToday
        .deletingLastPathComponent() // ios
        .deletingLastPathComponent() // the repo root

    /// Every listed form, or only the forms of the entry `word` names, as runs of whole words.
    /// `StrengthGraduationEvidenceTests` reads the forms of "engine" from here.
    nonisolated static func listedForms(of word: String? = nil) throws -> [[String]] {
        let file = repositoryRoot.appendingPathComponent("proxy/coach-internal-words.json")
        let list = try JSONDecoder().decode(WordList.self, from: Data(contentsOf: file))
        let forms = list.words
            .filter { word == nil || $0.word == word }
            .flatMap(\.forms)
            .map(words(in:))
        XCTAssertFalse(forms.isEmpty, "\(file.path) lists no forms of \(word ?? "any word")")
        return forms
    }

    /// `text` as lowercased whole words, splitting camelCase and punctuation, so "chainPositions" is
    /// "chain", "positions" and "discipline" stays one word. `proxy/test/worker.test.js` splits the
    /// same way.
    nonisolated private static func words(in text: String) -> [String] {
        var spaced = ""
        var previous: Character?
        for character in text {
            if let previous, character.isUppercase, previous.isLowercase || previous.isNumber {
                spaced.append(" ")
            }
            spaced.append(character)
            previous = character
        }
        return spaced.lowercased()
            .split(whereSeparator: { !($0.isLetter || $0.isNumber) })
            .map(String.init)
    }

    /// The listed forms that occur in `text`, each joined back into a phrase, in list order.
    nonisolated static func forms(_ listed: [[String]], foundIn text: String) -> [String] {
        let textWords = words(in: text)
        return listed.filter { form in
            guard !form.isEmpty, form.count <= textWords.count else { return false }
            return (0...(textWords.count - form.count)).contains { start in
                Array(textWords[start..<(start + form.count)]) == form
            }
        }
        .map { $0.joined(separator: " ") }
    }
}
