import Foundation

/// The seam to the day-one LLM Variety Language call (US-G03), fulfilled by the thin stateless proxy
/// (US-N05, deferred). An implementation makes exactly one Claude call for the session and returns
/// the LLM-authored line, or throws on any failure or timeout.
///
/// The proxy must **not** be trusted to succeed: it is a best-effort upgrade over the deterministic
/// template, never a dependency the app waits on. A conforming provider is responsible for enforcing
/// its own short timeout so the resolver's `await` is always bounded; on any error it throws and the
/// resolver falls back to the template. The MVP ships no provider (US-N05 is Phase 2), so every note
/// is template-sourced until one is wired in.
protocol VarietyLanguageProvider {
    /// The single LLM call for a session's Variety Language, given the **real** contrast the engine
    /// produced (so the model can only rephrase a true contrast, never invent one). Throws on any
    /// failure or timeout.
    func line(for contrast: VarietyLanguage.SessionContrast, user: User) async throws -> String
}

/// Resolves the Variety Language note for a session (US-G03), composing the optional LLM slice over
/// the always-available deterministic template.
///
/// The contract, in order:
/// - The **contrast** is always read from the engine's own output (`VarietyLanguage.contrast`), so
///   whatever the source, the note can only name a contrast the session actually reflects.
/// - The **LLM** is attempted at most once, and only when all of: the user is cold-start-active, the
///   network is reachable, and a provider is wired. On success it yields a `source == .llm` note.
/// - On **any** failure - offline, no provider, warmed-up user, a thrown error/timeout, or an empty
///   line - it falls back to the `source == .template` line. The app never blocks and never shows a
///   blank or an error.
struct VarietyLanguageResolver {

    /// The LLM provider (US-N05). `nil` in the MVP, where every note is template-sourced.
    var provider: VarietyLanguageProvider?

    /// Whether the network is currently reachable. Defaults to always-offline, so an unconfigured
    /// resolver is template-only by construction.
    var isOnline: () -> Bool

    init(provider: VarietyLanguageProvider? = nil, isOnline: @escaping () -> Bool = { false }) {
        self.provider = provider
        self.isOnline = isOnline
    }

    /// The Variety Language note for today's `workout` against `previousLog`, for `user`. Returns
    /// `nil` only when the session has no lead pillar to name (a degenerate warm-up-only session);
    /// otherwise always returns a note, LLM-sourced when the slice succeeds and template-sourced on
    /// any failure.
    func note(
        for workout: Workout,
        previousLog: WorkoutLog?,
        user: User
    ) async -> SessionPolicy.Note? {
        guard let contrast = VarietyLanguage.contrast(for: workout, previousLog: previousLog) else {
            return nil
        }
        let template = SessionPolicy.Note(text: VarietyLanguage.line(for: contrast), source: .template)

        // The LLM slice runs at most once, only while cold-start-active and online, and never blocks:
        // any failure, timeout, or empty line falls back to the template above.
        guard user.coldStart.active, isOnline(), let provider else { return template }
        do {
            let text = try await provider.line(for: contrast, user: user)
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return template }
            return SessionPolicy.Note(text: trimmed, source: .llm)
        } catch {
            return template
        }
    }

    /// The Variety Language note against the most recent of `recentLogs` (the immediately preceding
    /// session), the same "most recent log" the engine reads its signals from.
    func note(
        for workout: Workout,
        recentLogs: [WorkoutLog],
        user: User
    ) async -> SessionPolicy.Note? {
        await note(for: workout, previousLog: VarietyLanguage.mostRecent(recentLogs), user: user)
    }
}
