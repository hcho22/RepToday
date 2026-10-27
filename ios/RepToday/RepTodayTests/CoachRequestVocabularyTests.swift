import XCTest
@testable import RepToday

/// The app's half of one rule: the Coach model is never given a word the app does not show a user.
///
/// A model repeats the words it is given. A Coach reply once described a beginner's standing with
/// words the app never shows in that sense ("line", "unlocked"), and every one of them was in what the
/// model had been handed. The list of such words is `proxy/coach-internal-words.json`; "tier" is not
/// on it, because the Progress tab shows "Tier 2 of 4".
///
/// The rule is held in two suites that read that one list:
///
/// - **Here**, the request is built through the app's own send path (`CoachViewModel.send` over the
///   real catalog) for three users, and pinned to the files under
///   `proxy/test/fixtures/coach-requests/`. The only listed word the app sends is "chain", and only
///   inside two field names; no value it sends, and no movement name it could ever send, is a listed
///   word.
/// - **In `proxy/test/worker.test.js`**, the Worker is run over those same files, and neither the
///   summary it hands the model (which never carries a field name) nor its instructions may contain a
///   listed word.
///
/// When the app's request legitimately changes (a catalog change moves a tier count, say), this suite
/// fails until the fixtures are rebuilt with `REPTODAY_WRITE_EVIDENCE=1`, and the Worker tests then
/// check the new request the same way.
@MainActor
final class CoachRequestVocabularyTests: XCTestCase {

    // MARK: - The users

    private struct Scenario {
        /// The fixture's file name under `proxy/test/fixtures/coach-requests/`.
        let name: String
        let level: FitnessLevel
        let phase: Phase
        /// Made-up text; no real user's words.
        let message: String
        let logs: ([Exercise], Date) throws -> [WorkoutLog]
    }

    private static let scenarios: [Scenario] = [
        // The reported case: a beginner on the first movement of every foundation, nothing harder
        // reached yet, asking how they are doing.
        Scenario(
            name: "beginner-first-tier",
            level: .beginner,
            phase: .discipline,
            message: "How am I doing?",
            logs: { library, now in
                try ["push_wall", "pull_wall_scapular_pull", "squat_wall_sit", "hinge_glute_bridge", "core_forearm_plank"]
                    .enumerated()
                    .map { index, id in
                        try log(daysAgo: index + 1, now: now, [performed(id, in: library)])
                    }
            }
        ),
        // Nothing trained yet: every foundation not started.
        Scenario(
            name: "no-history",
            level: .beginner,
            phase: .discipline,
            message: "Why this workout?",
            logs: { _, _ in [] }
        ),
        // The Strength Phase earned, one foundation climbing, one flat for weeks, two not started, a
        // skipped step and a stretch in the latest session.
        Scenario(
            name: "strength-climbing-and-flat",
            level: .advanced,
            phase: .strength,
            message: "I'm bored, this feels repetitive.",
            logs: { library, now in
                [
                    try log(daysAgo: 42, now: now, [performed("push_wall", in: library)]),
                    try log(daysAgo: 35, now: now, [performed("hinge_glute_bridge", in: library)]),
                    try log(daysAgo: 7, now: now, [performed("push_incline", in: library)]),
                    try log(daysAgo: 3, now: now, [performed("squat_bodyweight", in: library)]),
                    try log(daysAgo: 2, now: now, [
                        performed("hinge_glute_bridge", in: library),
                        performed("mobility_cat_cow", in: library),
                        skipped("core_dead_bug", in: library),
                    ]),
                ]
            }
        ),
    ]

    // MARK: - Tests

