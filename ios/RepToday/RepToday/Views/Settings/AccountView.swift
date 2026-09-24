import AuthenticationServices
import SwiftUI

/// Reachable after onboarding; the credential is optional and never a purchase prerequisite.
struct AccountView: View {
    @State private var viewModel: AccountViewModel

    init(authService: any AuthServiceProtocol) {
        _viewModel = State(initialValue: AccountViewModel(authService: authService))
    }

    init(viewModel: AccountViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                switch viewModel.state {
                case .loading:
                    SwiftUI.ProgressView("Checking sign-in status")
                case .signedIn:
                    Label("Signed in with Apple", systemImage: "checkmark.seal.fill")
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Colors.accent)
                case .signedOut:
                    SignInWithAppleButton(.signIn) { request in
                        // No name or email is needed: this app stores only the opaque identifier.
                        request.requestedScopes = []
                        viewModel.beginSignIn()
                    } onCompletion: { result in
                        Task { await viewModel.handleAppleSignIn(result) }
                    }
                    .signInWithAppleButtonStyle(.black)
                    .frame(height: Theme.Spacing.buttonHeight)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Spacing.cardCornerRadius))
                    .disabled(!viewModel.canSignIn)
                    .accessibilityHint("Optional. Your existing workouts and history are kept.")
                    if viewModel.isSigningIn {
                        SwiftUI.ProgressView("Signing in")
                    }
                case .unavailable:
                    Button("Retry sign-in status") { Task { await viewModel.load() } }
                        .frame(minHeight: Theme.Spacing.minTouchTarget)
                }

                if let message = viewModel.message {
                    Text(message)
                        .font(Theme.Typography.body)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("Sign in is optional. Your workouts and history stay as they are. Premium purchases and restores use your App Store account and don't require signing in here.")
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
        .task { await viewModel.load() }
    }
}
