import SwiftUI

/// The Account screen (M3): who is signed in and how much of the device's data is on the account.
///
/// Signing in is required and happens before the app opens, so there is nothing optional here. The one
/// action it can offer is signing in again, when the account no longer accepts this device's session;
/// the data stays on the phone until then. Signing in to a different account than the one this phone
/// saves to is refused - two accounts' data never mix - and offers erasing this phone's data instead.
/// Premium stays with the App Store account.
struct AccountView: View {
    @Environment(\.services) private var services
    @Environment(AppState.self) private var appState
    @Environment(AccountSyncCoordinator.self) private var syncCoordinator: AccountSyncCoordinator?
    @State private var reSignIn: AccountSignInViewModel?

    var body: some View {
        let presentation = AccountStatusPresentation(
            account: appState.account,
            status: syncCoordinator?.status ?? (appState.account == nil ? .signedOut : .localOnly),
            pendingCount: syncCoordinator?.pendingCount ?? 0,
            lastSyncedAt: syncCoordinator?.lastSyncedAt,
            migrationStage: appState.legacyMigrationStage,
            now: Date()
        )
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                card {
                    row(
                        symbol: "person.crop.circle.fill",
                        title: presentation.accountLine,
                        detail: presentation.accountDetail,
                        detailIsAddress: true
                    )
                }

                card {
                    row(symbol: presentation.symbol, title: presentation.headline, detail: presentation.detail)
                }

                if presentation.offersSignIn, let reSignIn {
                    AccountSignInPanel(viewModel: reSignIn)
                }

                Text("Your plan and sessions live on this phone first and save to your account whenever you're connected. Premium purchases and restores use your App Store account.")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Spacing.lg)
        }
        .foregroundStyle(Theme.Colors.textPrimary)
        .background(Theme.Colors.background)
        .navigationTitle("Account")
        .onAppear {
            if reSignIn == nil {
                let deletionService = services.accountDeletionService
                reSignIn = AccountSignInViewModel(
                    auth: services.accountAuthService,
                    context: .existingUser,
                    eraseThisDevice: { [appState] in try await deletionService.eraseThisDevice(appState: appState) }
                ) { identity in
                    if let syncCoordinator {
                        try syncCoordinator.linkAccount(identity)
                    } else {
                        try appState.linkAccount(identity)
                    }
                }
            }
        }
        .task { await syncCoordinator?.syncNow() }
    }

    /// An icon beside a title and an optional second line, the second line aligned under the title.
    /// An address stays on one line, shortened in the middle if it must be: wrapping would hyphenate
    /// it and misstate it. VoiceOver reads it in full.
    private func row(symbol: String, title: String, detail: String?, detailIsAddress: Bool = false) -> some View {
        Label {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(title)
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail, detailIsAddress {
                    Text(detail)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .minimumScaleFactor(0.8)
                } else if let detail {
                    Text(detail)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(Theme.Colors.accent)
        }
        .accessibilityElement(children: .combine)
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Spacing.md)
            .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Spacing.cardCornerRadius))
    }
}
