import XCTest
@testable import RepToday

private actor ProofProbeVerifier: CoachRuntimeProofVerifying {
    let failure: Bool
    let hang: Bool
    private(set) var calls = 0
    private var continuation: CheckedContinuation<Void, Never>?
    init(failure: Bool = false, hang: Bool = false) { self.failure = failure; self.hang = hang }
    func verifyProofOnly(timeoutSeconds: Double) async throws {
        calls += 1
        if hang { await withCheckedContinuation { continuation = $0 } }
        if failure { throw NSError(domain: "PRIVATE-PROOF-DETAIL", code: 1) }
    }
    func release() { continuation?.resume(); continuation = nil }
}

@MainActor
final class CoachRuntimeProofProbeTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!
    override func setUp() { super.setUp(); suite = UUID().uuidString; defaults = UserDefaults(suiteName: suite)! }
    override func tearDown() { defaults.removePersistentDomain(forName: suite); defaults = nil; super.tearDown() }

    func testConfigurationAndSeparateConfirmationMakeNoCallsOrSpendMarker() async {
        let verifier = ProofProbeVerifier()
        for (enabled, confirmed, timeout) in [(false, true, 30.0), (true, false, 30), (true, true, 31), (true, true, 0)] {
            let probe = CoachRuntimeProofProbe(enabled: enabled, verifier: verifier, defaults: defaults, timeout: timeout)
            await probe.run(confirmed: confirmed); XCTAssertFalse(probe.attempted); XCTAssertNil(probe.outcome)
        }
        let missing = CoachRuntimeProofProbe(enabled: true, verifier: nil, defaults: defaults)
        await missing.run(confirmed: true); XCTAssertFalse(missing.attempted)
        let calls = await verifier.calls; XCTAssertEqual(calls, 0)
    }
    func testReserveBeforeOperationPersistsAcrossAnotherScreenAndRelaunchAndClearsResult() async {
        let verifier = ProofProbeVerifier(hang: true)
        let probe = CoachRuntimeProofProbe(enabled: true, verifier: verifier, defaults: defaults)
        let run = Task { await probe.run(confirmed: true) }
        while await verifier.calls == 0 { await Task.yield() }
        XCTAssertTrue(probe.attempted); XCTAssertTrue(probe.running)
        let other = CoachRuntimeProofProbe(enabled: true, verifier: verifier, defaults: UserDefaults(suiteName: suite)!)
        XCTAssertFalse(other.available); await other.run(confirmed: true)
        await verifier.release(); await run.value
        XCTAssertEqual(probe.outcome, .admittedReplayDenied)
        probe.close(); XCTAssertNil(probe.outcome); XCTAssertFalse(probe.available)
        let calls = await verifier.calls; XCTAssertEqual(calls, 1)
    }
    func testFailureOutputsOnlyFixedClassAndCannotRetry() async {
        let verifier = ProofProbeVerifier(failure: true)
        let probe = CoachRuntimeProofProbe(enabled: true, verifier: verifier, defaults: defaults)
        await probe.run(confirmed: true); XCTAssertEqual(probe.outcome, .failedUnverified)
        await probe.run(confirmed: true); let calls = await verifier.calls; XCTAssertEqual(calls, 1)
    }
    func testTimeoutAndScreenExitSuppressLateSuccessAndKeepAttemptSpent() async {
        for leave in [false, true] {
            defaults.removePersistentDomain(forName: suite)
            let verifier = ProofProbeVerifier(hang: true)
            let probe = CoachRuntimeProofProbe(enabled: true, verifier: verifier, defaults: defaults, timeout: 0.05)
            let run = Task { await probe.run(confirmed: true) }
            while await verifier.calls == 0 { await Task.yield() }
            if leave { probe.close(); run.cancel() }
            await run.value
            XCTAssertEqual(probe.outcome, leave ? nil : .failedUnverified)
            await verifier.release(); await Task.yield()
            XCTAssertEqual(probe.outcome, leave ? nil : .failedUnverified); XCTAssertTrue(probe.attempted)
        }
    }
}
