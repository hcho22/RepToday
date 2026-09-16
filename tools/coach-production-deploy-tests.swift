import Foundation

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

@main
struct CoachDeploymentTests {
    static func main() throws {
        let reader = DoubleReader(), coordinator = DoubleCoordinator()
        let result = try deployCoach(reader: reader, coordinator: coordinator)
        precondition(result == "non-secret double completed")
        precondition(reader.reads == CoachCredential.allCases && coordinator.calls == 1)
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
        let inspectSuccess = """
        let packet = ''; for await (const bytes of process.stdin) packet += bytes;
        if (process.argv[2] !== '--inspect' || Object.keys(JSON.parse(packet)).join(',') !== 'wafToken') process.exit(78);
        console.log('inspect: account single approved');
        console.log('inspect: custom invariant rules-array');
        console.log('inspected: read-only production state; no mutations or model calls');
        """
        try Data(inspectSuccess.utf8).write(to: entry)
        let inspection = try deployCoach(reader: DoubleReader(), coordinator: LocalNodeCoordinator(
            repository: fixture, node: node, operation: .inspect), operation: .inspect)
        precondition(inspection.contains("inspect: custom invariant rules-array"))
        try Data("for await (const bytes of process.stdin) {}\nconsole.log('inspect: raw NONSECRET_DIAGNOSTIC');".utf8).write(to: entry)
        do {
            _ = try deployCoach(reader: DoubleReader(), coordinator: LocalNodeCoordinator(
                repository: fixture, node: node, operation: .inspect), operation: .inspect)
            preconditionFailure("raw inspection output must stop")
        } catch CoachDeployFailure.coordinator {}
        print("passed: native deployment boundary tested with non-secret doubles; no Keychain or network access")
    }
}
