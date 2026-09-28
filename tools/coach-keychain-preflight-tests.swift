import Foundation
import LocalAuthentication

private struct SentinelError: Error, CustomStringConvertible {
    var description: String { "NONSECRET_ERROR_SENTINEL account=NONSECRET_ACCOUNT_SENTINEL" }
}
private final class PreflightReaderDouble: RuntimeMigrationReader {
    var reads: [RuntimeMigrationCredential] = []
    var liveBuffers = 0, released = 0, cancellations = 0
    var failAt: RuntimeMigrationCredential?
    var error: Error = SentinelError()
    var beforeRead: (() -> Void)?
    func read(_ item: RuntimeMigrationCredential) throws -> Data {
        precondition(liveBuffers == 0, "previous value must be released before the next read")
        beforeRead?(); reads.append(item)
        if item == failAt { throw error }
        let sentinel = Array(String(repeating: "NONSECRET_VALUE_SENTINEL", count: 100).utf8)
        let pointer = UnsafeMutableRawPointer.allocate(byteCount: sentinel.count, alignment: 1)
        sentinel.withUnsafeBytes { pointer.copyMemory(from: $0.baseAddress!, byteCount: sentinel.count) }
        liveBuffers += 1
        return Data(bytesNoCopy: pointer, count: sentinel.count, deallocator: .custom { pointer, _ in
            pointer.deallocate(); self.liveBuffers -= 1; self.released += 1
        })
    }
    func cancelPendingRead() { cancellations += 1 }
}

func testKeychainPreflight() throws {
    let items = RuntimeMigrationCredential.allCases
    precondition(items.count == 8)
    // Values intentionally do not pass deployment format validation. This is access-only.
    let reader = PreflightReaderDouble()
    var lines: [String] = []
    let progress = RuntimePreflightProgress(emit: { line in
        precondition(reader.liveBuffers == 0, "no value retained at the output boundary")
        lines.append(line)
    })
    precondition(runKeychainPreflight(reader: reader, progress: progress) == 0)
    precondition(reader.reads == items && reader.released == 8 && reader.cancellations == 0)
    precondition(lines.count == 17)
    for (index, item) in items.enumerated() {
        precondition(lines[index * 2].contains("category=\(item.rawValue) event=start"))
        precondition(lines[index * 2 + 1].contains("category=\(item.rawValue) event=completed"))
    }
    precondition(lines.last!.contains("category=all event=success"))

    // Stop at every possible index; unknown Error metadata is never rendered.
    for (index, item) in items.enumerated() {
        for error: Error in [SentinelError(), CoachCredentialReadStatus(status: -25293), RuntimePreflightCancelled()] {
            let reader = PreflightReaderDouble(); reader.failAt = item; reader.error = error
            let progress = RuntimePreflightProgress(emit: { lines.append($0) })
            let expected: Int32 = error is RuntimePreflightCancelled ? 130 : 78
            precondition(runKeychainPreflight(reader: reader, progress: progress) == expected)
            precondition(reader.reads == Array(items.prefix(index + 1)))
            precondition(reader.released == index && reader.liveBuffers == 0 && reader.cancellations == 1)
            precondition(lines.last!.contains("category=\(item.rawValue)"))
            precondition(lines.last!.hasSuffix(error is CoachCredentialReadStatus ? "osstatus=-25293" : "osstatus=unavailable"))
        }
    }
    let pattern = "^preflight category=(all|openAI|clientGate|wafToken|appPrefix|appID|keyID|issuerID|privateKey) event=(start|pending|completed|success|failure|timed_out|cancelled) elapsed_ms=[0-9]+ read_elapsed_ms=[0-9]+ osstatus=(unavailable|-?[0-9]+)$"
    precondition(lines.allSatisfy { $0.range(of: pattern, options: .regularExpression) != nil && !$0.contains("SENTINEL") })

    // Exact-boundary timeout wins even when a read returns; no next item is queried.
    for overall in [false, true] {
        var clock: TimeInterval = 0
        let reader = PreflightReaderDouble()
        reader.beforeRead = { clock += 3 }
        let progress = RuntimePreflightProgress(now: { clock }, readLimit: overall ? 20 : 3,
            overallLimit: overall ? 5 : 30, emit: { _ in })
        precondition(runKeychainPreflight(reader: reader, progress: progress) == 124)
        precondition(reader.reads == Array(items.prefix(overall ? 2 : 1)))
        precondition(reader.liveBuffers == 0 && reader.cancellations == 1)
    }
    var clock: TimeInterval = 0
    var pendingLines: [String] = []
    let pending = RuntimePreflightProgress(now: { clock }, emit: { pendingLines.append($0) })
    precondition(pending.begin(.issuerID)); clock = 5
    precondition(pending.poll() == nil && pendingLines.last!.contains("event=pending"))
    clock = 115
    precondition(pending.poll() == 124 && !pending.completed() && !pending.begin(.privateKey))
    precondition(pendingLines.last!.contains("category=issuerID event=timed_out"))
    let count = pendingLines.count
    pending.fail(SentinelError()); precondition(pending.poll() == 124 && pendingLines.count == count)
    let access = RuntimePreflightAccess(); access.cancel()
    do { try access.begin(LAContext()); preconditionFailure("cancel must win before query") }
    catch is RuntimePreflightCancelled {}

    // Branch spies: malformed/ambiguous native CLI cannot construct either path.
    var preflights = 0, operations = 0
    func route(_ args: [String]) -> Int32 {
        routeRuntimeMigration(args: args, preflight: { preflights += 1; return 0 },
            operation: { _, _, _, _, _ in operations += 1; return 0 })
    }
    let invalid: [[String]] = [[], ["--unknown"], ["--keychain-preflight", "--keychain-preflight"],
        ["--keychain-preflight", "/repo", "/node"], ["--keychain-preflight", "--auth-guard-diagnostics"],
        ["--stage", "--keychain-preflight", "/node"], ["--stage", "/repo", "--keychain-preflight"],
        ["--stage", "/repo", "/node", "--keychain-preflight"], ["--hold", "/repo", "/node", "--auth-guard-diagnostics"],
        ["--stage", "relative", "/node"], ["--stage", "/repo", "/node", "--unknown"]]
    for args in invalid { precondition(route(args) == 64) }
    for flag in ["--stage", "--release", "--hold", "--inspect", "--deploy"] {
        precondition(route(["--keychain-preflight", flag]) == 64)
        precondition(route([flag, "--keychain-preflight"]) == 64)
    }
    for selected in ["--hold", "--verify-candidate", "--verify-restored"] {
        precondition(route([selected, "/repo", "/node", "--final-auth-diagnostics"]) == 64)
    }
    precondition(route(["--stage", "/repo", "/node", "--final-auth-diagnostics", "--final-auth-diagnostics"]) == 64)
    precondition(preflights == 0 && operations == 0)
    precondition(route(["--keychain-preflight"]) == 0 && preflights == 1 && operations == 0)
    for operation in [RuntimeMigrationOperation.stage, .release, .hold] {
        precondition(route([operation.rawValue, "/repo", "/node"]) == 0)
        if operation == .stage || operation == .release { precondition(route([operation.rawValue, "/repo", "/node", "--auth-guard-diagnostics"]) == 0) }
    }
    precondition(preflights == 1 && operations == 5)
    print("passed: preflight eight-item order/discard, all failure indices, closed output, deadlines and CLI isolation")
}
