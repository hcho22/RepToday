import Foundation

/// The account's Premium entitlement as the server decides it (M4, US-CA02, ADR-0017):
/// `entitlements:status`, `entitlements:appAccountToken` and `entitlements:linkTransaction` in
/// `convex/entitlements.ts`.
///
/// StoreKit on the phone still owns billing and still unlocks the on-device Premium surfaces; the
/// Coach, which runs on the server, is unlocked by this entitlement instead, which App Store Server
/// Notifications keep current. The app's part is to tie its purchases to the account: it passes the
/// account's `appAccountToken` with every purchase, and sends a purchase's signed transaction after it
/// completes and on Restore Purchases, so a subscription bought before accounts - or on another device
/// - reaches the account.
protocol PremiumEntitlementServiceProtocol: Sendable {
    func status() async throws -> ServerPremiumStatus
    /// The account's App Store token, created on first use.
    func appAccountToken() async throws -> UUID
    /// Links signed StoreKit transactions (their `jwsRepresentation`) to the account and returns the
    /// resulting status. A transaction the server cannot verify, or that belongs to another account,
    /// throws.
    func link(transactions: [String]) async throws -> ServerPremiumStatus
}

struct ServerPremiumStatus: Decodable, Equatable, Sendable {
    let premium: Bool
    let expiresAt: Double?
    let productId: String?

    static let free = ServerPremiumStatus(premium: false, expiresAt: nil, productId: nil)
}

enum PremiumEntitlementError: Error, Equatable {
    case signedOut
    case offline
    /// The subscription is already linked to another Rep Today account.
    case linkedToOtherAccount
    /// The purchase could not be verified.
    case invalidTransaction
    case unavailable

    init(_ error: SyncRemoteError) {
        switch error {
        case .notSignedIn, .unauthenticated, .accountDeleting:
            self = .signedOut
        case .unreachable, .noResponse:
            self = .offline
        case .rejected(let code, _):
            switch code {
            case "linked_to_other_account": self = .linkedToOtherAccount
            case "invalid_transaction": self = .invalidTransaction
            default: self = .unavailable
            }
        case .invalidResponse:
            self = .unavailable
        }
    }
}

struct ConvexPremiumEntitlementService: PremiumEntitlementServiceProtocol {
    let client: ConvexHTTPClient

    func status() async throws -> ServerPremiumStatus {
        do {
            return try await client.call(.query, "entitlements:status", args: ConvexNoArguments())
        } catch let error as SyncRemoteError {
            throw PremiumEntitlementError(error)
        }
    }

    func appAccountToken() async throws -> UUID {
        do {
            let token: String = try await client.call(.mutation, "entitlements:appAccountToken", args: ConvexNoArguments())
            guard let uuid = UUID(uuidString: token) else { throw PremiumEntitlementError.unavailable }
            return uuid
        } catch let error as SyncRemoteError {
            throw PremiumEntitlementError(error)
        }
    }

    func link(transactions: [String]) async throws -> ServerPremiumStatus {
        var latest = ServerPremiumStatus.free
        var lastError: PremiumEntitlementError?
        for jws in transactions {
            do {
                latest = try await client.call(.action, "entitlements:linkTransaction", args: LinkArgs(jws: jws))
                if latest.premium { return latest }
            } catch let error as SyncRemoteError {
                lastError = PremiumEntitlementError(error)
            }
        }
        if let lastError, !latest.premium { throw lastError }
        return latest
    }

    private struct LinkArgs: Encodable, Sendable {
        let jws: String
    }
}

/// An in-memory entitlement for previews and tests.
actor MockPremiumEntitlementService: PremiumEntitlementServiceProtocol {
    private(set) var current: ServerPremiumStatus
    private(set) var linked: [String] = []
    private let token = UUID()
    private var linkResult: ServerPremiumStatus?
    private var linkError: PremiumEntitlementError?

    init(premium: Bool = false) {
        current = ServerPremiumStatus(premium: premium, expiresAt: nil, productId: premium ? SubscriptionPlan.ProductID.monthly : nil)
    }

    func set(premium: Bool) {
        current = ServerPremiumStatus(premium: premium, expiresAt: nil, productId: premium ? SubscriptionPlan.ProductID.monthly : nil)
    }

    /// What the next `link` answers; by default a link of any transaction makes the account Premium.
    func setLinkOutcome(_ result: ServerPremiumStatus?, error: PremiumEntitlementError? = nil) {
        linkResult = result
        linkError = error
    }

    func status() async throws -> ServerPremiumStatus { current }

    func appAccountToken() async throws -> UUID { token }

    func link(transactions: [String]) async throws -> ServerPremiumStatus {
        linked.append(contentsOf: transactions)
        if let linkError { throw linkError }
        if transactions.isEmpty { return current }
        current = linkResult ?? ServerPremiumStatus(premium: true, expiresAt: nil, productId: SubscriptionPlan.ProductID.monthly)
        return current
    }
}
