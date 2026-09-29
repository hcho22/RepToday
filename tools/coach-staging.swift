#if COACH_STAGING_TOOL
import Foundation

/// Staging deploy entry, compiled only by tools/coach-staging.sh. It reads just the five App Store
/// items through the reviewed native Keychain reader and passes them on stdin to
/// tools/coach-staging.mjs --deploy. No production item (provider, gate, WAF) is read.
let stagingItems: [RuntimeMigrationCredential] = [.appPrefix, .appID, .keyID, .issuerID, .privateKey]

struct StagingNodeCoordinator {
    let repository: URL, node: URL
    static let confirmed = "confirmed: single account and workers.dev subdomain"
    static let verified = "verified: staging bindings, own SQLite namespace, no custom domain, labelled no-model probes"
    static let failures: Set<String> = ["input", "auth", "account", "subdomain", "scope", "http", "wrangler", "revision",
        "secret", "settings", "namespace", "domain", "probe", "teardown", "unexpected"]
    static func isDeployedLine(_ line: String) -> Bool {
        let pattern = "^deployed: reptoday-coach-staging https://reptoday-coach-staging\\.[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\\.workers\\.dev/coach; staging only, no model key$"
        return line.range(of: pattern, options: .regularExpression) != nil
    }
    // Exact closed transcript: confirmed, one deployed line naming the workers.dev URL, verified.
    func sanitized(_ reply: Data, status: Int32) throws -> String {
        guard reply.count <= 8192, let text = String(data: reply, encoding: .utf8), text.hasSuffix("\n") else {
            throw RuntimeMigrationFailure.coordinator
        }
        let lines = String(text.dropLast()).components(separatedBy: "\n")
        let shape: [(String) -> Bool] = [{ $0 == Self.confirmed }, Self.isDeployedLine, { $0 == Self.verified }]
        if status == 0 {
            guard lines.count == shape.count, zip(lines, shape).allSatisfy({ $1($0) }) else { throw RuntimeMigrationFailure.coordinator }
            return lines.joined(separator: "\n")
        }
        guard let last = lines.last, last.hasPrefix("blocked: "), Self.failures.contains(String(last.dropFirst(9))),
              lines.count <= shape.count, zip(lines.dropLast(), shape).allSatisfy({ $1($0) }) else {
            throw RuntimeMigrationFailure.coordinator
        }
        let deployed = lines.dropLast().first(where: Self.isDeployedLine)
        let stopped = "blocked: staging deploy stopped (\(last.dropFirst(9))); run tools/coach-staging.sh --teardown if a staging Worker was created"
        return deployed.map { stopped + "\n" + $0 } ?? stopped
    }
    func run(_ credentials: [RuntimeMigrationCredential: Data]) throws -> String {
        guard Set(credentials.keys) == Set(stagingItems) else { throw RuntimeMigrationFailure.coordinator }
        let (reply, status) = try runBoundedNodeCoordinator(repository: repository, node: node,
            arguments: [repository.appendingPathComponent("tools/coach-staging.mjs").path, "--deploy"], credentials: credentials)
        return try sanitized(reply, status: status)
    }
}

func runStagingDeploy(reader: any RuntimeMigrationReader, coordinator: (([RuntimeMigrationCredential: Data]) throws -> String)) throws -> String {
    var credentials: [RuntimeMigrationCredential: Data] = [:]
    defer { for item in stagingItems {
        if var bytes = credentials.removeValue(forKey: item) { bytes.resetBytes(in: 0..<bytes.count) }
    } }
    for item in stagingItems {
        var bytes = try reader.read(item)
        guard item.valid(bytes) else { bytes.resetBytes(in: 0..<bytes.count); throw RuntimeMigrationFailure.format }
        credentials[item] = bytes
    }
    return try coordinator(credentials)
}

#if !COACH_STAGING_TESTS
@main struct CoachStagingMain {
    @MainActor static func main() {
        let args = Array(CommandLine.arguments.dropFirst())
        guard args.count == 3, args[0] == "--deploy" else {
            print("usage: tools/coach-staging.sh --deploy|--teardown|--inspect (never pass credentials)"); exit(64)
        }
        let coordinator = StagingNodeCoordinator(repository: URL(fileURLWithPath: args[1], isDirectory: true), node: URL(fileURLWithPath: args[2]))
        do {
            let result = try runStagingDeploy(reader: PresentedRuntimeMigrationReader(reader: NativeRuntimeMigrationReader()),
                                              coordinator: coordinator.run)
            print(result); exit(result.hasPrefix("blocked:") ? 78 : 0)
        } catch {
            print("blocked: staging deploy stopped before a verified result; no credential output"); exit(78)
        }
    }
}
#endif
#endif
