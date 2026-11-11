import SwiftUI

/// The one-time sign-in a user who onboarded before accounts meets on their next launch (M3, US-AU04,
/// decision 23). It is required - there is no skip - and it is the only thing that changes for them:
/// once signed in, the app opens as before and their history moves to the account in the background.
///
/// Signing in links the device (`AccountSyncCoordinator.linkAccount`), which needs no connection
/// beyond the sign-in itself; the upload then runs whenever the phone is online.
struct AccountRequiredView: View {
    @State private var signIn: AccountSignInViewModel

    init(auth: any AccountAuthServiceProtocol, onSignedIn: @escaping @MainActor (AccountIdentity) throws -> Void) {
        _signIn = State(initialValue: AccountSignInViewModel(auth: auth, context: .existingUser) { identity in
            try onSignedIn(identity)
        })
    }

    var body: some View {
        ZStack {
            Theme.Colors.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    Image(systemName: "person.crop.circle.badge.checkmark")
                        .font(.system(size: 56, weight: .semibold))
                        .foregroundStyle(Theme.Colors.accent)
                        .padding(.top, Theme.Spacing.xl)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        Text("Keep your history")
                            .font(Theme.Typography.largeTitle)
                            .foregroundStyle(Theme.Colors.textPrimary)
                            .accessibilityAddTraits(.isHeader)
                        Text("Rep Today now saves to your account. Sign in once and everything on this phone - your plan and every session you've finished - comes with you.")
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    AccountSignInPanel(viewModel: signIn)

                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text("Your sessions stay on this phone while they save, and you can keep training offline.")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Link(destination: LegalLinks.privacyPolicy) {
                            Text("Privacy Policy")
                                .font(Theme.Typography.caption)
                                .foregroundStyle(Theme.Colors.accent)
                                .frame(minHeight: Theme.Spacing.minTouchTarget, alignment: .leading)
                        }
                        .accessibilityLabel("Privacy Policy")
                    }
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.bottom, Theme.Spacing.xl)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .statusBarBacking()
    }
}
