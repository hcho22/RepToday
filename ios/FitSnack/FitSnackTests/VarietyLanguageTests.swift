import XCTest
@testable import FitSnack

/// Tests US-G03: the Variety Language slice.
///
/// The deterministic template (`VarietyLanguage`) is the source of truth for the contrast - it reads
/// the lead pillar straight off the assembled `Workout` and the preceding `WorkoutLog`, so the line
/// can only name a contrast the engine actually produced. The resolver (`VarietyLanguageResolver`)
/// composes the optional LLM slice (US-N05) over that template and must fall back to it on any
/// failure, offline state, or a warmed-up user, never blocking.
///
/// Coverage mirrors the PRD acceptance criteria: template output offline; graceful fallback on a
/// simulated proxy failure; the produced contrast matches the assembled session; and the honesty
/// guarantees (no fabricated contrast, no `why` callback).
final class VarietyLanguageTests: XCTestCase {

    // MARK: - Fixtures

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private var asOf: Date {
        calendar.date(from: DateComponents(year: 2026, month: 6, day: 29, hour: 12))!
    }

    private func library() async throws -> [Exercise] {
        try await MockExerciseService().exercises()
    }

    private func user(coldStartActive: Bool = true) -> User {
        var user = User(
            id: "u1",
            displayName: "Test",
            createdAt: asOf,
            profile: UserProfile(
                age: 35,
                sex: .other,
                heightCm: 175,
                weightKg: 75,
                fitnessLevel: .beginner,
                primaryGoal: .stayActive,
                sitsLong: true,
                injuries: [],
                typicalAvailableMinutes: 8
            ),
            phase: .discipline,
            subscription: Subscription(tier: .free, provider: .apple, expiresAt: nil, trialEndsAt: nil),
            consistency: Consistency(
                weeklyGoal: 3,
                score: 50,
                workoutsThisWeek: 0,
                longestChain: 0,
                totalWorkoutsCompleted: 0,
                totalMinutesExercised: 0
            )
        )
        user.coldStart = User.ColdStart(sessionsLogged: 1, active: coldStartActive)
        return user
    }

    /// A minimal single-focus workout leading with `pillar` (a warm-up plus one training block).
    private func singleFocusWorkout(_ pillar: Pillar) -> Workout {
        let category: ExerciseCategory
        switch pillar {
        case .strength: category = .strength
        case .mobility: category = .mobility
        case .primal: category = .primal
        }
        return Workout(
            id: UUID(),
            createdAt: asOf,
            shape: .singleFocus,
            focusPillar: pillar,
            requestedMinutes: 8,
            blocks: [
                WorkoutBlock(id: UUID(), title: "Warm-Up", category: .warmup, exercises: []),
                WorkoutBlock(id: UUID(), title: "Training", category: category, exercises: []),
            ]
        )
    }

    /// A single-focus log leading with `pillar`, completed `daysAgo` before `asOf`.
    private func singleFocusLog(_ pillar: Pillar, daysAgo: Int) -> WorkoutLog {
        WorkoutLog(
            id: UUID(),
            workoutId: UUID(),
            completedAt: calendar.date(byAdding: .day, value: -daysAgo, to: asOf)!,
            requestedMinutes: 8,
            durationMinutes: 8,
            shape: .singleFocus,
            focusPillar: pillar,
            perceivedDifficulty: nil,
            exercises: []
        )
    }

    private func loggedExercise(_ pillar: Pillar, pattern: MovementPattern, skipped: Bool = false) -> LoggedExercise {
        LoggedExercise(
            id: UUID(),
            exerciseId: "\(pillar.rawValue)_\(pattern.rawValue)",
            pillar: pillar,
            movementPattern: pattern,
            completedSets: [CompletedSet(reps: 10, durationSeconds: nil)],
            skipped: skipped
        )
    }

    // MARK: - Template line (offline, deterministic)

    /// PRD validation: offline, a mobility session following a strength session produces the correct
    /// template line, instantly and template-sourced.
    func testTemplateNamesContrastOffline() {
        let note = VarietyLanguage.templatedNote(
            for: singleFocusWorkout(.mobility),
            previousLog: singleFocusLog(.strength, daysAgo: 1)
        )
        XCTAssertEqual(note?.source, .template)
        XCTAssertEqual(note?.text, "Today's a mobility day - yesterday was strength")
    }

