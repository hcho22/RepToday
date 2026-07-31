import Foundation

/// The one place that decides where a test suite's rendered-UI evidence is written.
///
/// Every evidence suite renders on every run - the renders and the assertions beside them are the
/// gate - but where the bytes land is opt-in:
///
/// - by default, a per-run temporary directory, so a plain `test` never leaves the worktree dirty
///   with re-encoded PNGs and never depends on the machine the evidence was first captured on;
/// - `REPTODAY_WRITE_EVIDENCE=1` points the same writes at the repo's own `artifacts/reports/`,
///   which is how the committed images the PRD and `docs/test-coverage.md` cite are produced -
///   deliberately, by these tests, rather than copied there by hand;
/// - `REPTODAY_EVIDENCE_DIR=<path>` overrides the destination outright.
///
/// **The rule for `REPTODAY_EVIDENCE_DIR`: it names a *root*, never a final directory.** The story
/// folder is appended to it exactly as it is appended to `artifacts/reports/`, so one redirected run
/// lays its output out in the same shape as the committed baselines and stays self-organising by
/// story instead of pouring every suite's renders into one flat directory. All three modes therefore
/// differ only in the root; the `<root>/<story>/<file>.png` shape is invariant.
///
/// The repo root is walked up from `#filePath`, since a test bundle controls neither the working
/// directory nor any repo-relative path:
/// `<repo>/ios/RepToday/RepTodayTests/EvidenceOutput.swift` -> `<repo>/artifacts/reports`.
///
/// New evidence suites call `EvidenceOutput.directory(for:)` rather than copying this resolver.
/// `OnboardingBasicsEvidenceTests` (unmerged, PR #67) still carries its own copy and should adopt
/// this once that branch lands.
enum EvidenceOutput {

    /// Each story keeps its evidence in its own folder, so a render belonging to one story's work
    /// never lands among the ones another story's acceptance notes point a reviewer at.
    enum Story {
        static let perSideSwap = "per-side-swap"
        static let sessionTimer = "us-o03"
        static let progressAnalytics = "us-m02"
    }

    /// The directory `story`'s evidence is written to for this run.
    static func directory(for story: String) -> String {
        (root as NSString).appendingPathComponent(story)
    }

    private static let root: String = {
        let environment = ProcessInfo.processInfo.environment
        if let override = environment["REPTODAY_EVIDENCE_DIR"], !override.isEmpty {
            return override
        }
        if environment["REPTODAY_WRITE_EVIDENCE"] == "1" {
            return URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent() // RepTodayTests
                .deletingLastPathComponent() // RepToday
                .deletingLastPathComponent() // ios
                .deletingLastPathComponent() // the repo root
                .appendingPathComponent("artifacts")
                .appendingPathComponent("reports")
                .path
        }
        return FileManager.default.temporaryDirectory
            .appendingPathComponent("RepTodayEvidence")
            .appendingPathComponent(UUID().uuidString)
            .path
    }()
}
