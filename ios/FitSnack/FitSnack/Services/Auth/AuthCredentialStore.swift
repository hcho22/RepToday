import Foundation
import Security

/// Persists the Sign in with Apple user identifier (US-N01).
///
/// The identifier keys the user record, so it must survive relaunch (and, in production,
/// reinstall) and stay private on-device. This is the single seam behind `AppleAuthService`,
/// so the service composes an in-memory store in tests/previews and a Keychain-backed store in
/// the running app without any other code knowing the difference.
protocol AuthCredentialStore: Sendable {
    /// The persisted Sign in with Apple user identifier, or `nil` if the user has not signed in.
    func loadIdentifier() async throws -> String?
    /// Persists the signed-in identifier, overwriting any previous value.
    func save(_ identifier: String) async throws
    /// Clears the persisted identifier (sign-out).
    func clear() async throws
}

/// In-memory store for tests, previews, and the mock container - no Keychain, no disk.
actor InMemoryAuthCredentialStore: AuthCredentialStore {
    private var identifier: String?

    init(identifier: String? = nil) {
        self.identifier = identifier
    }

    func loadIdentifier() async throws -> String? { identifier }

    func save(_ identifier: String) async throws { self.identifier = identifier }

    func clear() async throws { identifier = nil }
}

/// The production credential store: the identifier lives in the Keychain, so it survives
/// relaunch and reinstall, stays encrypted at rest, and never leaves the device. The Keychain
/// C API is thread-safe and the store holds only immutable configuration, so it is `Sendable`
/// without a lock. Ready to be wired into the production `ServiceContainer` (US-N02); `mock()`
/// keeps the in-memory store so tests stay disk- and Keychain-free.
final class KeychainAuthCredentialStore: AuthCredentialStore {
    private let service: String
    private let account: String

    init(
        service: String = "com.fitsnack.app.auth",
        account: String = "apple.user.identifier"
    ) {
        self.service = service
        self.account = account
    }

    func loadIdentifier() async throws -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data, let string = String(data: data, encoding: .utf8) else {
                throw AuthError.invalidCredential
            }
            return string
        case errSecItemNotFound:
            return nil
        default:
            throw AuthError.failed("keychain read failed (\(status))")
        }
    }

    func save(_ identifier: String) async throws {
        let data = Data(identifier.utf8)
        var query = baseQuery()

        // Try an in-place update first so we never leave two items for the same account.
        let updateStatus = SecItemUpdate(
            query as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            query[kSecValueData as String] = data
            let addStatus = SecItemAdd(query as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw AuthError.failed("keychain add failed (\(addStatus))")
            }
        default:
            throw AuthError.failed("keychain update failed (\(updateStatus))")
        }
    }

    func clear() async throws {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AuthError.failed("keychain delete failed (\(status))")
        }
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
    }
}