    /// The first session has nothing to contrast against, so it is only named - never a fabricated
    /// "yesterday".
    func testNoPriorSessionNamesOnlyToday() {
        let note = VarietyLanguage.templatedNote(for: singleFocusWorkout(.strength), previousLog: nil)
        XCTAssertEqual(note?.text, "Today's a strength day")
        XCTAssertFalse(note?.text.localizedCaseInsensitiveContains("yesterday") ?? true)
    }

    /// When today leads with the same pillar as the last session there is no contrast to claim, so
    /// the "yesterday" clause is dropped rather than asserting a difference that did not happen.
    func testSamePillarClaimsNoContrast() {
        let note = VarietyLanguage.templatedNote(
            for: singleFocusWorkout(.strength),
            previousLog: singleFocusLog(.strength, daysAgo: 1)
        )
        XCTAssertEqual(note?.text, "Today's a strength day")
        XCTAssertNil(VarietyLanguage.contrast(
            for: singleFocusWorkout(.strength),
            previousLog: singleFocusLog(.strength, daysAgo: 1)
        )?.yesterday)
    }

    /// Every first-class pillar has a readable, distinct label.
    func testPillarLabels() {
        XCTAssertEqual(VarietyLanguage.label(for: .strength), "strength")
        XCTAssertEqual(VarietyLanguage.label(for: .mobility), "mobility")
        XCTAssertEqual(VarietyLanguage.label(for: .primal), "primal")
    }

    /// The most-recent log is the one contrasted, regardless of input order.
    func testMostRecentLogIsTheContrast() {
        let logs = [
            singleFocusLog(.mobility, daysAgo: 5),
            singleFocusLog(.strength, daysAgo: 1), // most recent
            singleFocusLog(.primal, daysAgo: 9),
        ]
        let note = VarietyLanguage.templatedNote(for: singleFocusWorkout(.mobility), recentLogs: logs)
        XCTAssertEqual(note?.text, "Today's a mobility day - yesterday was strength")
    }

    // MARK: - Lead pillar of a blend log

    /// A blend log records no single focus; the lead is the most-worked pillar, skips excluded.
    func testBlendLogLeadIsMostWorkedPillar() {
        let log = WorkoutLog(
            id: UUID(),
            workoutId: UUID(),
            completedAt: asOf,
            requestedMinutes: 30,
            durationMinutes: 30,
            shape: .blend,
            focusPillar: nil,
            perceivedDifficulty: nil,
            exercises: [
                loggedExercise(.strength, pattern: .push),
                loggedExercise(.strength, pattern: .squat),
                loggedExercise(.mobility, pattern: .mobility),
                loggedExercise(.primal, pattern: .locomotion, skipped: true), // excluded
            ]
        )
        XCTAssertEqual(VarietyLanguage.leadPillar(of: log), .strength)
    }

    // MARK: - Contrast matches the assembled session (end-to-end)

    /// The contrast reads the true lead pillar off the engine's own output: the "today" pillar always
    /// matches the assembled session's focus, never a guess.
    func testContrastMatchesAssembledSession() async throws {
        let library = try await library()
        let policy = SessionPolicy.seeded(forFitnessLevel: .beginner)
        let workout = SessionAssembly.assemble(
            requestedMinutes: 8,
            user: user(),
            library: library,
            recentLogs: [],
            sessionPolicy: policy,
            asOf: asOf,
            calendar: calendar
        )
        let today = try XCTUnwrap(VarietyLanguage.leadPillar(of: workout))
        XCTAssertEqual(today, workout.focusPillar, "the named pillar must be the one the engine actually assembled")

        let note = try XCTUnwrap(VarietyLanguage.templatedNote(for: workout, previousLog: nil))
        XCTAssertTrue(note.text.contains(VarietyLanguage.label(for: today)), note.text)
    }

    /// A degenerate session with no training block has no lead pillar, so no note is produced rather
    /// than an empty or false line.
    func testWarmupOnlySessionProducesNoNote() {
        let workout = Workout(
            id: UUID(),
            createdAt: asOf,
            shape: .singleFocus,
            focusPillar: nil,
            requestedMinutes: 5,
            blocks: [WorkoutBlock(id: UUID(), title: "Warm-Up", category: .warmup, exercises: [])]
        )
        XCTAssertNil(VarietyLanguage.templatedNote(for: workout, previousLog: nil))
    }

