import Foundation
import Security
import CryptoKit

final class RuntimeIntakeStoreDouble:CoachRuntimeIntakeStore {
    var existing:Set<CoachRuntimeCredential> = []
    var written=[CoachRuntimeCredential]()
    var denied:CoachRuntimeCredential?
    var failSave=false
    func status(_ credential:CoachRuntimeCredential)->OSStatus {
        if denied == credential {return errSecAuthFailed}
        return existing.contains(credential) ? errSecSuccess : errSecItemNotFound
    }
    func add(_ bytes:Data,credential:CoachRuntimeCredential)->OSStatus {
        if failSave {return errSecAuthFailed};written.append(credential);existing.insert(credential);return errSecSuccess
    }
}
@main struct RuntimeIntakeTests {
    static func main() throws {
        // Generated fixture private key is not an Apple API credential; it never leaves this process.
        let pem=P256.Signing.PrivateKey().pemRepresentation
        let fixture:[CoachRuntimeCredential:String]=[.appPrefix:"FIXTURE001",.appID:"1",.keyID:"FIXTURE002",
            .issuerID:"00000000-0000-4000-8000-000000000000",.privateKey:pem]
        for credential in CoachRuntimeCredential.allCases {
            precondition(credential.valid(Data(fixture[credential]!.utf8)))
            precondition(!credential.valid(Data()))
            precondition(!credential.valid(Data(repeating:65,count:4097)))
        }
        precondition(!CoachRuntimeCredential.appID.valid(Data("9007199254740992".utf8)))
        precondition(!CoachRuntimeCredential.privateKey.valid(Data("-----BEGIN PRIVATE KEY-----\ninvalid".utf8)))
        let store=RuntimeIntakeStoreDouble();store.existing=[.keyID]
        try intakeCoachRuntimeKeys(store:store){credential in precondition(credential != .keyID);return Data(fixture[credential]!.utf8)}
        precondition(store.written.count == 4)
        try intakeCoachRuntimeKeys(store:store){_ in preconditionFailure("existing item must never be prompted or overwritten")}
        for mode in 0...3 {
            let store=RuntimeIntakeStoreDouble()
            if mode == 0 {store.denied = .appPrefix}
            if mode == 3 {store.failSave=true}
            do {
                try intakeCoachRuntimeKeys(store:store){credential in
                    if mode == 1 {return nil};if mode == 2 {return Data("invalid".utf8)}
                    return Data(fixture[credential]!.utf8)
                }
                preconditionFailure("failure must stop")
            } catch {}
            precondition(store.written.isEmpty)
        }
        print("validated: Apple runtime intake format, preservation, cancellation and error doubles; no Keychain or UI execution")
    }
}