    func testEachRequestTheAppBuildsIsTheOneTheWorkerTestsRead() async throws {
        for scenario in Self.scenarios {
            let built = try await builtRequest(for: scenario)
            let fixture = Self.fixturesDirectory.appendingPathComponent("\(scenario.name).json")

            if ProcessInfo.processInfo.environment["REPTODAY_WRITE_EVIDENCE"] == "1" {
                try FileManager.default.createDirectory(at: Self.fixturesDirectory, withIntermediateDirectories: true)
                var text = try XCTUnwrap(String(
                    data: JSONSerialization.data(
                        withJSONObject: built,
                        options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
                    ),
                    encoding: .utf8
                ))
                text += "\n"
                try text.write(to: fixture, atomically: true, encoding: .utf8)
            }

            let committed = try XCTUnwrap(
                JSONSerialization.jsonObject(with: Data(contentsOf: fixture)) as? NSDictionary,
                "\(fixture.path) is not a JSON object"
            )
            XCTAssertEqual(
                built,
                committed,
                """
                The request the app builds for "\(scenario.name)" is no longer the one committed at \
                \(fixture.path), which is what proxy/test/worker.test.js checks the Worker's summary \
                and instructions against. If the change is intended, rebuild the fixtures by running \
                this suite with REPTODAY_WRITE_EVIDENCE=1, then run `npm test` in proxy/.
                """
            )
        }
    }

    func testTheOnlyListedWordTheAppSendsIsInsideTwoFieldNames() async throws {
        let listed = try Self.listedForms()

        for scenario in Self.scenarios {
            let built = try await builtRequest(for: scenario)
            var names: [String] = []
            var values: [String] = []
            Self.collect(built, names: &names, values: &values)

            // No value the app sends is a listed word: what the Worker passes on verbatim (a movement's
            // name) and what it rewrites from an allowlist alike.
            for value in values {
                let found = Self.forms(listed, foundIn: value)
                XCTAssertTrue(found.isEmpty, "\(scenario.name): the app sends \"\(value)\", which contains \(found)")
            }

            // The field names are the app's own code's words. The one listed word among them is
            // "chain", which is why the Worker never hands the request's JSON to the model.
            let namesWithAListedWord = Set(names.filter { !Self.forms(listed, foundIn: $0).isEmpty })
            XCTAssertEqual(
                namesWithAListedWord,
                ["chainPositions", "chainLength"],
                "\(scenario.name): a field name outside the two the Worker is known to replace carries a listed word"
            )
        }
    }

