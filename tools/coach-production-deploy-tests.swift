import Foundation
import AppKit

// Non-secret in-memory doubles only. No NativeCoachCredentialReader is constructed here.
final class DoubleReader: CoachCredentialReader {
    var reads: [CoachCredential] = []
    var failAt: CoachCredential?
    var malformedAt: CoachCredential?
    func read(_ item: CoachCredential) throws -> Data {
        reads.append(item)
        if item == failAt { throw CoachDeployFailure.retrieval }
        if item == malformedAt { return Data("malformed-double".utf8) }
        switch item {
        case .openAI: return Data("sk-NONSECRET_TEST_DOUBLE_1234567890".utf8)
        case .clientGate: return Data(String(repeating: "0", count: 64).utf8)
        case .wafToken: return Data("NONSECRET_WAF_TEST_DOUBLE_1234567890".utf8)
        }
    }
}

final class DoubleCoordinator: CoachDeploymentCoordinator {
    var calls = 0
    var expected = Set(CoachCredential.allCases)
    func run(_ credentials: [CoachCredential: Data]) throws -> String {
        calls += 1
        precondition(Set(credentials.keys) == expected)
        precondition(credentials.allSatisfy { $0.key.accepts($0.value) })
        return "non-secret double completed"
    }
}

// Model an authorization read that needs a visible owner and a main-queue callback.
// This never constructs an LAContext, calls Security.framework, or accesses Keychain.
private final class PresentationObservation: @unchecked Sendable {
    private let lock = NSLock()
    private var presented = false
    func record(_ value: Bool) { lock.lock(); presented = value; lock.unlock() }
    func value() -> Bool { lock.lock(); defer { lock.unlock() }; return presented }
}

private struct PresentationRequiredReader: CoachCredentialReader {
    func read(_ item: CoachCredential) throws -> Data {
        guard !Thread.isMainThread else { throw CoachDeployFailure.retrieval }
        let observation = PresentationObservation()
        let callback = DispatchSemaphore(value: 0)
        DispatchQueue.main.async {
            let app = NSApplication.shared
            let visible = app.activationPolicy() == .accessory && app.windows.contains {
                $0.identifier == NSUserInterfaceItemIdentifier("RepTodayCoachKeychainAccess") && $0.isVisible
            }
            observation.record(visible)
            callback.signal()
        }
        guard callback.wait(timeout: .now() + 3) == .success && observation.value() else {
            throw CoachDeployFailure.retrieval
        }
        guard item == .wafToken else { throw CoachDeployFailure.retrieval }
        return Data("NONSECRET_WAF_TEST_DOUBLE_1234567890".utf8)
    }
}

