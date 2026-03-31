import Foundation

protocol AuthServiceProtocol {
    var currentUserId: String? { get }
    var isAuthenticated: Bool { get }
    func signIn(displayName: String) async throws -> String
    func signOut()
}
