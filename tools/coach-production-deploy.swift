import Foundation
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

protocol CoachDeploymentCoordinator {
    func run(_ credentials: [CoachCredential: Data]) throws -> String
}

func deployCoach(reader: CoachCredentialReader, coordinator: CoachDeploymentCoordinator) throws -> String {
    var credentials: [CoachCredential: Data] = [:]
    defer {
        for item in CoachCredential.allCases {
            if var bytes = credentials.removeValue(forKey: item) { bytes.resetBytes(in: 0..<bytes.count) }
        }
    }
    for item in CoachCredential.allCases {
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

    func run(_ credentials: [CoachCredential: Data]) throws -> String {
        let process = Process()
        process.executableURL = node
        process.arguments = [repository.appendingPathComponent("tools/coach-production-deploy.mjs").path, "--deploy"]
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
        var packet = try JSONSerialization.data(withJSONObject: Dictionary(uniqueKeysWithValues: names.map {
            ($0.value, String(decoding: credentials[$0.key]!, as: UTF8.self))
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
        guard reply.count <= 2048, let text = String(data: reply, encoding: .utf8) else {
            throw CoachDeployFailure.coordinator
        }
        // Never forward arbitrary child output, API responses, exception descriptions or credentials.
        let permitted = Set([
            "confirmed: approved account, zone and Worker target",
            "protected: hostname held closed; path and rate rules verified",
            "staged: Worker has no persistence, logs or development URLs",
            "deployed: reptoday-variety-language-proxy https://coach.reptoday.app/coach; live model QA pending"
        ])
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
        guard args.count == 3, args[0] == "--deploy" else {
            print("usage: launch tools/deploy-coach-production.sh locally; never pass a credential")
            exit(64)
        }
        do {
            let result = try deployCoach(reader: NativeCoachCredentialReader(), coordinator: LocalNodeCoordinator(
                repository: URL(fileURLWithPath: args[1], isDirectory: true), node: URL(fileURLWithPath: args[2])
            ))
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
