import Foundation

/// The Coach agent on the account backend (M4, US-CA01/US-CA03, ADR-0017): `coach:history`,
/// `coach:send` and `coach:recordProposalOutcome` in `convex/coach.ts`.
///
/// A turn runs on the server, which reads the user's own synced records, checks their Premium
/// entitlement and keeps the conversation. This client only carries the message and today's plan up
/// and the stored messages back; it decides nothing.
protocol CoachServiceProtocol: Sendable {
    /// The conversation so far, oldest first.
    func history() async throws -> [CoachMessage]
    /// One turn. `clientMessageId` makes a retry of the same message return the same answer.
    func send(clientMessageId: UUID, message: String, today: CoachTodaySnapshot?) async throws -> CoachTurn
    /// Records what the user did with a proposal, so the conversation remembers it.
    func recordOutcome(messageId: String, proposalId: String, status: CoachProposal.Status) async throws
}

/// One stored turn: the user's message and the Coach's reply.
struct CoachTurn: Decodable, Equatable, Sendable {
    let user: CoachMessage
    let coach: CoachMessage
}

/// Why a Coach call did not succeed, in the terms the Coach tab shows.
enum CoachServiceError: Error, Equatable {
    /// No account is signed in, or its session was refused.
    case signedOut
    /// The server found no active Premium entitlement for this account (US-CA02).
    case notPremium
    /// Today's turn limit is used up.
    case limitReached
    /// The model is not configured or did not answer; worth trying again.
    case unavailable
    /// No connection, or no answer came back; worth trying again.
    case offline
    /// The message was refused as malformed (empty or too long).
    case invalidMessage
    /// The account is being deleted.
    case accountDeleting

    /// Maps the sync layer's error onto the Coach's terms.
    init(_ error: SyncRemoteError) {
        switch error {
        case .notSignedIn, .unauthenticated:
            self = .signedOut
        case .accountDeleting:
            self = .accountDeleting
        case .unreachable, .noResponse:
            self = .offline
        case .rejected(let code, _):
            switch code {
            case "not_premium": self = .notPremium
            case "limit_reached": self = .limitReached
            case "invalid_message": self = .invalidMessage
            default: self = .unavailable
            }
        case .invalidResponse:
            self = .unavailable
        }
    }
}

/// The Coach over Convex.
struct ConvexCoachService: CoachServiceProtocol {
    let client: ConvexHTTPClient

    /// How long a turn may take: the server allows the model 40 seconds.
    static let turnTimeout: TimeInterval = 60

    func history() async throws -> [CoachMessage] {
        do {
            let result: HistoryResult = try await client.call(.query, "coach:history", args: ConvexNoArguments())
            return result.messages
        } catch let error as SyncRemoteError {
            throw CoachServiceError(error)
        }
    }

    func send(clientMessageId: UUID, message: String, today: CoachTodaySnapshot?) async throws -> CoachTurn {
        do {
            return try await client.call(
                .action,
                "coach:send",
                args: SendArgs(clientMessageId: clientMessageId.uuidString.lowercased(), message: message, today: today),
                timeout: Self.turnTimeout
            )
        } catch let error as SyncRemoteError {
            throw CoachServiceError(error)
        }
    }

    func recordOutcome(messageId: String, proposalId: String, status: CoachProposal.Status) async throws {
        do {
            let _: OutcomeResult = try await client.call(
                .mutation,
                "coach:recordProposalOutcome",
                args: OutcomeArgs(messageId: messageId, proposalId: proposalId, status: status.rawValue)
            )
        } catch let error as SyncRemoteError {
            throw CoachServiceError(error)
        }
    }

    private struct HistoryResult: Decodable {
        let messages: [CoachMessage]
    }

    struct SendArgs: Encodable, Sendable {
        let clientMessageId: String
        let message: String
        let today: CoachTodaySnapshot?

        private enum CodingKeys: String, CodingKey {
            case clientMessageId, message, today
        }

        // An absent snapshot is omitted, never `null`, which the server's validator would refuse.
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(clientMessageId, forKey: .clientMessageId)
            try container.encode(message, forKey: .message)
            try container.encodeIfPresent(today, forKey: .today)
        }
    }

    private struct OutcomeArgs: Encodable, Sendable {
        let messageId: String
        let proposalId: String
        let status: String
    }

    private struct OutcomeResult: Decodable {
        let status: String
    }
}

/// A scripted Coach for previews and tests: answers from a closure, records what it was sent.
actor MockCoachService: CoachServiceProtocol {
    private(set) var stored: [CoachMessage]
    private(set) var sent: [(message: String, today: CoachTodaySnapshot?)] = []
    private(set) var outcomes: [(messageId: String, proposalId: String, status: CoachProposal.Status)] = []
    private var reply: @Sendable (String) throws -> (text: String, proposals: [CoachProposal])
    private let now: @Sendable () -> Date

    init(
        history: [CoachMessage] = [],
        now: @escaping @Sendable () -> Date = { Date() },
        reply: @escaping @Sendable (String) throws -> (text: String, proposals: [CoachProposal]) = { _ in
            ("You're someone who shows up. What would help today?", [])
        }
    ) {
        stored = history
        self.now = now
        self.reply = reply
    }

    func setReply(_ reply: @escaping @Sendable (String) throws -> (text: String, proposals: [CoachProposal])) {
        self.reply = reply
    }

    func history() async throws -> [CoachMessage] { stored }

    func send(clientMessageId: UUID, message: String, today: CoachTodaySnapshot?) async throws -> CoachTurn {
        sent.append((message, today))
        let answer = try reply(message)
        let user = CoachMessage(id: clientMessageId.uuidString.lowercased(), role: .user, text: message, createdAt: now(), proposals: [])
        let coach = CoachMessage(id: UUID().uuidString.lowercased(), role: .coach, text: answer.text, createdAt: now(), proposals: answer.proposals)
        stored.append(contentsOf: [user, coach])
        return CoachTurn(user: user, coach: coach)
    }

    func recordOutcome(messageId: String, proposalId: String, status: CoachProposal.Status) async throws {
        outcomes.append((messageId, proposalId, status))
        guard let index = stored.firstIndex(where: { $0.id == messageId }),
              let proposalIndex = stored[index].proposals.firstIndex(where: { $0.id == proposalId }) else { return }
        stored[index].proposals[proposalIndex].status = status
    }
}
