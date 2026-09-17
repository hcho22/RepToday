import Foundation
import AppKit
import Security
import LocalAuthentication

enum RuntimeMigrationOperation: String { case stage = "--stage", release = "--release", hold = "--hold"
    var items: [RuntimeMigrationCredential] {
        switch self {
        case .stage: return RuntimeMigrationCredential.allCases
        case .release: return [.clientGate, .wafToken]
        case .hold: return [.wafToken]
        }
    }
}
enum RuntimeMigrationCredential: String, CaseIterable {
    case openAI, clientGate, wafToken, appPrefix, appID, keyID, issuerID, privateKey
    var legacy: CoachCredential? {
        switch self { case .openAI: return .openAI; case .clientGate: return .clientGate
        case .wafToken: return .wafToken; default: return nil }
    }
    var apple: CoachRuntimeCredential? {
        switch self { case .appPrefix: return .appPrefix; case .appID: return .appID; case .keyID: return .keyID
        case .issuerID: return .issuerID; case .privateKey: return .privateKey; default: return nil }
    }
    func valid(_ bytes: Data) -> Bool { legacy?.accepts(bytes) ?? apple?.valid(bytes) ?? false }
}
enum RuntimeMigrationFailure: Error { case retrieval, format, coordinator }
protocol RuntimeMigrationReader { func read(_ item: RuntimeMigrationCredential) throws -> Data }
protocol RuntimeMigrationCoordinator { func run(_ credentials: [RuntimeMigrationCredential: Data]) throws -> String }

