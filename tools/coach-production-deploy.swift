import Foundation
import AppKit
import Security
import LocalAuthentication

// This executable has no Keychain write, creation, rotation, or general-purpose read interface.
enum CoachCredential: String, CaseIterable {
    case openAI = "openai-api-key"
    case clientGate = "client-shared-secret"
    case wafToken = "cloudflare-zone-waf-token"

    func accepts(_ bytes: Data) -> Bool {
        let ascii = (20...1024).contains(bytes.count) && bytes.allSatisfy {
            (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 || $0 == 95
        }
        switch self {
        case .openAI: return ascii && bytes.starts(with: Data("sk-".utf8))
        case .wafToken: return ascii
        case .clientGate:
            return bytes.count == 64 && bytes.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
        }
    }
}

enum CoachDeployFailure: Error { case retrieval, format, coordinator }

enum CoachOperation: String {
    case deploy = "--deploy", inspect = "--inspect"
    var items: [CoachCredential] { self == .inspect ? [.wafToken] : CoachCredential.allCases }
}

protocol CoachCredentialReader {
    func read(_ item: CoachCredential) throws -> Data
}

struct NativeCoachCredentialReader: CoachCredentialReader {
    func read(_ item: CoachCredential) throws -> Data {
        let context = LAContext()
        context.interactionNotAllowed = false
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.reptoday.coach.production",
            kSecAttrAccount as String: item.rawValue,
            kSecAttrSynchronizable as String: false,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true,
            kSecUseAuthenticationContext as String: context
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let bytes = result as? Data else { throw CoachDeployFailure.retrieval }
        return bytes
    }
}

// Only presentation changes here: the existing Security query and LAContext policy are untouched.
// Security.framework blocks its caller. Keep AppKit's event loop alive while that call runs.
private final class PresentedReadWork: @unchecked Sendable {
    private let reader: CoachCredentialReader
    private let item: CoachCredential
    private let lock = NSLock()
    private var result: Result<Data, Error>?

    init(reader: CoachCredentialReader, item: CoachCredential) {
        self.reader = reader
        self.item = item
    }

    func execute() {
        let value = Result { try reader.read(item) }
        lock.lock()
        result = value
        lock.unlock()
    }

    func take() throws -> Data {
        lock.lock()
        let value = result
        result = nil
        lock.unlock()
        guard let value else { throw CoachDeployFailure.retrieval }
        return try value.get()
    }
}

struct AppKitCoachCredentialReader: CoachCredentialReader {
    let reader: CoachCredentialReader

    func read(_ item: CoachCredential) throws -> Data {
        guard Thread.isMainThread else { throw CoachDeployFailure.retrieval }
        return try MainActor.assumeIsolated {
            let app = NSApplication.shared
            app.setActivationPolicy(.accessory)
            let panel = NSAlert()
            panel.messageText = "Rep Today Keychain access"
            let label: String
            switch item {
            case .openAI: label = "OpenAI API key"
            case .clientGate: label = "client gate"
            case .wafToken: label = "zone-WAF token"
            }
            panel.informativeText = "Reading the existing \(label) from this Mac's Keychain. Authorize the macOS prompt for this dedicated helper if it appears."
            panel.addButton(withTitle: "Cancel")
            // This is an informational owner window, with no credential or re-entry field.
            panel.window.identifier = NSUserInterfaceItemIdentifier("RepTodayCoachKeychainAccess")
            panel.window.level = .normal
            app.activate(ignoringOtherApps: true)
            let work = PresentedReadWork(reader: reader, item: item)
            // Start after runModal has presented its window and entered the UI event loop.
            DispatchQueue.main.async {
                DispatchQueue.global(qos: .userInitiated).async {
                    work.execute()
                    DispatchQueue.main.async { NSApplication.shared.abortModal() }
                }
            }
            let response = panel.runModal()
            panel.window.orderOut(nil)
            guard response == .abort else { throw CoachDeployFailure.retrieval }
            return try work.take()
        }
    }
}

protocol CoachDeploymentCoordinator {
    func run(_ credentials: [CoachCredential: Data]) throws -> String
}

func deployCoach(reader: CoachCredentialReader, coordinator: CoachDeploymentCoordinator, operation: CoachOperation = .deploy) throws -> String {
    var credentials: [CoachCredential: Data] = [:]
    defer {
        for item in CoachCredential.allCases {
            if var bytes = credentials.removeValue(forKey: item) { bytes.resetBytes(in: 0..<bytes.count) }
        }
    }
    for item in operation.items {
        var bytes = try reader.read(item)
        guard item.accepts(bytes) else {
            bytes.resetBytes(in: 0..<bytes.count)
            throw CoachDeployFailure.format
        }
        credentials[item] = bytes
    }
    return try coordinator.run(credentials)
}

struct LocalNodeCoordinator: CoachDeploymentCoordinator {
    let repository: URL
    let node: URL
    var operation: CoachOperation = .deploy

