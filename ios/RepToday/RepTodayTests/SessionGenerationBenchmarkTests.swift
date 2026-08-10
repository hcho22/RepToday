import XCTest
@testable import RepToday

/// Re-runnable latency benchmark for the on-device session-generation claim ("every session is
/// assembled offline in under 100ms", FR-12), the substantiation harness behind
/// `gtm/01-research/session-generation-benchmark-2026-08-10.md`.
///
/// **What it measures.** The exact call the marketing/telemetry number straddles:
/// `WorkoutEngineProtocol.generateWorkout(requestedMinutes:user:recentLogs:sessionPolicy:)` on the
/// production conformer `MockWorkoutEngine` (misleadingly named; it is the real deterministic engine
/// wired in both `ServiceContainer.live()` and `.mock()`), which runs the full Steps 1-7 pipeline
/// through `SessionAssembly.assemble`. This is the same await `ReadyViewModel.generate()` times to
/// emit `generation_ms` on `ready_screen_shown` (US-T09), so the harness benchmarks the claim's own
/// unit rather than a proxy for it.
///
/// **Why this is NOT the authoritative number.** A test bundle runs in the iOS Simulator, which
/// executes on the host Mac's CPU. A Simulator generation time therefore reflects desktop-class
/// silicon, not the slowest supported iPhone (iPhone XS on iOS 17). The percentiles this prints are
/// an *optimistic proxy* and do not satisfy the real-hardware requirement. The harness is written so
/// the SAME test, unchanged, runs on a physical device by passing a device `-destination`; only then
/// is the p95 authoritative. See the record for the PENDING on-device section.
///
/// **Cold vs warm (defined precisely).**
/// - `warm`: one engine constructed once and warmed with a throwaway generation, then N timed
///   generations per duration. Models repeated one-tap duration-chip regeneration inside a live
///   session (`ReadyViewModel.selectDuration`).
/// - `cold`: a freshly constructed `MockWorkoutEngine` per sample over a shared, already-decoded
///   library, timing that engine's first generation. Models the first Ready Screen generation after
///   a fresh launch, where the exercise library is already loaded at app launch (as in production)
///   but the engine instance has done no prior work. Caveat recorded in the doc: after the process
///   itself warms, Swift runtime/type caches are process-global, so in-process `cold` converges
///   toward `warm`; the single genuinely process-cold datapoint is captured separately below as
///   `firstInProcess`, and even that is optimistic versus a true device cold launch.
///
/// The harness is pure measurement: it does not alter engine behavior. It prints a copy-pasteable
/// markdown block delimited by `BENCH_BEGIN`/`BENCH_END` to the test log (a Simulator-hosted bundle
/// inherits no shell environment, so stdout is the transport), plus one loose non-flaky assertion per
/// lane so it is a legitimate, greppable test rather than an assertion-free one.
///
/// **Opt-in.** It is skipped by default (so a plain `xcodebuild test` and the CI `ios` gate never
/// pay its ~17.5k-generation cost); pass `RUN_SESSION_BENCHMARK=1` to `xcodebuild` to run it. The
/// flag reaches the Simulator-hosted process through the `RepToday` scheme's environment (a bundle
/// inherits no shell env), forwarded exactly like `REPTODAY_WRITE_EVIDENCE`.
final class SessionGenerationBenchmarkTests: XCTestCase {

    // MARK: - Tunables

    /// The chip vocabulary spans the whole 5-60 min claim surface; each duration changes how much the
    /// engine assembles (single-focus -> blend-extended), so the distribution is read per duration.
    private let durations = [5, 10, 15, 20, 30, 45, 60]
    /// Warm samples per duration - large enough to read a stable p95 on a fast host.
    private let warmIterations = 2000
    /// Cold samples per duration - each rebuilds the engine, so fewer but still enough for a p95.
    private let coldIterations = 500

    // MARK: - Deterministic fixtures
    //
    // Fixed clock + UTC calendar so inputs are identical run to run and the only variable is host
    // speed. An intermediate user with a few days of mixed history gives Steps 2-6 real staleness and
    // capacity signal to chew on (an empty-history user would under-exercise the pipeline).

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private var asOf: Date {
        calendar.date(from: DateComponents(year: 2026, month: 6, day: 29, hour: 12))!
    }

    private func date(daysAgo: Int) -> Date {
        calendar.date(byAdding: .day, value: -daysAgo, to: asOf)!
    }

    private func benchmarkUser() -> User {
        User(
            id: "bench-user",
            displayName: "Bench",
            createdAt: asOf,
            profile: UserProfile(
                age: 35,
                sex: .other,
                heightCm: 175,
                weightKg: 75,
                fitnessLevel: .intermediate,
                primaryGoal: .stayActive,
                sitsLong: true,
                injuries: [],
                typicalAvailableMinutes: 20
            ),
            phase: .discipline,
            subscription: Subscription(tier: .free, provider: .apple, expiresAt: nil, trialEndsAt: nil),
            consistency: Consistency(
                weeklyGoal: 3,
                score: 50,
                workoutsThisWeek: 1,
                longestChain: 0,
                totalWorkoutsCompleted: 0,
                totalMinutesExercised: 0
            )
        )
    }

