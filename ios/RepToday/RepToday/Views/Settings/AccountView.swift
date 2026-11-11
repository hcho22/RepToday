import SwiftUI

/// The Account screen (M3): who is signed in and how much of the device's data is on the account.
///
/// Signing in is required and happens before the app opens, so there is nothing optional here. The one
/// action it can offer is signing in again, when the account no longer accepts this device's session;
/// the data stays on the phone until then. Premium stays with the App Store account.
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
                    Label {
                        Text(presentation.accountLine)
                            .font(Theme.Typography.headline)
                            .foregroundStyle(Theme.Colors.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "person.crop.circle.fill")
                            .foregroundStyle(Theme.Colors.accent)
                    }
                    .accessibilityElement(children: .combine)
                }

                card {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Label {
                            Text(presentation.headline)
                                .font(Theme.Typography.headline)
                                .foregroundStyle(Theme.Colors.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                        } icon: {
                            Image(systemName: presentation.symbol)
                                .foregroundStyle(Theme.Colors.accent)
                        }
                        if let detail = presentation.detail {
                            Text(detail)
                                .font(Theme.Typography.body)
                                .foregroundStyle(Theme.Colors.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .accessibilityElement(children: .combine)
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
                reSignIn = AccountSignInViewModel(auth: services.accountAuthService, context: .existingUser) { identity in
                    if let syncCoordinator {
                        syncCoordinator.linkAccount(identity)
                    } else {
                        appState.linkAccount(identity)
                    }
                }
            }
        }
        .task { await syncCoordinator?.syncNow() }
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Spacing.md)
            .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Spacing.cardCornerRadius))
    }
}