    func testNoMovementNameTheAppCanSendIsAListedWord() async throws {
        let listed = try Self.listedForms()
        let library = try await MockExerciseService().exercises()
        XCTAssertFalse(library.isEmpty)

        // A movement's display name is the one piece of free text the Worker passes to the model
        // unchanged, so it is checked for the whole catalog rather than for three users.
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

    /// The entries whose proof says no string in the app contains them. The app uses its own
    /// words for the same things ("Rep Today", "your current movement", "the area you've gone
    /// longest without"), so a string literal anywhere in the app's sources carrying one of these is
    /// a word the Coach is told never to say, shown on a screen instead.
    private static let absentFromTheApp = ["engine", "deterministic", "stalest", "frontier"]

    func testNoStringTheAppCanShowCarriesAWordItNeverUses() throws {
        let absent = try Self.listedForms(only: Self.absentFromTheApp)
        let sources = try Self.appSwiftSources()
        XCTAssertGreaterThan(sources.count, 100, "the app's sources were not found under \(Self.appSourcesDirectory.path)")

        for file in sources {
            let source = try String(contentsOf: file, encoding: .utf8)
            for literal in Self.stringLiterals(in: source) {
                let found = Self.forms(absent, foundIn: literal.text)
                XCTAssertTrue(
                    found.isEmpty,
                    "\(file.lastPathComponent):\(literal.line) carries \(found): \"\(literal.text)\""
                )
            }
        }
    }

    func testTheStringReaderSeesEveryLiteralAndNoComment() throws {
        let absent = try Self.listedForms(only: Self.absentFromTheApp)
        XCTAssertEqual(absent.count, 8, "the four entries' forms were not all read from the list")

        // Positive controls: a reader that missed any of these shapes would let the scan above pass.
        let sample = ##"""
        // the engine, in a comment
        /* the engine, in a block comment */
        let a = "the engine's easing you back"
        let b = """
            your deterministic workout
            """
        let c = #"{"reply":"\#(reply) your frontier"}"#
        let d = "\(flag ? "stale" : "fresh") sessions"
        """##
        let literals = Self.stringLiterals(in: sample)
        XCTAssertEqual(
            literals.map { Self.forms(absent, foundIn: $0.text) }.filter { !$0.isEmpty },
            [["engine"], ["deterministic"], ["frontier"], ["stale"]]
        )
        XCTAssertEqual(literals.first?.line, 3)
    }

    // MARK: - Building the request through the app

    private actor CapturingTransport: CoachProxyTransport {
        private(set) var lastBody: Data?

        func post(
            to url: URL,
            jsonBody: Data,
            headers: [String: String],
            timeoutSeconds: Double
        ) async throws -> (data: Data, statusCode: Int) {
            lastBody = jsonBody
            return (Data(#"{"reply":"ok"}"#.utf8), 200)
        }
    }

    /// A fixed vantage and calendar, so the weeks the request reports do not depend on the day or the
    /// machine the suite runs on.
    private static let now = Date(timeIntervalSince1970: 1_791_000_000)

    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 1
        calendar.minimumDaysInFirstWeek = 1
        return calendar
    }()

    /// The request body exactly as `CoachViewModel.send` hands it to the transport.
    private func builtRequest(for scenario: Scenario) async throws -> NSDictionary {
        var user = MockPersistence.sampleUser
        user.profile.fitnessLevel = scenario.level
        user.phase = scenario.phase
        let exercises = try MockExerciseService()
        let library = try await exercises.exercises()
        let transport = CapturingTransport()
        let viewModel = CoachViewModel(
            client: CoachProxyClient(
                endpoint: URL(string: "https://proxy.example.com/coach")!,
                safetyIdentifier: testCoachSafetyIdentifier,
                transport: transport
            ),
            userService: MockUserService(user: user),
            workoutLogService: MockWorkoutLogService(logs: try scenario.logs(library, Self.now)),
            exerciseService: exercises,
            now: { Self.now },
            calendar: Self.calendar
        )
        viewModel.grantDataSharingConsent()
        viewModel.draft = scenario.message
        await viewModel.send()

        let captured = await transport.lastBody
        let body = try XCTUnwrap(captured, "\(scenario.name): the send path made no request")
        return try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? NSDictionary)
    }

    nonisolated private static func log(daysAgo: Int, now: Date, _ exercises: [LoggedExercise]) throws -> WorkoutLog {
        WorkoutLog(
            id: UUID(),
            workoutId: UUID(),
            completedAt: now.addingTimeInterval(-Double(daysAgo) * 86_400),
            requestedMinutes: 15,
            durationMinutes: 15,
            shape: .blend,
            focusPillar: nil,
            perceivedDifficulty: nil,
            exercises: exercises
        )
    }

    nonisolated private static func performed(_ id: String, in library: [Exercise]) throws -> LoggedExercise {
        let exercise = try XCTUnwrap(library.first { $0.id == id }, "\(id) is not in the catalog")
        return LoggedExercise(
            id: UUID(),
            exerciseId: exercise.id,
            pillar: exercise.pillar,
            movementPattern: exercise.movementPattern,
            completedSets: [exercise.isHold
                ? CompletedSet(reps: nil, durationSeconds: 20)
                : CompletedSet(reps: 8, durationSeconds: nil)],
            skipped: false
        )
    }

    nonisolated private static func skipped(_ id: String, in library: [Exercise]) throws -> LoggedExercise {
        var exercise = try performed(id, in: library)
        exercise.completedSets = []
        exercise.skipped = true
        return exercise
    }

    // MARK: - The shared list

    private struct WordList: Decodable {
        struct Entry: Decodable {
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

    private static let fixturesDirectory = repositoryRoot
        .appendingPathComponent("proxy/test/fixtures/coach-requests")

    /// Every listed form, as its run of whole words.
    nonisolated private static func listedForms() throws -> [[String]] {
        let file = repositoryRoot.appendingPathComponent("proxy/coach-internal-words.json")
        let list = try JSONDecoder().decode(WordList.self, from: Data(contentsOf: file))
        let forms = list.words.flatMap(\.forms).map(words(in:))
        XCTAssertFalse(forms.isEmpty, "\(file.path) lists no words")
        return forms
    }

    private struct NamedWordList: Decodable {
        struct Entry: Decodable {
            let word: String
            let forms: [String]
        }

        let words: [Entry]
    }

    /// The listed forms of the named entries only, as runs of whole words.
    nonisolated private static func listedForms(only names: [String]) throws -> [[String]] {
        let file = repositoryRoot.appendingPathComponent("proxy/coach-internal-words.json")
        let list = try JSONDecoder().decode(NamedWordList.self, from: Data(contentsOf: file))
        let entries = list.words.filter { names.contains($0.word) }
        XCTAssertEqual(Set(entries.map(\.word)), Set(names), "\(file.path) no longer lists every one of \(names)")
        return entries.flatMap(\.forms).map(words(in:))
    }

    private static let appSourcesDirectory = repositoryRoot.appendingPathComponent("ios/RepToday/RepToday")

    /// Every Swift file the app target compiles.
    nonisolated private static func appSwiftSources() throws -> [URL] {
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(at: appSourcesDirectory, includingPropertiesForKeys: nil))
        return enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
    }

    /// The text of every string literal in Swift `source`, with the line it starts on. Comments are
    /// skipped; plain, multi-line and raw (`#"..."#`) literals are read; an interpolation's own
    /// literals are read as literals of their own.
    nonisolated private static func stringLiterals(in source: String) -> [(line: Int, text: String)] {
        let characters = Array(source)
        var index = 0
        var line = 1
        var found: [(line: Int, text: String)] = []

        func at(_ offset: Int) -> Character? {
            index + offset < characters.count ? characters[index + offset] : nil
        }
        func starts(with text: String) -> Bool {
            text.enumerated().allSatisfy { at($0.offset) == $0.element }
        }
        func advance(_ count: Int = 1) {
            for _ in 0..<count where index < characters.count {
                if characters[index] == "\n" { line += 1 }
                index += 1
            }
        }

        /// Reads code until the end, or until the `)` closing an interpolation when `inInterpolation`.
        func code(inInterpolation: Bool) {
            var depth = 0
            while index < characters.count {
                if starts(with: "//") {
                    while let next = at(0), next != "\n" { advance() }
                } else if starts(with: "/*") {
                    var nesting = 0
                    repeat {
                        if starts(with: "/*") { nesting += 1; advance(2) }
                        else if starts(with: "*/") { nesting -= 1; advance(2) }
                        else { advance() }
                    } while nesting > 0 && index < characters.count
                } else if characters[index] == "#" || characters[index] == "\"" {
                    var hashes = 0
                    while at(hashes) == "#" { hashes += 1 }
                    if at(hashes) == "\"" {
                        advance(hashes)
                        literal(hashes: hashes)
                    } else {
                        advance(max(hashes, 1))
                    }
                } else if characters[index] == "(" {
                    depth += 1
                    advance()
                } else if characters[index] == ")" {
                    if inInterpolation && depth == 0 { advance(); return }
                    depth -= 1
                    advance()
                } else {
                    advance()
                }
            }
        }

        /// Reads one literal whose opening quote is at `index`.
        func literal(hashes: Int) {
            let startLine = line
            let multiline = starts(with: "\"\"\"")
            let quote = multiline ? "\"\"\"" : "\""
            let close = quote + String(repeating: "#", count: hashes)
            let escape = "\\" + String(repeating: "#", count: hashes)
            advance(quote.count)
            var text = ""
            while index < characters.count {
                if starts(with: close) {
                    advance(close.count)
                    break
                }
                if starts(with: escape) {
                    advance(escape.count)
                    if at(0) == "(" {
                        advance()
                        code(inInterpolation: true)
                        text += " "
                    } else {
                        advance()
                    }
                    continue
                }
                text.append(characters[index])
                advance()
            }
            found.append((startLine, text))
        }

        code(inInterpolation: false)
        return found.sorted { $0.line < $1.line }
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
    nonisolated private static func forms(_ listed: [[String]], foundIn text: String) -> [String] {
        let textWords = words(in: text)
        return listed.filter { form in
            guard !form.isEmpty, form.count <= textWords.count else { return false }
            return (0...(textWords.count - form.count)).contains { start in
                Array(textWords[start..<(start + form.count)]) == form
            }
        }
        .map { $0.joined(separator: " ") }
    }

    /// Every field name and every string value in a decoded JSON tree.
    nonisolated private static func collect(_ node: Any, names: inout [String], values: inout [String]) {
        if let dictionary = node as? [String: Any] {
            for (name, child) in dictionary {
                names.append(name)
                collect(child, names: &names, values: &values)
            }
        } else if let array = node as? [Any] {
            for child in array {
                collect(child, names: &names, values: &values)
            }
        } else if let string = node as? String {
            values.append(string)
        }
    }
}