    // MARK: - Resolver: fallback and LLM path

    /// A provider that always throws, simulating an unreachable/timed-out proxy.
    private struct FailingProvider: VarietyLanguageProvider {
        struct Boom: Error {}
        func line(for contrast: VarietyLanguage.SessionContrast, user: User) async throws -> String {
            throw Boom()
        }
    }

    /// A provider that returns a fixed LLM-authored line.
    private struct StubProvider: VarietyLanguageProvider {
        let text: String
        func line(for contrast: VarietyLanguage.SessionContrast, user: User) async throws -> String {
            text
        }
    }

    /// Offline (the default), the resolver returns the template even when a provider is present.
    func testResolverOfflineReturnsTemplate() async {
        let resolver = VarietyLanguageResolver(provider: StubProvider(text: "LLM line"), isOnline: { false })
        let note = await resolver.note(
            for: singleFocusWorkout(.mobility),
            previousLog: singleFocusLog(.strength, daysAgo: 1),
            user: user()
        )
        XCTAssertEqual(note?.source, .template)
        XCTAssertEqual(note?.text, "Today's a mobility day - yesterday was strength")
    }

    /// PRD validation: on a simulated proxy failure the resolver falls back to the template with no
    /// error and no blocking.
    func testResolverFallsBackToTemplateOnProviderFailure() async {
        let resolver = VarietyLanguageResolver(provider: FailingProvider(), isOnline: { true })
        let note = await resolver.note(
            for: singleFocusWorkout(.mobility),
            previousLog: singleFocusLog(.strength, daysAgo: 1),
            user: user()
        )
        XCTAssertEqual(note?.source, .template)
        XCTAssertEqual(note?.text, "Today's a mobility day - yesterday was strength")
    }

    /// Online, cold-start-active, and a working provider: the LLM line is used and marked `.llm`.
    func testResolverUsesLLMWhenOnlineAndColdStart() async {
        let resolver = VarietyLanguageResolver(provider: StubProvider(text: "A fresh take on today"), isOnline: { true })
        let note = await resolver.note(
            for: singleFocusWorkout(.mobility),
            previousLog: singleFocusLog(.strength, daysAgo: 1),
            user: user(coldStartActive: true)
        )
        XCTAssertEqual(note?.source, .llm)
        XCTAssertEqual(note?.text, "A fresh take on today")
    }

    /// A warmed-up user (cold-start retired) never triggers the LLM slice, even online.
    func testResolverSkipsLLMOnceColdStartRetires() async {
        let resolver = VarietyLanguageResolver(provider: StubProvider(text: "LLM line"), isOnline: { true })
        let note = await resolver.note(
            for: singleFocusWorkout(.mobility),
            previousLog: singleFocusLog(.strength, daysAgo: 1),
            user: user(coldStartActive: false)
        )
        XCTAssertEqual(note?.source, .template)
    }

    /// An empty LLM line is treated as a failure and falls back to the template.
    func testResolverFallsBackWhenLLMReturnsEmpty() async {
        let resolver = VarietyLanguageResolver(provider: StubProvider(text: "   "), isOnline: { true })
        let note = await resolver.note(
            for: singleFocusWorkout(.mobility),
            previousLog: singleFocusLog(.strength, daysAgo: 1),
            user: user()
        )
        XCTAssertEqual(note?.source, .template)
        XCTAssertEqual(note?.text, "Today's a mobility day - yesterday was strength")
    }

    /// With no provider wired (the MVP default), the resolver is template-only.
    func testResolverWithoutProviderIsTemplateOnly() async {
        let resolver = VarietyLanguageResolver()
        let note = await resolver.note(
            for: singleFocusWorkout(.primal),
            previousLog: singleFocusLog(.mobility, daysAgo: 1),
            user: user()
        )
        XCTAssertEqual(note?.source, .template)
        XCTAssertEqual(note?.text, "Today's a primal day - yesterday was mobility")
    }

    // MARK: - Determinism

    func testDeterministic() {
        let workout = singleFocusWorkout(.mobility)
        let log = singleFocusLog(.strength, daysAgo: 1)
        let a = VarietyLanguage.templatedNote(for: workout, previousLog: log)
        let b = VarietyLanguage.templatedNote(for: workout, previousLog: log)
        XCTAssertEqual(a, b)
    }
}
