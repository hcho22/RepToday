import Foundation

/// What the Account screen says about the account and its sync (M3, ADR-0016), as plain values so the
/// copy is testable without hosting the screen.
///
/// The words are calm and factual: what is saved, what is waiting, and the one thing to do when there
/// is one. Nothing is ever described as lost, because nothing is - the phone keeps every change until
/// the account has it.
struct AccountStatusPresentation: Equatable {
    /// How the user signs in ("Signed in with Apple").
    let accountLine: String
    /// The account's email address, on its own line so a long one wraps cleanly.
    let accountDetail: String?
    /// Where the data stands.
    let headline: String
    /// A second line, when there is something more to say.
    let detail: String?
    /// The SF Symbol beside the headline.
    let symbol: String
    /// Whether the screen offers signing in again.
    let offersSignIn: Bool
    /// Whether the screen offers erasing this phone's data, the only way on from an account being
    /// deleted.
    let offersErase: Bool

    init(
        account: AccountIdentity?,
        status: AccountSyncCoordinator.Status,
        pendingCount: Int,
        lastSyncedAt: Date?,
        migrationStage: LegacyAccountMigrationStage?,
        now: Date
    ) {
        accountLine = account.map { Self.methodLine($0.method) } ?? "Not signed in"
        accountDetail = account?.email.flatMap { $0.isEmpty ? nil : $0 }
        offersSignIn = status == .needsSignIn
        offersErase = status == .accountBeingDeleted

        let moving = migrationStage == .importingFromICloud || migrationStage == .uploading
        let waiting = Self.waitingPhrase(pendingCount)
        switch status {
        case .upToDate:
            headline = "Everything is saved to your account."
            detail = lastSyncedAt.map { "Last saved \(Self.relative($0, now: now))." }
            symbol = "checkmark.icloud"
        case .syncing:
            headline = moving ? "Moving your history to your account." : "Saving to your account."
            detail = pendingCount > 0 ? "\(waiting) to go. You can keep training while it saves." : nil
            symbol = "arrow.triangle.2.circlepath.icloud"
        case .waitingForConnection:
            headline = pendingCount > 0 ? "\(waiting) will save when you're online." : "Waiting for a connection."
            detail = "Everything stays on this phone until then."
            symbol = "icloud.slash"
        case .retrying:
            headline = pendingCount > 0 ? "\(waiting) waiting to save." : "Saving to your account."
            detail = "We'll keep trying. Everything stays on this phone until then."
            symbol = "exclamationmark.icloud"
        case .needsSignIn:
            headline = "Sign in again to keep saving to your account."
            detail = "Everything stays on this phone until you do."
            symbol = "person.crop.circle.badge.exclamationmark"
        case .accountBeingDeleted:
            headline = "This account is being deleted."
            detail = "That finishes on its own. This phone keeps its plan and sessions until you erase them. Erasing them lets you set up with another account, starting fresh on this phone."
            symbol = "person.crop.circle.badge.xmark"
        case .localOnly:
            headline = "This build keeps your data on this phone only."
            detail = nil
            symbol = "iphone"
        case .signedOut:
            headline = "Not signed in."
            detail = nil
            symbol = "person.crop.circle"
        }
    }

    private static func methodLine(_ method: AccountSignInMethod) -> String {
        switch method {
        case .apple: return "Signed in with Apple"
        case .google: return "Signed in with Google"
        case .email: return "Signed in with email"
        }
    }

    private static func waitingPhrase(_ count: Int) -> String {
        count == 1 ? "1 change" : "\(count) changes"
    }

    private static func relative(_ date: Date, now: Date) -> String {
        if now.timeIntervalSince(date) < 60 {
            return "just now"
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: now)
    }
}
