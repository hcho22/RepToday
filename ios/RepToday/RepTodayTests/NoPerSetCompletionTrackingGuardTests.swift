import XCTest
@testable import RepToday

/// Fails the **default** `RepToday` test run if the per-set record ever grows a "did they really do it"
/// completion-tracking field (US-CC09, and FR-9).
///
/// The continuous-circuit player is hands-free: an auto-advanced set records prescribed = performed,
/// identical to a tapped completion, and only an explicit **Skip** logs an exercise as not-done. The one
/// adaptation signal into the Asymmetric Ramp (US-E05) is the end-of-session perceived-difficulty rating
/// (US-L02), collected once via `rate`, never per set. A per-set "was this really finished?" / per-set
/// difficulty field on the recorded set would reintroduce exactly the tap-gated, per-rep-verified model
/// the follow-along flow removes - and would quietly become a second, finer difficulty signal the Ramp
/// was never designed to read.
///
/// `CompletedSet` is *the* per-set record (`ActiveSessionViewModel.recordSet` appends one per completed
/// set, and it is what flows into every `LoggedExercise`), so this guard pins its shape by reflection:
/// exactly `reps` and `durationSeconds`, nothing more. This is compile-coupled rather than prose-fragile -
/// adding any per-set completion/difficulty field trips it, the same build-time-fact enforcement pattern
/// as `NoManualModeGuardTests` and `UITestLaunchGuardTests`, living in the routinely-run unit bundle for
/// the same reason (the gate is `-scheme RepToday test`).
///
/// ADR-0011 adds one post-session, per-*move* signal beside the rating: after "too hard" the completion
/// screen asks which moves the user could not finish, stored as `LoggedExercise.couldNotFinish`. The
/// second test pins `LoggedExercise` to its fields plus that one flag, so the narrowing goes no further.
final class NoPerSetCompletionTrackingGuardTests: XCTestCase {

    func testCompletedSetHasNoPerSetCompletionTrackingField() {
        let allowed: Set<String> = ["reps", "durationSeconds"]

        let sample = CompletedSet(reps: 10, durationSeconds: nil)
        let labels = Mirror(reflecting: sample).children.compactMap { $0.label }

        XCTAssertEqual(
            Set(labels), allowed,
            """
            `CompletedSet` gained a field beyond \(allowed.sorted()): \(labels.sorted()). US-CC09 (FR-9) \
            forbids any per-set "did they really do it" / per-set difficulty tracking: an auto-advanced set \
            records prescribed = performed exactly like a tapped one, only an explicit Skip logs not-done, \
            and the end-of-session perceived-difficulty rating (US-L02, `rate`) is the sole adaptation \
            signal into the Asymmetric Ramp. Remove the per-set field - a finer signal is exactly what this \
            guard exists to keep from shipping.
            """
        )
    }

    /// ADR-0011 narrows this guard by exactly one field: `LoggedExercise.couldNotFinish`, the completion
    /// screen's post-session "couldn't finish" mark - one optional flag per *move*, set only after a
    /// "too hard" rating, never per set. Any other new field on the logged move is still refused, so a
    /// per-set or per-move "did they really do it" record cannot slip in beside it.
    func testLoggedExerciseCarriesOnlyThePostSessionCouldNotFinishMark() {
        let allowed: Set<String> = [
            "id", "exerciseId", "pillar", "movementPattern", "completedSets", "skipped", "couldNotFinish"
        ]

        let sample = LoggedExercise(
            id: UUID(), exerciseId: "push_up", pillar: .strength, movementPattern: .push,
            completedSets: [], skipped: false
        )
        let labels = Mirror(reflecting: sample).children.compactMap { $0.label }

        XCTAssertEqual(
            Set(labels), allowed,
            """
            `LoggedExercise` gained a field beyond \(allowed.sorted()): \(labels.sorted()). The only \
            completion signal it may carry beyond the session's rating is ADR-0011's post-session, per-move \
            `couldNotFinish` mark; a set still records prescribed = performed (US-CC09).
            """
        )
    }
}
