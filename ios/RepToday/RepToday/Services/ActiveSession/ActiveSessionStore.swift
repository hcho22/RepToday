import Foundation

/// Persists the single in-progress session per user (US-K04), keyed by the user's id and overwritten
/// in place, so a user has at most one resumable session at a time.
///
/// The active-session player writes a fresh snapshot after every meaningful change (and just before
/// backgrounding), and clears it the instant the session completes or the user discards it. The Ready
/// Screen reads it on open to offer Resume or Discard. A protocol so the player and Ready Screen stay
/// testable without CoreData: `InMemoryActiveSessionStore` backs tests, previews, and the mock
/// container, while `CoreDataActiveSessionStore` (Persistence) backs the running app and, via
/// `CDActiveSession`, lets an abandoned session survive a full relaunch.
protocol ActiveSessionStore {
    /// The in-progress session for `userId`, or `nil` when none is saved (never started, completed,
    /// or discarded).
    func load(for userId: String) async throws -> ActiveSessionState?
    /// Overwrite the in-progress session for `userId` in place (insert or update).
    func save(_ state: ActiveSessionState, for userId: String) async throws
    /// Remove the in-progress session for `userId`. A no-op when none is saved.
    func clear(for userId: String) async throws
}

/// An in-memory `ActiveSessionStore` for tests, previews, and the mock container. Deterministic and
/// isolated per instance; nothing is written to disk (so it does not itself survive relaunch - the
/// `CoreDataActiveSessionStore` provides that when the production container is wired).
actor InMemoryActiveSessionStore: ActiveSessionStore {
    private var sessions: [String: ActiveSessionState]

    init(sessions: [String: ActiveSessionState] = [:]) {
        self.sessions = sessions
    }

    func load(for userId: String) async throws -> ActiveSessionState? {
        sessions[userId]
    }

    func save(_ state: ActiveSessionState, for userId: String) async throws {
        sessions[userId] = state
    }

    func clear(for userId: String) async throws {
        sessions.removeValue(forKey: userId)
    }
}
