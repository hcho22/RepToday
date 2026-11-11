import AuthenticationServices
import SwiftUI

/// The account sign-in controls (M3, decision 23): Apple, Google and an email code, then the
/// signed-in confirmation. Shared by onboarding's "Save your plan" step and the existing-user sign-in
/// screen, which each supply their own heading.
///
/// Every color, font and dimension comes from `Theme`; controls are full-width, at least 56pt tall, and
/// grow with Dynamic Type instead of truncating.
struct AccountSignInPanel: View {
    @Bindable var viewModel: AccountSignInViewModel
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var focusedField: Field?
    /// Apple's button draws its title in proportion to its height and ignores Dynamic Type, so its
    /// height scales with the text size instead. It stops at one and a half times the standard: past
    /// that the title is limited by the button's width, and the button would only outgrow the two-line
    /// buttons beside it.
    @ScaledMetric(relativeTo: .headline) private var appleButtonHeight: CGFloat = Theme.Spacing.buttonHeight

    private enum Field {
        case email, code
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            switch viewModel.phase {
            case .choosing:
                choices
            case .email:
                emailEntry
            case .code(let challenge):
                codeEntry(challenge)
            case .signedIn(let identity):
                signedIn(identity)
            }

            if let message = viewModel.message {
                Label {
                    Text(message)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "info.circle")
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
            }

            #if DEBUG
            if !viewModel.isConfigured {
                Text("Development build: sign-in is simulated and nothing leaves this phone. On the email code screen, use \(StubAccountAuthService.acceptedCode).")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            #endif
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task { await viewModel.load() }
        .onChange(of: viewModel.message) { _, message in
            if let message {
                AccessibilityNotification.Announcement(message).post()
            }
        }
    }

    // MARK: - Choosing

    private var choices: some View {
        VStack(spacing: Theme.Spacing.sm) {
            SignInWithAppleButton(.continue) { request in
                // Only the account email is asked for; Rep Today never stores a name from Apple.
                request.requestedScopes = [.email]
                viewModel.beginApple()
            } onCompletion: { result in
                Task { await viewModel.handleApple(result) }
            }
            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
            .frame(maxWidth: .infinity)
            .frame(height: min(appleButtonHeight, Theme.Spacing.buttonHeight * 1.5))
            .clipShape(RoundedRectangle(cornerRadius: Theme.Spacing.cardCornerRadius))
            .disabled(viewModel.isWorking)
            .accessibilityHint("Signs in with your Apple Account")

            // Text only: Google's mark is a licensed asset this app does not ship
            // (docs/asset-attribution.md), and a stand-in glyph would misrepresent it.
            secondaryButton("Continue with Google", working: viewModel.activity == .google) {
                Task { await viewModel.signInWithGoogle() }
            }
            .accessibilityHint("Opens Google sign-in")

            secondaryButton("Continue with email", working: false) {
                viewModel.chooseEmail()
                focusedField = .email
            }
            .accessibilityHint("Sends a one-time code to your email")
        }
    }

    // MARK: - Email

    private var emailEntry: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Your email")
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.textPrimary)
            inputField {
                TextField("you@example.com", text: $viewModel.email)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.send)
                    .focused($focusedField, equals: .email)
                    .onSubmit { Task { await viewModel.sendCode() } }
                    .accessibilityLabel("Email address")
            }
            primaryButton("Send code", working: viewModel.activity == .sendingCode, enabled: viewModel.canSendCode) {
                Task { await viewModel.sendCode() }
            }
            textButton("Back to all sign-in options") { viewModel.showChoices() }
        }
    }

    // MARK: - Code

    private func codeEntry(_ challenge: EmailCodeChallenge) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Enter the code we sent to \(challenge.email).")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            inputField {
                TextField("Code", text: $viewModel.code)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .focused($focusedField, equals: .code)
                    .accessibilityLabel("Code from your email")
            }
            primaryButton("Sign in", working: viewModel.activity == .verifyingCode, enabled: viewModel.canVerifyCode) {
                Task { await viewModel.verifyCode() }
            }
            textButton("Send a new code") { Task { await viewModel.resendCode() } }
            textButton("Use a different email") {
                viewModel.chooseEmail()
                focusedField = .email
            }
        }
        .onAppear { focusedField = .code }
    }

    // MARK: - Signed in

    private func signedIn(_ identity: AccountIdentity) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Label {
                Text(Self.signedInText(identity))
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(Theme.Colors.accent)
            }
            .accessibilityElement(children: .combine)

            if viewModel.activity == .finishing {
                HStack(spacing: Theme.Spacing.sm) {
                    ProgressView()
                    Text("Saving your plan")
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                .frame(minHeight: Theme.Spacing.minTouchTarget)
                .accessibilityElement(children: .combine)
            } else {
                primaryButton("Continue", working: false, enabled: true) {
                    Task { await viewModel.retryFinishing() }
                }
                textButton("Use a different account") { Task { await viewModel.useDifferentAccount() } }
            }
        }
    }

    static func signedInText(_ identity: AccountIdentity) -> String {
        if let email = identity.email, !email.isEmpty {
            return "Signed in as \(email)"
        }
        switch identity.method {
        case .apple: return "Signed in with Apple"
        case .google: return "Signed in with Google"
        case .email: return "Signed in"
        }
    }

    // MARK: - Controls

    private func primaryButton(_ title: String, working: Bool, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                if working {
                    ProgressView().tint(Theme.Colors.onAccent)
                } else {
                    Text(title)
                        .font(Theme.Typography.button)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: Theme.Spacing.buttonHeight)
        }
        .accentFilledButtonStyle()
        .clipShape(RoundedRectangle(cornerRadius: Theme.Spacing.cardCornerRadius))
        .disabled(!enabled || viewModel.isWorking)
        .accessibilityLabel(title)
    }

    private func secondaryButton(_ title: String, working: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.sm) {
                if working {
                    ProgressView()
                }
                Text(title)
                    .font(Theme.Typography.button)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: Theme.Spacing.buttonHeight)
            .padding(.horizontal, Theme.Spacing.md)
            .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Spacing.cardCornerRadius))
            .contentShape(RoundedRectangle(cornerRadius: Theme.Spacing.cardCornerRadius))
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isWorking)
        .accessibilityLabel(title)
    }

    private func textButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.accent)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: Theme.Spacing.minTouchTarget, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isWorking)
    }

    private func inputField<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .font(Theme.Typography.body)
            .foregroundStyle(Theme.Colors.textPrimary)
            .padding(.horizontal, Theme.Spacing.md)
            .frame(minHeight: Theme.Spacing.buttonHeight)
            .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Spacing.cardCornerRadius))
    }
}
