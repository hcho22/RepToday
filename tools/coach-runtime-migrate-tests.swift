import Foundation
import CryptoKit

// Explicit in-memory doubles only. No Security reader, AppKit window or production child entry.
private final class ReaderDouble: RuntimeMigrationReader {
    var reads: [RuntimeMigrationCredential] = []; var failure: RuntimeMigrationCredential?
    var invalid: RuntimeMigrationCredential?
    let privateKey = P256.Signing.PrivateKey().pemRepresentation
    func read(_ item: RuntimeMigrationCredential) throws -> Data {
        reads.append(item)
        if item == failure { throw RuntimeMigrationFailure.retrieval }
        if item == invalid { return Data("invalid fixture".utf8) }
        let value: String
        switch item {
        case .openAI: value = "sk-NONSECRET_TEST_DOUBLE_123456789"
        case .clientGate: value = String(repeating: "0", count: 64)
        case .wafToken: value = "NONSECRET_WAF_TEST_DOUBLE_123456789"
        case .appPrefix: value = "FIXTURE001"
        case .appID: value = "123456"
        case .keyID: value = "FIXTURE002"
        case .issuerID: value = "00000000-0000-0000-0000-000000000000"
        case .privateKey: value = privateKey
        }
        return Data(value.utf8)
    }
}
private final class CoordinatorDouble: RuntimeMigrationCoordinator {
    let operation: RuntimeMigrationOperation; var calls = 0
    init(_ operation: RuntimeMigrationOperation) { self.operation = operation }
    func run(_ credentials: [RuntimeMigrationCredential: Data]) throws -> String {
        precondition(Set(credentials.keys) == Set(operation.items)); calls += 1; return "fixed fixture completion"
    }
}
@main struct CoachRuntimeMigrationTests {
    static func main() throws {
        precondition(CommandLine.arguments.count == 3)
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let node = URL(fileURLWithPath: CommandLine.arguments[2])
        for operation in [RuntimeMigrationOperation.stage, .release, .hold] {
            let reader = ReaderDouble(), mockCoordinator = CoordinatorDouble(operation)
            _ = try runRuntimeMigration(reader: reader, coordinator: mockCoordinator, operation: operation)
            precondition(reader.reads == operation.items && mockCoordinator.calls == 1)
            for item in operation.items {
                for invalid in [false, true] {
                    let reader = ReaderDouble(), coordinator = CoordinatorDouble(operation)
                    if invalid { reader.invalid = item } else { reader.failure = item }
                    do { _ = try runRuntimeMigration(reader: reader, coordinator: coordinator, operation: operation); preconditionFailure("must stop") }
                    catch RuntimeMigrationFailure.format { precondition(invalid) }
                    catch RuntimeMigrationFailure.retrieval { precondition(!invalid) }
                    precondition(coordinator.calls == 0 && reader.reads.last == item)
                }
            }
            let coordinator = RuntimeNodeCoordinator(repository: root, node: node, operation: operation)
            let success = coordinator.expected.joined(separator: "\n") + "\n"
            let accepted = try coordinator.sanitized(Data(success.utf8), status: 0)
            precondition(accepted == success.trimmingCharacters(in: .newlines))
            for transcript in [success + "unexpected\n", String(success.dropLast()), "\n" + success,
                coordinator.expected.reversed().joined(separator: "\n") + "\n", coordinator.expected[0] + "\n"] {
                do { _ = try coordinator.sanitized(Data(transcript.utf8), status: 0); preconditionFailure("must reject transcript") }
                catch RuntimeMigrationFailure.coordinator {}
            }
            for code in RuntimeNodeCoordinator.failures {
                let stopped = try coordinator.sanitized(Data((RuntimeNodeCoordinator.confirmed + "\nblocked: " + code + "\n").utf8), status: 78)
                precondition(stopped.hasPrefix("blocked: dedicated runtime migration stopped"))
            }
            for transcript in ["blocked: arbitrary value\n", "unexpected\nblocked: scope\n", success + "blocked: scope\n"] {
                do { _ = try coordinator.sanitized(Data(transcript.utf8), status: 78); preconditionFailure("must reject unsafe failure") }
                catch RuntimeMigrationFailure.coordinator {}
            }
        }
        // Exercise the real pipe, credential argument/environment exclusion and strict child contract.
        let fixture = root.appendingPathComponent("build/coach-runtime-migration/native-double")
        let tools = fixture.appendingPathComponent("tools"); try FileManager.default.createDirectory(at: tools, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixture) }
        let entry = tools.appendingPathComponent("coach-runtime-migrate.mjs")
        for operation in [RuntimeMigrationOperation.stage, .release, .hold] {
            let coordinator = RuntimeNodeCoordinator(repository: fixture, node: node, operation: operation)
            let transcript = try JSONSerialization.data(withJSONObject: coordinator.expected)
            let script = """
            let input = ''; for await (const chunk of process.stdin) input += chunk;
            const packet = JSON.parse(input);
            if (process.argv.length !== 3 || process.argv[2] !== '\(operation.rawValue)' || Object.keys(packet).sort().join(',') !== '\(operation.items.map{$0.rawValue}.sorted().joined(separator: ","))') process.exit(78);
            if (Object.values(packet).some(value => process.argv.includes(value) || Object.values(process.env).includes(value))) process.exit(78);
            for (const line of \(String(decoding: transcript, as: UTF8.self))) console.log(line);
            """
            try Data(script.utf8).write(to: entry)
            _ = try runRuntimeMigration(reader: ReaderDouble(), coordinator: coordinator, operation: operation)
        }
        // Explicit flag travels only as a fixed nonsecret option; default command stays unchanged.
        for operation in [RuntimeMigrationOperation.stage, .release] {
            let coordinator = RuntimeNodeCoordinator(repository: fixture, node: node, operation: operation, diagnostics: true)
            let transcript = try JSONSerialization.data(withJSONObject: coordinator.expected)
            let script = """
            let input = ''; for await (const chunk of process.stdin) input += chunk;
            const packet = JSON.parse(input);
            if (process.argv.length !== 4 || process.argv[2] !== '\(operation.rawValue)' || process.argv[3] !== '--auth-guard-diagnostics') process.exit(78);
            if (Object.values(packet).some(value => process.argv.includes(value) || Object.values(process.env).includes(value))) process.exit(78);
            for (const line of \(String(decoding: transcript, as: UTF8.self))) console.log(line);
            """
            try Data(script.utf8).write(to: entry)
            _ = try runRuntimeMigration(reader: ReaderDouble(), coordinator: coordinator, operation: operation)
        }
        let invalidDiagnosticHold = RuntimeNodeCoordinator(repository: fixture, node: node, operation: .hold, diagnostics: true)
        do { _ = try invalidDiagnosticHold.run([.wafToken: Data("NONSECRET_WAF_TEST_DOUBLE_123456789".utf8)]); preconditionFailure("hold cannot opt in") }
        catch RuntimeMigrationFailure.coordinator {}
        let coordinator = RuntimeNodeCoordinator(repository: fixture, node: node, operation: .hold)
        try Data("for await(const chunk of process.stdin) {} console.log('NONSECRET_UNEXPECTED_OUTPUT');".utf8).write(to: entry)
        do { _ = try runRuntimeMigration(reader: ReaderDouble(), coordinator: coordinator, operation: .hold); preconditionFailure("must reject echo") }
        catch RuntimeMigrationFailure.coordinator {}
        try Data("for await(const chunk of process.stdin) {} console.log('x'.repeat(20000));".utf8).write(to: entry)
        do { _ = try runRuntimeMigration(reader: ReaderDouble(), coordinator: coordinator, operation: .hold); preconditionFailure("must bound output") }
        catch RuntimeMigrationFailure.coordinator {}
        print("passed: runtime migration native doubles; no Keychain, UI, control plane or live Worker access")
    }
}