    func run(_ credentials: [CoachCredential: Data]) throws -> String {
        guard Set(credentials.keys) == Set(operation.items) else { throw CoachDeployFailure.coordinator }
        let process = Process()
        process.executableURL = node
        process.arguments = [repository.appendingPathComponent("tools/coach-production-deploy.mjs").path, operation.rawValue]
        process.currentDirectoryURL = repository
        // No credential is put in argv or the environment. The WAF token stays in this local child.
        var environment = ProcessInfo.processInfo.environment
        environment.removeValue(forKey: "NODE_OPTIONS")
        environment.removeValue(forKey: "NODE_DEBUG")
        environment.removeValue(forKey: "NODE_DEBUG_NATIVE")
        process.environment = environment
        let input = Pipe()
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        let names: [CoachCredential: String] = [.openAI: "openAI", .clientGate: "clientGate", .wafToken: "wafToken"]
        var packet = try JSONSerialization.data(withJSONObject: Dictionary(uniqueKeysWithValues: credentials.map {
            (names[$0.key]!, String(decoding: $0.value, as: UTF8.self))
        }))
        defer { packet.resetBytes(in: 0..<packet.count) }
        try process.run()
        do {
            try input.fileHandleForWriting.write(contentsOf: packet)
            try input.fileHandleForWriting.close()
        } catch {
            process.terminate()
            throw CoachDeployFailure.coordinator
        }
        let reply = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard reply.count <= 8192, let text = String(data: reply, encoding: .utf8) else {
            throw CoachDeployFailure.coordinator
        }
        // Never forward arbitrary child output, API responses, exception descriptions or credentials.
        var permitted = Set([
            "confirmed: approved account, zone and Worker target",
            "protected: hostname held closed; path and rate rules verified",
            "staged: Worker has no persistence, logs or development URLs",
            "deployed: reptoday-variety-language-proxy https://coach.reptoday.app/coach; live model QA pending"
        ])
        if operation == .inspect {
            permitted = Set([
                "inspect: account single approved", "inspect: zone active approved Free",
                "inspected: read-only production state; no mutations or model calls"
            ])
            for phase in ["custom", "rate"] {
                for state in ["absent", "matches", "mismatch"] { permitted.insert("inspect: \(phase) phase \(state)") }
                for state in ["ok", "ruleset-shape", "ruleset-identity", "kind", "phase", "rules-array", "rule-identity", "skip", "logging", "duplicate-ref", "owned-semantics", "rate-capacity"] {
                    permitted.insert("inspect: \(phase) invariant \(state)")
                }
                for state in ["absent", "omitted-or-invalid", "populated", "empty"] { permitted.insert("inspect: \(phase) rules-list \(state)") }
                for state in ["none", "unknown", "present"] { permitted.insert("inspect: unrelated \(phase) rules \(state)") }
                for state in ["available", "unknown", "conflict"] { permitted.insert("inspect: \(phase) capacity \(state)") }
            }
            for owned in ["hold", "boundary", "rate"] {
                for state in ["absent", "unknown", "enabled", "disabled", "conflict"] { permitted.insert("inspect: owned \(owned) \(state)") }
            }
            for field in ["worker", "provider binding", "client-gate binding", "unexpected secret bindings"] {
                for state in ["absent", "present"] { permitted.insert("inspect: \(field) \(state)") }
            }
            for state in ["absent", "approved", "conflict"] { permitted.insert("inspect: domain \(state)") }
            for state in ["clear", "conflict"] { permitted.insert("inspect: legacy route \(state)") }
            let rateFields = ["ref", "action", "expression", "enabled", "logging", "action-parameters",
                "characteristics", "period", "requests", "mitigation", "requests-to-origin",
                "counting-expression", "score-per-period", "score-response-header", "extra-rule-fields", "extra-rate-fields"]
            for field in rateFields {
                for state in ["missing", "matches", "mismatch", "absent", "disabled", "enabled", "invalid",
                    "empty-default", "present", "missing-or-invalid", "absent-default", "zero-default", "unexpected", "none"] {
                    permitted.insert("inspect: rate field \(field) \(state)")
                }
                permitted.insert("inspect: rate first divergence \(field)")
            }
            permitted.insert("inspect: rate first divergence none")
        }
        let lines = text.split(separator: "\n").map(String.init)
        let failures = Set([
            "input", "auth", "account", "zone", "target", "scope", "rules", "route", "settings",
            "secret", "wrangler", "http", "gate", "rate-plan", "unexpected"
        ])
        guard !lines.isEmpty, lines.allSatisfy({ permitted.contains($0) ||
            ($0.hasPrefix("blocked: ") && failures.contains(String($0.dropFirst(9)))) }) else {
            throw CoachDeployFailure.coordinator
        }
        if process.terminationStatus != 0 {
            let code = lines.last.flatMap { $0.hasPrefix("blocked: ") ? String($0.dropFirst(9)) : nil } ?? "unexpected"
            return "blocked: dedicated deployment helper stopped (\(code)); inspect configuration without printing credentials"
        }
        if operation == .inspect {
            guard lines.first == "inspect: account single approved",
                  lines.last == "inspected: read-only production state; no mutations or model calls",
                  !lines.contains(where: { $0.hasPrefix("blocked:") }) else { throw CoachDeployFailure.coordinator }
            return lines.joined(separator: "\n")
        }
        guard lines == [
            "confirmed: approved account, zone and Worker target",
            "protected: hostname held closed; path and rate rules verified",
            "staged: Worker has no persistence, logs or development URLs",
            "deployed: reptoday-variety-language-proxy https://coach.reptoday.app/coach; live model QA pending"
        ] else {
            throw CoachDeployFailure.coordinator
        }
        return lines.joined(separator: "\n")
    }
}

#if !COACH_DEPLOY_TESTS
@main
struct CoachProductionDeploy {
    static func main() {
        let args = Array(CommandLine.arguments.dropFirst())
        guard args.count == 3, let operation = CoachOperation(rawValue: args[0]) else {
            print("usage: launch tools/deploy-coach-production.sh locally; never pass a credential")
            exit(64)
        }
        do {
            let result = try deployCoach(reader: AppKitCoachCredentialReader(reader: NativeCoachCredentialReader()), coordinator: LocalNodeCoordinator(
                repository: URL(fileURLWithPath: args[1], isDirectory: true), node: URL(fileURLWithPath: args[2]), operation: operation
            ), operation: operation)
            print(result)
            exit(result.hasPrefix("blocked:") ? 78 : 0)
        } catch CoachDeployFailure.retrieval {
            print("blocked: native Keychain retrieval denied or unavailable; no values printed and no production mutation")
            exit(78)
        } catch CoachDeployFailure.format {
            print("blocked: existing Keychain credential format mismatch; no values printed and no production mutation")
            exit(78)
        } catch {
            print("blocked: dedicated deployment coordinator unavailable; no diagnostic values forwarded")
            exit(78)
        }
    }
}
#endif