@main
struct CoachDeploymentTests {
    static func main() throws {
        let reader = DoubleReader(), coordinator = DoubleCoordinator()
        let result = try deployCoach(reader: reader, coordinator: coordinator)
        precondition(result == "non-secret double completed")
        precondition(reader.reads == CoachCredential.allCases && coordinator.calls == 1)
        // The Foundation-only call pattern cannot satisfy the modeled presentation requirement.
        let directCoordinator = DoubleCoordinator()
        directCoordinator.expected = [.wafToken]
        do {
            _ = try deployCoach(reader: PresentationRequiredReader(), coordinator: directCoordinator, operation: .inspect)
            preconditionFailure("direct main-thread read must fail the presentation counterfactual")
        } catch CoachDeployFailure.retrieval {}
        precondition(directCoordinator.calls == 0)
        // Change only presentation: a real AppKit modal is visible, its main loop services the
        // callback, the delegated read runs off-main, and only the non-secret WAF double is used.
        let presentedCoordinator = DoubleCoordinator()
        presentedCoordinator.expected = [.wafToken]
        _ = try deployCoach(reader: AppKitCoachCredentialReader(reader: PresentationRequiredReader()),
            coordinator: presentedCoordinator, operation: .inspect)
        precondition(presentedCoordinator.calls == 1)
        precondition(!NSApplication.shared.windows.contains {
            $0.identifier == NSUserInterfaceItemIdentifier("RepTodayCoachKeychainAccess") && $0.isVisible
        })
        let failedReader = DoubleReader(), failedCoordinator = DoubleCoordinator()
        failedReader.failAt = .wafToken
        failedCoordinator.expected = [.wafToken]
        do {
            _ = try deployCoach(reader: AppKitCoachCredentialReader(reader: failedReader),
                coordinator: failedCoordinator, operation: .inspect)
            preconditionFailure("presented read failure must still stop before the coordinator")
        } catch CoachDeployFailure.retrieval {}
        precondition(failedCoordinator.calls == 0 && failedReader.reads == [.wafToken])
        let inspectReader = DoubleReader(), inspectCoordinator = DoubleCoordinator()
        inspectReader.failAt = .openAI
        inspectCoordinator.expected = [.wafToken]
        _ = try deployCoach(reader: inspectReader, coordinator: inspectCoordinator, operation: .inspect)
        precondition(inspectReader.reads == [.wafToken] && inspectCoordinator.calls == 1)
        for failed in CoachCredential.allCases {
            let reader = DoubleReader(), coordinator = DoubleCoordinator()
            reader.failAt = failed
            do { _ = try deployCoach(reader: reader, coordinator: coordinator); preconditionFailure("retrieval must stop") }
            catch CoachDeployFailure.retrieval {}
            precondition(coordinator.calls == 0)
            precondition(reader.reads.last == failed)
        }
        for malformed in CoachCredential.allCases {
            let reader = DoubleReader(), coordinator = DoubleCoordinator()
            reader.malformedAt = malformed
            do { _ = try deployCoach(reader: reader, coordinator: coordinator); preconditionFailure("format must stop") }
            catch CoachDeployFailure.format {}
            precondition(coordinator.calls == 0 && reader.reads.last == malformed)
        }
        precondition(CommandLine.arguments.count == 3)
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let node = URL(fileURLWithPath: CommandLine.arguments[2])
        let fixture = root.appendingPathComponent("build/coach-native-double", isDirectory: true)
        let tools = fixture.appendingPathComponent("tools", isDirectory: true)
        try FileManager.default.createDirectory(at: tools, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixture) }
        let entry = tools.appendingPathComponent("coach-production-deploy.mjs")
        let native = LocalNodeCoordinator(repository: fixture, node: node)
        // Test the actual anonymous pipe without displaying any doubles or packet contents.
        let success = """
        let packet = ''; for await (const bytes of process.stdin) packet += bytes;
        const credentials = JSON.parse(packet);
        if (Object.keys(credentials).sort().join(',') !== 'clientGate,openAI,wafToken') process.exit(78);
        if (process.argv.length !== 3 || process.argv[2] !== '--deploy') process.exit(78);
        if (Object.values(credentials).some(value => process.argv.includes(value) || Object.values(process.env).includes(value))) process.exit(78);
        console.log('confirmed: approved account, zone and Worker target');
        console.log('protected: hostname held closed; path and rate rules verified');
        console.log('staged: Worker has no persistence, logs or development URLs');
        console.log('deployed: reptoday-variety-language-proxy https://coach.reptoday.app/coach; live model QA pending');
        """
        try Data(success.utf8).write(to: entry)
        let liveDouble = try deployCoach(reader: DoubleReader(), coordinator: native)
        precondition(liveDouble.hasSuffix("live model QA pending"))
        // An accidental child echo is rejected entirely, rather than forwarded to terminal output.
        try Data("for await (const bytes of process.stdin) {}\nconsole.log('NONSECRET_UNEXPECTED_DIAGNOSTIC');".utf8).write(to: entry)
        do { _ = try deployCoach(reader: DoubleReader(), coordinator: native); preconditionFailure("unexpected output must stop") }
        catch CoachDeployFailure.coordinator {}
        try Data("for await (const bytes of process.stdin) {}\nconsole.log('blocked: scope'); process.exitCode=78;".utf8).write(to: entry)
        let blocked = try deployCoach(reader: DoubleReader(), coordinator: native)
        precondition(blocked == "blocked: dedicated deployment helper stopped (scope); inspect configuration without printing credentials")
        let gateLine = "gate: probe missing-authorization failure json status 403 redirected no contract non-json"
        let gateFailure = """
        const { gateProbes, gateFailureLine } = await import(new URL('../../../tools/coach-production-deploy.mjs', import.meta.url));
        let packet = ''; for await (const bytes of process.stdin) packet += bytes;
        const credentials = JSON.parse(packet);
        console.log('confirmed: approved account, zone and Worker target');
        try {
          await gateProbes(credentials.clientGate, async () => new Response('<html>' + credentials.openAI + '</html>', { status: 403 }));
          process.exitCode = 1;
        } catch (error) {
          console.log(gateFailureLine(error));
          console.log('blocked: gate');
          process.exitCode = 78;
        }
        """
        try Data(gateFailure.utf8).write(to: entry)
        let diagnosed = try deployCoach(reader: DoubleReader(), coordinator: native)
        precondition(diagnosed == "blocked: dedicated deployment helper stopped (gate); inspect configuration without printing credentials\n" + gateLine)
        // The blocked prefix preserves the production executable's existing exit-78 rule.
        precondition(diagnosed.hasPrefix("blocked:"))
        precondition(!diagnosed.contains("confirmed:") && !diagnosed.contains("sk-NONSECRET"))
        let rejected: [[String]] = [
            [gateLine.replacingOccurrences(of: "status 403", with: "status NONSECRET_PRIVATE_VALUE"), "blocked: gate"],
            [gateLine.replacingOccurrences(of: "status 403", with: "status 600"), "blocked: gate"],
            [gateLine.replacingOccurrences(of: "status 403", with: "status 0403"), "blocked: gate"],
            [gateLine.replacingOccurrences(of: "failure json", with: "failure NONSECRET_EXCEPTION"), "blocked: gate"],
            [gateLine.replacingOccurrences(of: "contract non-json", with: "contract NONSECRET_BODY"), "blocked: gate"],
            [gateLine + " NONSECRET_HEADER", "blocked: gate"],
            [gateLine, "NONSECRET_PRIVATE_BODY", "blocked: gate"],
            [gateLine, gateLine, "blocked: gate"],
            [gateLine, "blocked: scope"]
        ]
        for lines in rejected {
            let encoded = String(data: try JSONSerialization.data(withJSONObject: lines), encoding: .utf8)!
            let child = "for await (const bytes of process.stdin) {}\nfor (const line of \(encoded)) console.log(line); process.exitCode=78;"
            try Data(child.utf8).write(to: entry)
            do {
                _ = try deployCoach(reader: DoubleReader(), coordinator: native)
                preconditionFailure("arbitrary or mixed diagnostic output must be rejected entirely")
            } catch CoachDeployFailure.coordinator {}
        }
        try Data((success + "\nconsole.log('\(gateLine)');").utf8).write(to: entry)
        do {
            _ = try deployCoach(reader: DoubleReader(), coordinator: native)
            preconditionFailure("a diagnostic must not turn a successful child exit into an accepted deployment")
        } catch CoachDeployFailure.coordinator {}
        try Data(gateFailure.utf8).write(to: entry)
        do {
            _ = try deployCoach(reader: DoubleReader(), coordinator: LocalNodeCoordinator(
                repository: fixture, node: node, operation: .inspect), operation: .inspect)
            preconditionFailure("inspection must not relay deployment gate diagnostics")
        } catch CoachDeployFailure.coordinator {}
        let inspectSuccess = """
        let packet = ''; for await (const bytes of process.stdin) packet += bytes;
        if (process.argv[2] !== '--inspect' || Object.keys(JSON.parse(packet)).join(',') !== 'wafToken') process.exit(78);
        console.log('inspect: account single approved');
        console.log('inspect: custom invariant rules-array');
        console.log('inspect: rate field requests-to-origin absent-default');
        console.log('inspect: rate first divergence requests-to-origin');
        console.log('inspect: settings field observability null');
        console.log('inspect: settings field workers-dev disabled');
        console.log('inspect: settings invariant conflict');
        console.log('inspected: read-only production state; no mutations or model calls');
        """
        try Data(inspectSuccess.utf8).write(to: entry)
        let inspection = try deployCoach(reader: DoubleReader(), coordinator: LocalNodeCoordinator(
            repository: fixture, node: node, operation: .inspect), operation: .inspect)
        precondition(inspection.contains("inspect: custom invariant rules-array"))
        precondition(inspection.contains("inspect: settings field observability null"))
        precondition(inspection.contains("inspect: settings invariant conflict"))
        try Data("for await (const bytes of process.stdin) {}\nconsole.log('inspect: raw NONSECRET_DIAGNOSTIC');".utf8).write(to: entry)
        do {
            _ = try deployCoach(reader: DoubleReader(), coordinator: LocalNodeCoordinator(
                repository: fixture, node: node, operation: .inspect), operation: .inspect)
            preconditionFailure("raw inspection output must stop")
        } catch CoachDeployFailure.coordinator {}
        try Data("for await (const bytes of process.stdin) {}\nconsole.log('inspect: settings field observability NONSECRET_RAW_VALUE');".utf8).write(to: entry)
        do {
            _ = try deployCoach(reader: DoubleReader(), coordinator: LocalNodeCoordinator(
                repository: fixture, node: node, operation: .inspect), operation: .inspect)
            preconditionFailure("raw settings field output must stop")
        } catch CoachDeployFailure.coordinator {}
        print("passed: native deployment boundary tested with non-secret doubles; no Keychain or network access")
    }
}
