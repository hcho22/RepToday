import AppKit
import Security
import CryptoKit
import UniformTypeIdentifiers

// Captain-operated only. No credential arguments, environment import, searching or value output.
enum CoachRuntimeCredential: String, CaseIterable {
    case appPrefix = "app-attest-app-prefix"
    case appID = "app-store-app-id"
    case keyID = "app-store-key-id"
    case issuerID = "app-store-issuer-id"
    case privateKey = "app-store-private-key"
    var title: String {
        switch self {
        case .appPrefix: return "Registered App ID prefix"
        case .appID: return "Production App Store numeric app ID"
        case .keyID: return "App Store Connect In-App Purchase key ID"
        case .issuerID: return "App Store Connect issuer ID"
        case .privateKey: return "Existing App Store Connect private .p8 key"
        }
    }
    func valid(_ bytes: Data) -> Bool {
        guard bytes.count <= 4096, let value = String(data:bytes,encoding:.utf8) else { return false }
        switch self {
        case .appPrefix, .keyID: return value.range(of:"^[A-Z0-9]{10}$",options:.regularExpression) != nil
        case .appID:
            return value.range(of:"^[1-9][0-9]{0,15}$",options:.regularExpression) != nil && (UInt64(value).map{$0 <= 9_007_199_254_740_991} ?? false)
        case .issuerID: return UUID(uuidString:value) != nil && value.count == 36
        case .privateKey:
            return value.hasPrefix("-----BEGIN PRIVATE KEY-----\n") && (try? P256.Signing.PrivateKey(pemRepresentation:value)) != nil
        }
    }
}
protocol CoachRuntimeIntakeStore {
    func status(_ credential: CoachRuntimeCredential) -> OSStatus
    func add(_ bytes: Data, credential: CoachRuntimeCredential) -> OSStatus
}
struct SecurityCoachRuntimeIntakeStore: CoachRuntimeIntakeStore {
    private func query(_ credential: CoachRuntimeCredential) -> [String:Any] {
        [kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:"com.reptoday.coach.production",
         kSecAttrAccount as String:credential.rawValue,kSecAttrSynchronizable as String:false]
    }
    func status(_ credential:CoachRuntimeCredential)->OSStatus {
        var query=query(credential);query[kSecReturnAttributes as String]=true;query[kSecMatchLimit as String]=kSecMatchLimitOne
        return SecItemCopyMatching(query as CFDictionary,nil) // Metadata only; never request value data.
    }
    func add(_ bytes:Data,credential:CoachRuntimeCredential)->OSStatus {
        var query=query(credential);query[kSecValueData as String]=bytes
        query[kSecAttrAccessible as String]=kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        return SecItemAdd(query as CFDictionary,nil) // No update/rotation of existing items.
    }
}
enum CoachRuntimeIntakeFailure: Error { case unavailable, cancelled, invalid, save }
func intakeCoachRuntimeKeys(store:any CoachRuntimeIntakeStore, receive:(CoachRuntimeCredential)throws->Data?) throws {
    for credential in CoachRuntimeCredential.allCases {
        switch store.status(credential) {
        case errSecSuccess: continue
        case errSecItemNotFound: break
        default: throw CoachRuntimeIntakeFailure.unavailable
        }
        guard var bytes=try receive(credential) else { throw CoachRuntimeIntakeFailure.cancelled }
        defer {bytes.resetBytes(in:0..<bytes.count)}
        guard credential.valid(bytes) else { throw CoachRuntimeIntakeFailure.invalid }
        guard store.add(bytes,credential:credential) == errSecSuccess else { throw CoachRuntimeIntakeFailure.save }
    }
}

#if !COACH_RUNTIME_INTAKE_TESTS
@main struct CoachRuntimeKeyIntakeMain {
    @MainActor static func main() {
        let arguments=Array(CommandLine.arguments.dropFirst())
        let store=SecurityCoachRuntimeIntakeStore()
        if arguments == ["--check"] {
            let ready=CoachRuntimeCredential.allCases.allSatisfy{store.status($0) == errSecSuccess}
            print(ready ? "ready: Apple runtime-authentication Keychain items exist; platform authority unverified" : "not-ready: Apple runtime-authentication Keychain items missing or unavailable")
            exit(ready ? 0 : 78)
        }
        guard arguments.isEmpty else { print("usage: tools/prepare-coach-runtime-keychain.sh [--check]; never pass credentials");exit(64) }
        NSApplication.shared.setActivationPolicy(.accessory)
        do {
            try intakeCoachRuntimeKeys(store:store) { credential in
                NSApplication.shared.activate(ignoringOtherApps:true)
                if credential == .privateKey {
                    let panel=NSOpenPanel();panel.title=credential.title
                    panel.message="Select only the captain-approved existing In-App Purchase private key. It goes directly to this Mac's Keychain; no copy or value output is made."
                    panel.allowedContentTypes=[UTType(filenameExtension:"p8") ?? .plainText]
                    panel.allowsMultipleSelection=false;panel.canChooseDirectories=false
                    guard panel.runModal() == .OK,let url=panel.url else {return nil}
                    let values=try url.resourceValues(forKeys:[.isRegularFileKey,.fileSizeKey])
                    guard values.isRegularFile == true,let size=values.fileSize,size > 0,size <= 4096 else {throw CoachRuntimeIntakeFailure.invalid}
                    let file=try FileHandle(forReadingFrom:url);defer{try? file.close()}
                    guard let data=try file.read(upToCount:4097),data.count <= 4096 else {throw CoachRuntimeIntakeFailure.invalid}
                    return data
                }
                let alert=NSAlert();alert.messageText=credential.title
                alert.informativeText="Enter the existing captain-verified production value. Saved directly to Keychain and never printed. Verify the registered App ID prefix; do not assume it equals the team ID."
                alert.addButton(withTitle:"Save to Keychain");alert.addButton(withTitle:"Cancel")
                let field=NSSecureTextField(frame:NSRect(x:0,y:0,width:440,height:28))
                field.setAccessibilityLabel("Production configuration, secure input")
                alert.accessoryView=field;alert.window.initialFirstResponder=field
                guard alert.runModal() == .alertFirstButtonReturn else {field.stringValue="";return nil}
                let bytes=Data(field.stringValue.utf8);field.stringValue="";return bytes
            }
            print("ready: Apple runtime-authentication Keychain items saved or preserved; no deployment or platform verification performed")
        } catch {
            print("stopped: Apple runtime-authentication intake incomplete; saved items preserved; no values printed")
            exit(78)
        }
    }
}
#endif
