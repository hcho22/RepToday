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
    @State private var isEraseConfirmationPresented = false
    @State private var isErasing = false
    @State private var eraseFailed = false

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
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                card {
                    row(
                        icon: appState.account?.method == .email ? .mail : .profile,
                        title: presentation.accountLine,
                        detail: presentation.accountDetail,
                        detailIsAddress: true
                    )
                }

                card {
                    row(
                        icon: presentation.icon,
                        iconColor: presentation.icon == .check ? Theme.Colors.legs : Theme.Colors.text2,
                        title: presentation.headline,
                        detail: presentation.detail
                    )
                }

                if presentation.offersSignIn, let reSignIn {
                    AccountSignInPanel(viewModel: reSignIn)
                }

                if presentation.offersErase {
                    eraseButton
                }

                Text("Your plan and sessions live on this phone first and save to your account whenever you're connected. Premium purchases and restores use your App Store account.")
                    .font(Theme.Typography.callout)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Theme.Spacing.xs)
                    .padding(.top, Theme.Spacing.xs)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.Spacing.screenMargin)
            .padding(.bottom, Theme.Spacing.mlg)
        }
        .foregroundStyle(Theme.Colors.textPrimary)
        .background(Theme.Colors.background)
        .screenTitle("Account")
        .alert(AccountSignInPanel.eraseConfirmationTitle, isPresented: $isEraseConfirmationPresented) {
            Button("Erase", role: .destructive) { Task { await eraseThisDevice() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(AccountSignInPanel.eraseConfirmationMessage)
        }
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

    /// Erasing this phone's data, offered once the account it saves to is being deleted.
    private var eraseButton: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Button(role: .destructive) {
                isEraseConfirmationPresented = true
            } label: {
                HStack(spacing: Theme.Spacing.smd) {
                    if isErasing {
                        ProgressView()
                            .tint(Theme.Colors.danger)
                    } else {
                        ScaledIcon(icon: .trash, size: 22, relativeTo: .headline)
                    }
                    Text("Erase this phone's Rep Today data")
                        .font(Theme.Typography.headline)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, minHeight: Theme.Spacing.rowHeight, alignment: .leading)
                .padding(.horizontal, 18)
                .cardSurface()
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.Colors.danger)
            .disabled(isErasing)
            .accessibilityHint("Asks you to confirm first")
            if eraseFailed {
                Text("We couldn't erase this phone's data. Please try again.")
                    .font(Theme.Typography.callout)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .padding(.horizontal, Theme.Spacing.xs)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func eraseThisDevice() async {
        isErasing = true
        eraseFailed = false
        defer { isErasing = false }
        do {
            try await services.accountDeletionService.eraseThisDevice(appState: appState)
        } catch {
            eraseFailed = true
        }
    }

    /// An icon beside a title and an optional second line, the second line aligned under the title.
    /// An address stays on one line, shortened in the middle if it must be: wrapping would hyphenate
    /// it and misstate it. VoiceOver reads it in full.
    private func row(
        icon: AppIcon, iconColor: Color = Theme.Colors.text2, title: String, detail: String?,
        detailIsAddress: Bool = false
    ) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail, detailIsAddress {
                    Text(detail)
                        .font(Theme.Typography.callout)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .minimumScaleFactor(0.5)
                } else if let detail {
                    Text(detail)
                        .font(Theme.Typography.callout)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } icon: {
            ScaledIcon(icon: icon, size: 24, relativeTo: .headline)
                .foregroundStyle(iconColor)
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        }
        .labelStyle(AccountRowLabelStyle())
        .accessibilityElement(children: .combine)
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, minHeight: Theme.Spacing.rowHeight, alignment: .leading)
            .padding(.horizontal, 18)
            .padding(.vertical, Theme.Spacing.md)
            .cardSurface()
    }
}

/// An Account row's icon centered on its text, 14 pt from it; at accessibility text sizes the icon sits
/// above the text so the text, an address above all, keeps the row's full width.
private struct AccountRowLabelStyle: LabelStyle {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    func makeBody(configuration: Configuration) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Spacing.sm))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 14))
        layout {
            configuration.icon
            configuration.title
        }
    }
}