    private func log(
        _ exercises: [(id: String, pillar: Pillar, pattern: MovementPattern, reps: Int)],
        daysAgo: Int,
        difficulty: PerceivedDifficulty? = nil
    ) -> WorkoutLog {
        WorkoutLog(
            id: UUID(),
            workoutId: UUID(),
            completedAt: date(daysAgo: daysAgo),
            requestedMinutes: 20,
            durationMinutes: 20,
            shape: .blend,
            focusPillar: nil,
            perceivedDifficulty: difficulty,
            exercises: exercises.map { entry in
                LoggedExercise(
                    id: UUID(),
                    exerciseId: entry.id,
                    pillar: entry.pillar,
                    movementPattern: entry.pattern,
                    completedSets: [
                        CompletedSet(reps: entry.reps, durationSeconds: nil),
                        CompletedSet(reps: entry.reps, durationSeconds: nil),
                        CompletedSet(reps: entry.reps, durationSeconds: nil),
                    ],
                    skipped: false
                )
            }
        )
    }

    private func history() -> [WorkoutLog] {
        [
            log([
                ("push_standard", .strength, .push, 12),
                ("squat_bodyweight", .strength, .squat, 15),
            ], daysAgo: 2, difficulty: .justRight),
            log([
                ("mobility_cat_cow", .mobility, .mobility, 10),
            ], daysAgo: 4),
        ]
    }

    /// A fresh production engine over the shared, already-validated library, with the clock pinned so
    /// two runs assemble the same session and only speed varies.
    private func makeEngine(library: [Exercise]) -> MockWorkoutEngine {
        let exerciseService = try! MockExerciseService(library: library)
        let fixedNow = asOf
        return MockWorkoutEngine(exerciseService: exerciseService, now: { fixedNow })
    }

    // MARK: - Timing

    /// Monotonic wall-time of one `generateWorkout`, in milliseconds. Uses `DispatchTime.uptime`
    /// (the same clock the existing `testGenerationLatencyUnder100ms` uses), which does not drift with
    /// the calendar or pause across suspensions.
    private func timeGenerationMs(_ engine: MockWorkoutEngine, minutes: Int, user: User, logs: [WorkoutLog]) async -> Double {
        let start = DispatchTime.now()
        _ = try! await engine.generateWorkout(
            requestedMinutes: minutes,
            user: user,
            recentLogs: logs,
            sessionPolicy: .default
        )
        return Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
    }

    // MARK: - Percentiles

    /// Nearest-rank percentile on an already-sorted ascending array: p in [0,1] -> the value at rank
    /// ceil(p*n). p95 is `percentile(sorted, 0.95)`; this is the headline the claim is judged on.
    private func percentile(_ sorted: [Double], _ p: Double) -> Double {
        guard !sorted.isEmpty else { return .nan }
        if p <= 0 { return sorted.first! }
        if p >= 1 { return sorted.last! }
        let rank = Int((p * Double(sorted.count)).rounded(.up))
        return sorted[min(max(rank - 1, 0), sorted.count - 1)]
    }

    private struct Row {
        let lane: String
        let minutes: Int
        let count: Int
        let p50: Double
        let p95: Double
        let max: Double
    }

    private func summarize(lane: String, minutes: Int, samples: [Double]) -> Row {
        let sorted = samples.sorted()
        return Row(
            lane: lane,
            minutes: minutes,
            count: sorted.count,
            p50: percentile(sorted, 0.50),
            p95: percentile(sorted, 0.95),
            max: sorted.last ?? .nan
        )
    }

    // MARK: - The benchmark

