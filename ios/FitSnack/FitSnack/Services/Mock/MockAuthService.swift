import Foundation

final class MockAuthService: AuthServiceProtocol {
    private let userIdKey = "mockUserId"
    private let displayNameKey = "mockDisplayName"

    var currentUserId: String? {
        UserDefaults.standard.string(forKey: userIdKey)
    }

    var isAuthenticated: Bool {
        currentUserId != nil
    }

    func signIn(displayName: String) async throws -> String {
        let userId = currentUserId ?? UUID().uuidString
        UserDefaults.standard.set(userId, forKey: userIdKey)
        UserDefaults.standard.set(displayName, forKey: displayNameKey)
        return userId
    }

    func signOut() {
        UserDefaults.standard.removeObject(forKey: userIdKey)
        UserDefaults.standard.removeObject(forKey: displayNameKey)
    }
}
