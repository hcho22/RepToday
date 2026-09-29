#if COACH_STAGING_TESTS
import Foundation
import CryptoKit

// Native staging checks with nonsecret doubles: no Keychain, UI, network or Cloudflare access.
final class StagingReaderDouble: RuntimeMigrationReader {
    var reads: [RuntimeMigrationCredential] = []
    var invalid: RuntimeMigrationCredential?
    let privateKey = P256.Signing.PrivateKey().pemRepresentation
    func read(_ item: RuntimeMigrationCredential) throws -> Data {
        reads.append(item)
        if item == invalid { return Data("invalid".utf8) }
        switch item {
        case .appPrefix: return Data("FIXTURE001".utf8)
        case .appID: return Data("123456".utf8)
        case .keyID: return Data("FIXTURE002".utf8)
        case .issuerID: return Data("00000000-0000-0000-0000-000000000000".utf8)
        case .privateKey: return Data(privateKey.utf8)
        default: preconditionFailure("staging must never read \(item)")
        }
    }
    func cancelPendingRead() {}
}

@main struct CoachStagingTests {
    static func main() throws {
        let args = CommandLine.arguments
        precondition(args.count == 3, "usage: native-tests <repo> <node>")
        let root = URL(fileURLWithPath: args[1], isDirectory: true), node = URL(fileURLWithPath: args[2])
        // Only the five App Store items, in order; an invalid one stops before the coordinator.
        let reader = StagingReaderDouble(); var calls = 0
        _ = try runStagingDeploy(reader: reader) { credentials in calls += 1
            precondition(Set(credentials.keys) == Set(stagingItems)); return "ok" }
        precondition(reader.reads == stagingItems && calls == 1)
        for item in stagingItems {
            let bad = StagingReaderDouble(); bad.invalid = item; var reached = false
            do { _ = try runStagingDeploy(reader: bad) { _ in reached = true; return "" }; preconditionFailure("must stop") }
            catch RuntimeMigrationFailure.format { precondition(!reached && bad.reads.last == item) }
        }
        // Closed transcript.
        let coordinator = StagingNodeCoordinator(repository: root, node: node)
        let deployed = "deployed: reptoday-coach-staging https://reptoday-coach-staging.fixture-account.workers.dev/coach; staging only, no model key"
        let success = [StagingNodeCoordinator.confirmed, deployed, StagingNodeCoordinator.verified].joined(separator: "\n") + "\n"
        let accepted = try coordinator.sanitized(Data(success.utf8), status: 0)
        precondition(accepted == String(success.dropLast()))
        for transcript in [success + "extra\n", StagingNodeCoordinator.confirmed + "\n" + StagingNodeCoordinator.verified + "\n",
            success.replacingOccurrences(of: "fixture-account.workers.dev", with: "evil.example"),
            success.replacingOccurrences(of: "reptoday-coach-staging https", with: "reptoday-variety-language-proxy https"),
            String(success.dropLast())] {
            do { _ = try coordinator.sanitized(Data(transcript.utf8), status: 0); preconditionFailure("must reject transcript") }
            catch RuntimeMigrationFailure.coordinator {}
        }
        for code in StagingNodeCoordinator.failures {
            let early = try coordinator.sanitized(Data((StagingNodeCoordinator.confirmed + "\nblocked: " + code + "\n").utf8), status: 78)
            precondition(early == "blocked: staging deploy stopped (\(code)); run tools/coach-staging.sh --teardown if a staging Worker was created")
            let late = try coordinator.sanitized(Data((StagingNodeCoordinator.confirmed + "\n" + deployed + "\nblocked: " + code + "\n").utf8), status: 78)
            precondition(late.hasPrefix("blocked: staging deploy stopped (\(code));") && late.hasSuffix("\n" + deployed))
        }
        for transcript in ["blocked: arbitrary\n", "unexpected\nblocked: probe\n", success + "blocked: probe\n"] {
            do { _ = try coordinator.sanitized(Data(transcript.utf8), status: 78); preconditionFailure("must reject failure") }
            catch RuntimeMigrationFailure.coordinator {}
        }
        // Real pipe: credentials arrive only on stdin; argv carries just the script and --deploy.
        let fixture = root.appendingPathComponent("build/coach-staging/native-double")
        let tools = fixture.appendingPathComponent("tools")
        try FileManager.default.createDirectory(at: tools, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixture) }
        let script = """
        let input = ''; process.stdin.on('data', chunk => input += chunk);
        process.stdin.on('end', () => {
          const packet = JSON.parse(input);
          const ok = process.argv.slice(2).join(' ') === '--deploy' && Object.keys(packet).sort().join(',') === 'appID,appPrefix,issuerID,keyID,privateKey' &&
            !JSON.stringify(process.argv).includes('FIXTURE001') && !Object.values(process.env).some(value => String(value).includes('FIXTURE001'));
          process.stdout.write(ok ? \(String(reflecting: success)) : 'blocked: input\\n'); process.exitCode = ok ? 0 : 78;
        });
        """
        try script.write(to: tools.appendingPathComponent("coach-staging.mjs"), atomically: true, encoding: .utf8)
        let piped = try runStagingDeploy(reader: StagingReaderDouble(), coordinator: StagingNodeCoordinator(repository: fixture, node: node).run)
        precondition(piped == String(success.dropLast()), "pipe transcript")
        print("passed: staging native reader scope, closed transcript and credential-only-on-stdin pipe; no Keychain or network")
    }
}
#endif
