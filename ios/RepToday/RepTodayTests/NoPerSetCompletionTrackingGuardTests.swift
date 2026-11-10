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
/// `LoggedExercise` is pinned the same way. Beyond its identity and completed sets it carries exactly two
/// kinds of per-move data: ADR-0011's post-session `couldNotFinish` mark (one flag per move, set only after
/// a "too hard" rating), and the prescription facts copied onto the move when it is logged (US-TD02) - the
/// station's `role` and its Earned Reps (`earnedReps` / `earnedDurationSeconds`). Those copied facts
/// describe what was prescribed, not whether it was done, so they are no completion signal. Anything
/// else is refused.
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

    /// The logged move carries its identity, its completed sets, the skip, ADR-0011's post-session
    /// "couldn't finish" mark, and the prescription facts copied from its station (role and Earned Reps).
    /// Any other new field is refused, so a per-set or per-move "did they really do it" record cannot slip
    /// in beside them.
    func testLoggedExerciseCarriesOnlyThePostSessionMarkAndItsPrescriptionFacts() {
        let allowed: Set<String> = [
            "id", "exerciseId", "pillar", "movementPattern", "completedSets", "skipped",
            "couldNotFinish", "role", "earnedReps", "earnedDurationSeconds"
        ]

        let sample = LoggedExercise(
            id: UUID(), exerciseId: "push_up", pillar: .strength, movementPattern: .push,
            completedSets: [], skipped: false
        )
        let labels = Mirror(reflecting: sample).children.compactMap { $0.label }

        XCTAssertEqual(
            Set(labels), allowed,
            """
            `LoggedExercise` gained a field beyond \(allowed.sorted()): \(labels.sorted()). Beyond the \
            session's rating it may carry only ADR-0011's post-session, per-move `couldNotFinish` mark and \
            the prescription facts copied from its station (US-TD02: `role`, `earnedReps`, \
            `earnedDurationSeconds`); a set still records prescribed = performed (US-CC09).
            """
        )
    }
}