    func testSessionGenerationLatencyBenchmark() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["RUN_SESSION_BENCHMARK"] == "1", "opt-in latency benchmark; pass RUN_SESSION_BENCHMARK=1 to xcodebuild to run")
        let library = try await MockExerciseService().exercises()
        let user = benchmarkUser()
        let logs = history()

        // Library load (JSON decode + integrity validation): the one-time launch cost paid before the
        // first generation, reported as context - production loads this once at app launch, not per
        // generation, so it is deliberately outside the timed `generateWorkout` region.
        let libLoadStart = DispatchTime.now()
        _ = try MockExerciseService(library: library)
        let libraryLoadMs = Double(DispatchTime.now().uptimeNanoseconds - libLoadStart.uptimeNanoseconds) / 1_000_000

        // First-in-process: the single genuinely cold generation per duration, captured before any
        // warm-up so process-global type caches are cold. N=1 per duration, high variance by nature;
        // the closest in-process analog to a true device cold launch (still optimistic on desktop
        // silicon). Captured on fresh engines, in duration order, before the warm/cold loops warm the
        // process.
        var firstInProcess: [Int: Double] = [:]
        for minutes in durations {
            let engine = makeEngine(library: library)
            firstInProcess[minutes] = await timeGenerationMs(engine, minutes: minutes, user: user, logs: logs)
        }

        var rows: [Row] = []

        // COLD: fresh engine per sample, shared pre-decoded library, first generation timed.
        for minutes in durations {
            var samples: [Double] = []
            samples.reserveCapacity(coldIterations)
            for _ in 0..<coldIterations {
                let engine = makeEngine(library: library)
                samples.append(await timeGenerationMs(engine, minutes: minutes, user: user, logs: logs))
            }
            rows.append(summarize(lane: "cold", minutes: minutes, samples: samples))
        }

        // WARM: one engine, warmed once, then repeated timed generations.
        for minutes in durations {
            let engine = makeEngine(library: library)
            _ = await timeGenerationMs(engine, minutes: minutes, user: user, logs: logs) // warm-up, discarded
            var samples: [Double] = []
            samples.reserveCapacity(warmIterations)
            for _ in 0..<warmIterations {
                samples.append(await timeGenerationMs(engine, minutes: minutes, user: user, logs: logs))
            }
            rows.append(summarize(lane: "warm", minutes: minutes, samples: samples))
        }

        emitReport(rows: rows, firstInProcess: firstInProcess, libraryLoadMs: libraryLoadMs)

        // Loose, non-flaky guards so this is a real test, not an assertion-free print. These assert the
        // harness actually ran and produced finite numbers - NOT a device latency gate (that lives in
        // the on-device record, not here, precisely because a Simulator number cannot substantiate it).
        let warmRows = rows.filter { $0.lane == "warm" }
        let coldRows = rows.filter { $0.lane == "cold" }
        XCTAssertEqual(warmRows.count, durations.count, "expected one warm row per duration")
        XCTAssertEqual(coldRows.count, durations.count, "expected one cold row per duration")
        for row in rows {
            XCTAssertEqual(row.count, row.lane == "warm" ? warmIterations : coldIterations, "\(row.lane) \(row.minutes)min sample count")
            XCTAssertTrue(row.p95.isFinite && row.p95 >= 0, "\(row.lane) \(row.minutes)min p95 must be a finite, non-negative latency")
        }
    }

    // MARK: - Report emission

    private func fmt(_ ms: Double) -> String {
        String(format: "%.4f", ms)
    }

    private func emitReport(rows: [Row], firstInProcess: [Int: Double], libraryLoadMs: Double) {
        let info = ProcessInfo.processInfo
        let mem = Double(info.physicalMemory) / 1_073_741_824
        var out = "\nBENCH_BEGIN\n"
        out += "## Session-generation latency benchmark (proxy run)\n\n"
        out += "- Measured call: `MockWorkoutEngine.generateWorkout(requestedMinutes:user:recentLogs:sessionPolicy:)` -> `SessionAssembly.assemble` (Steps 1-7)\n"
        out += "- OS/runtime: \(info.operatingSystemVersionString)\n"
        out += "- Host physical memory: \(String(format: "%.1f", mem)) GiB\n"
        out += "- Warm iterations/duration: \(warmIterations); cold iterations/duration: \(coldIterations)\n"
        out += "- Percentile method: nearest-rank (p95 = value at rank ceil(0.95*n))\n"
        out += "- Library load (decode + validate, one-time, outside timed region): \(fmt(libraryLoadMs)) ms\n\n"
        out += "| lane | minutes | n | p50 ms | p95 ms | max ms |\n"
        out += "| --- | --- | --- | --- | --- | --- |\n"
        for lane in ["cold", "warm"] {
            for row in rows where row.lane == lane {
                out += "| \(row.lane) | \(row.minutes) | \(row.count) | \(fmt(row.p50)) | \(fmt(row.p95)) | \(fmt(row.max)) |\n"
            }
        }
        out += "\n**First-in-process (single genuinely cold generation per duration, N=1 each):**\n\n"
        out += "| minutes | ms |\n| --- | --- |\n"
        for minutes in durations.sorted() {
            out += "| \(minutes) | \(fmt(firstInProcess[minutes] ?? .nan)) |\n"
        }
        // Headline extraction: worst p95 across the whole range, per lane.
        let coldP95 = rows.filter { $0.lane == "cold" }.map { $0.p95 }.max() ?? .nan
        let warmP95 = rows.filter { $0.lane == "warm" }.map { $0.p95 }.max() ?? .nan
        out += "\n**Worst-case p95 across 5-60 min:** cold = \(fmt(coldP95)) ms, warm = \(fmt(warmP95)) ms (budget 100 ms).\n"
        out += "BENCH_END\n"
        print(out)
    }
}