// Read only explicitly enumerated existing items. No write/search/rotation or output of values.
struct NativeRuntimeMigrationReader: RuntimeMigrationReader {
    func read(_ item: RuntimeMigrationCredential) throws -> Data {
        if let legacy = item.legacy { return try NativeCoachCredentialReader().read(legacy) }
        guard let apple = item.apple else { throw RuntimeMigrationFailure.retrieval }
        let context = LAContext(); context.interactionNotAllowed = false
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.reptoday.coach.production", kSecAttrAccount as String: apple.rawValue,
            kSecAttrSynchronizable as String: false, kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true, kSecUseAuthenticationContext as String: context]
        var value: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &value) == errSecSuccess,
              let bytes = value as? Data else { throw RuntimeMigrationFailure.retrieval }
        return bytes
    }
}
private final class RuntimePresentedRead: @unchecked Sendable {
    let reader: any RuntimeMigrationReader, item: RuntimeMigrationCredential
    private let lock = NSLock(); private var value: Result<Data, Error>?
    init(reader: any RuntimeMigrationReader, item: RuntimeMigrationCredential) { self.reader = reader; self.item = item }
    func execute() { let result = Result { try reader.read(item) }; lock.lock(); value = result; lock.unlock() }
    func take() throws -> Data { lock.lock(); let result = value; value = nil; lock.unlock()
        guard let result else { throw RuntimeMigrationFailure.retrieval }; return try result.get() }
}
struct PresentedRuntimeMigrationReader: RuntimeMigrationReader {
    let reader: any RuntimeMigrationReader
    func read(_ item: RuntimeMigrationCredential) throws -> Data {
        guard Thread.isMainThread else { throw RuntimeMigrationFailure.retrieval }
        return try MainActor.assumeIsolated {
            let app = NSApplication.shared; app.setActivationPolicy(.accessory)
            let panel = NSAlert(); panel.messageText = "Rep Today migration Keychain access"
            panel.informativeText = "Reading an approved existing server configuration item. Authorize the macOS prompt for this dedicated helper if it appears. No value is displayed or re-entered."
            panel.addButton(withTitle: "Cancel"); app.activate(ignoringOtherApps: true)
            let work = RuntimePresentedRead(reader: reader, item: item)
            DispatchQueue.main.async { DispatchQueue.global(qos: .userInitiated).async {
                work.execute(); DispatchQueue.main.async { NSApplication.shared.abortModal() }
            } }
            let response = panel.runModal(); panel.window.orderOut(nil)
            guard response == .abort else { throw RuntimeMigrationFailure.retrieval }; return try work.take()
        }
    }
}
func runRuntimeMigration(reader: any RuntimeMigrationReader, coordinator: any RuntimeMigrationCoordinator,
                         operation: RuntimeMigrationOperation) throws -> String {
    var credentials: [RuntimeMigrationCredential: Data] = [:]
    defer { for item in RuntimeMigrationCredential.allCases {
        if var bytes = credentials.removeValue(forKey: item) { bytes.resetBytes(in: 0..<bytes.count) }
    } }
    for item in operation.items {
        var bytes = try reader.read(item)
        guard item.valid(bytes) else { bytes.resetBytes(in: 0..<bytes.count); throw RuntimeMigrationFailure.format }
        credentials[item] = bytes
    }
    return try coordinator.run(credentials)
}
struct RuntimeNodeCoordinator: RuntimeMigrationCoordinator {
    let repository: URL, node: URL
    let operation: RuntimeMigrationOperation
    static let confirmed = "confirmed: approved existing account, zone, Worker and attached origin"
    static let protected = "protected: hostname held closed; existing boundary and rate protections verified"
    static let staged = "staged: reviewed runtime source, SQLite namespace and server bindings verified; hostname held closed"
    static let released = "released: reptoday-variety-language-proxy https://coach.reptoday.app/coach; genuine Apple and live model QA pending"
    static let held = "held: hostname closed; Worker, server bindings and security records preserved"
    static let failures = Set(["input", "auth", "account", "zone", "target", "scope", "rules", "route", "settings",
        "secret", "wrangler", "http", "gate", "rate-plan", "namespace", "revision", "rehold", "unexpected"])
    var expected: [String] {
        if operation == .hold { return [Self.confirmed, Self.held] }
        return [Self.confirmed, Self.protected, operation == .stage ? Self.staged : Self.released]
    }
    // Exact complete transcript, including newline/order: partial, duplicate and arbitrary output fail.
    func sanitized(_ reply: Data, status: Int32) throws -> String {
        guard reply.count <= 8192, let text = String(data: reply, encoding: .utf8), text.hasSuffix("\n") else {
            throw RuntimeMigrationFailure.coordinator
        }
        let lines = String(text.dropLast()).components(separatedBy: "\n")
        if status == 0 { guard lines == expected else { throw RuntimeMigrationFailure.coordinator }; return lines.joined(separator: "\n") }
        guard let last = lines.last, last.hasPrefix("blocked: "), Self.failures.contains(String(last.dropFirst(9))),
              Array(lines.dropLast()) == Array(expected.prefix(lines.count - 1)), lines.count <= expected.count else {
            throw RuntimeMigrationFailure.coordinator
        }
        return "blocked: dedicated runtime migration stopped (\(last.dropFirst(9))); preserve the hold and inspect prerequisites without values"
    }
    func run(_ credentials: [RuntimeMigrationCredential: Data]) throws -> String {
        guard Set(credentials.keys) == Set(operation.items) else { throw RuntimeMigrationFailure.coordinator }
        let process = Process(); process.executableURL = node
        process.arguments = [repository.appendingPathComponent("tools/coach-runtime-migrate.mjs").path, operation.rawValue]
        process.currentDirectoryURL = repository
        var environment = ProcessInfo.processInfo.environment
        for name in ["NODE_OPTIONS", "NODE_DEBUG", "NODE_DEBUG_NATIVE", "OPENAI_API_KEY", "CLIENT_SHARED_SECRET",
                     "ANTHROPIC_API_KEY", "APP_STORE_PRIVATE_KEY"] { environment.removeValue(forKey: name) }
        process.environment = environment
        let input = Pipe(), output = Pipe(); process.standardInput = input; process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        var packet = try JSONSerialization.data(withJSONObject: Dictionary(uniqueKeysWithValues: credentials.map {
            ($0.key.rawValue, String(decoding: $0.value, as: UTF8.self))
        }))
        defer { packet.resetBytes(in: 0..<packet.count) }
        guard packet.count <= 12_288 else { throw RuntimeMigrationFailure.coordinator }
        try process.run()
        let timer = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 700, execute: timer)
        defer { timer.cancel() }
        do { try input.fileHandleForWriting.write(contentsOf: packet); try input.fileHandleForWriting.close() }
        catch { if process.isRunning { process.terminate() }; throw RuntimeMigrationFailure.coordinator }
        var reply = Data()
        do { while let part = try output.fileHandleForReading.read(upToCount: 4096), !part.isEmpty {
            guard reply.count + part.count <= 8192 else {
                if process.isRunning { process.terminate() }; throw RuntimeMigrationFailure.coordinator
            }; reply.append(part)
        } } catch { if process.isRunning { process.terminate() }; throw RuntimeMigrationFailure.coordinator }
        process.waitUntilExit(); return try sanitized(reply, status: process.terminationStatus)
    }
}
#if !COACH_RUNTIME_MIGRATION_TESTS
@main struct CoachRuntimeMigrationMain {
    @MainActor static func main() {
        let args = Array(CommandLine.arguments.dropFirst())
        guard args.count == 3, let operation = RuntimeMigrationOperation(rawValue: args[0]) else {
            print("usage: launch tools/migrate-coach-runtime.sh with --stage, --release or --hold; never pass credentials"); exit(64)
        }
        do {
            let result = try runRuntimeMigration(reader: PresentedRuntimeMigrationReader(reader: NativeRuntimeMigrationReader()),
                coordinator: RuntimeNodeCoordinator(repository: URL(fileURLWithPath: args[1], isDirectory: true),
                    node: URL(fileURLWithPath: args[2]), operation: operation), operation: operation)
            print(result); if result.hasPrefix("blocked:") { exit(78) }
        } catch {
            print("blocked: dedicated runtime migration stopped before a verified result; preserve the hold; no credential output"); exit(78)
        }
    }
}
#endif
