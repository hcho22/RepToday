import AppKit
import Security

// Local captain-operated intake only. Never add a command that emits credential values.
private let keychainService = "com.reptoday.coach.production"
private let openAIAccount = "openai-api-key"
private let clientGateAccount = "client-shared-secret"

private func report(_ message: String, code: Int32 = 0) -> Never {
    print(message)
    exit(code)
}

private func query(_ account: String) -> [String: Any] {
    [kSecClass as String: kSecClassGenericPassword,
     kSecAttrService as String: keychainService,
     kSecAttrAccount as String: account,
     kSecAttrSynchronizable as String: false]
}

// Metadata only: --check never retrieves or prints the saved passwords.
private func itemStatus(_ account: String) -> OSStatus {
    var attributes = query(account)
    attributes[kSecReturnAttributes as String] = true
    attributes[kSecMatchLimit as String] = kSecMatchLimitOne
    return SecItemCopyMatching(attributes as CFDictionary, nil)
}

private func add(_ bytes: Data, account: String) -> OSStatus {
    var attributes = query(account)
    attributes[kSecValueData as String] = bytes
    attributes[kSecAttrLabel as String] = "Rep Today production Coach: \(account)"
    return SecItemAdd(attributes as CFDictionary, nil)
}

private func ensureClientGate() {
    switch itemStatus(clientGateAccount) {
    case errSecSuccess:
        return // Preserve an existing gate; never silently rotate a deployed client's credential.
    case errSecItemNotFound:
        break
    default:
        report("error: client-gate Keychain item is unavailable; credentials were not printed", code: 78)
    }
    var bytes = [UInt8](repeating: 0, count: 32)
    guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
        report("error: secure client-gate generation failed", code: 1)
    }
    defer { _ = bytes.withUnsafeMutableBytes { $0.initializeMemory(as: UInt8.self, repeating: 0) } }
    var gate = Data(bytes.map { String(format: "%02x", $0) }.joined().utf8)
    defer { gate.resetBytes(in: 0..<gate.count) }
    guard add(gate, account: clientGateAccount) == errSecSuccess else {
        report("error: client-gate save failed; any saved API key remains in Keychain", code: 78)
    }
}

let arguments = Array(CommandLine.arguments.dropFirst())
if arguments == ["--check"] {
    let ready = itemStatus(openAIAccount) == errSecSuccess && itemStatus(clientGateAccount) == errSecSuccess
    report(ready ? "ready: both production Coach Keychain items exist" : "not-ready: production Coach Keychain items are missing or unavailable", code: ready ? 0 : 78)
}
guard arguments.isEmpty else {
    report("usage: tools/prepare-coach-keychain.sh [--check] (never pass a credential as an argument)", code: 64)
}

switch itemStatus(openAIAccount) {
case errSecSuccess:
    ensureClientGate()
    report("ready: existing production Coach API key preserved; client gate available")
case errSecItemNotFound:
    break
default:
    report("error: API-key Keychain item is unavailable; unlock the local Keychain and retry", code: 78)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let dialog = NSAlert()
dialog.messageText = "Rep Today production Coach key"
dialog.informativeText = "Enter the captain-owned OpenAI API key here. It will be saved directly to this Mac's default Keychain. A new client gate will also be saved there if absent. This helper does not deploy or call a model."
dialog.addButton(withTitle: "Save to Keychain")
dialog.addButton(withTitle: "Cancel")
let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 420, height: 26))
field.placeholderString = "OpenAI API key"
field.setAccessibilityLabel("OpenAI API key, secure input")
dialog.accessoryView = field
dialog.window.initialFirstResponder = field
app.activate(ignoringOtherApps: true)
guard dialog.runModal() == .alertFirstButtonReturn else {
    field.stringValue = ""
    report("cancelled: no credentials saved", code: 130)
}

var key = Data(field.stringValue.utf8)
field.stringValue = ""
defer { key.resetBytes(in: 0..<key.count) }
guard key.starts(with: Data("sk-".utf8)), (20...1024).contains(key.count),
      key.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 || $0 == 95 }) else {
    report("error: API key has an unexpected format; nothing saved", code: 64)
}
guard add(key, account: openAIAccount) == errSecSuccess else {
    report("error: API-key save failed; no credential value was printed", code: 78)
}
ensureClientGate()
report("ready: production Coach API key and client gate saved in macOS Keychain")
