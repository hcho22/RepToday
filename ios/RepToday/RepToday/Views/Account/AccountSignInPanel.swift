import SwiftUI

/// The account sign-in controls (M3, decision 23): Apple, Google and an email code, then the
/// signed-in confirmation. Shared by onboarding's "Save your plan" step and the existing-user sign-in
/// screen, which each supply their own heading.
///
/// Every color, font and dimension comes from `Theme`; controls are full-width, at least 56pt tall, and
/// grow with Dynamic Type instead of truncating. The three sign-in choices share one type size, weight
/// and height at every text size: Apple's own button draws its title at a fixed size, so the Apple
/// choice is a custom Sign in with Apple button in Apple's black (light) or white (dark) style with the
/// Apple logo and "Continue with Apple", which Apple's guidelines allow.
struct AccountSignInPanel: View {
    @Bindable var viewModel: AccountSignInViewModel
    @FocusState private var focusedField: Field?

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
            case .belongsToAnotherAccount(let attempted):
                anotherAccount(attempted)
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
        .alert(Self.eraseConfirmationTitle, isPresented: $viewModel.isEraseConfirmationPresented) {
            Button("Erase", role: .destructive) { Task { await viewModel.confirmErase() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(Self.eraseConfirmationMessage)
        }
        .task { await viewModel.load() }
        .onChange(of: viewModel.message) { _, message in
            if let message {
                AccessibilityNotification.Announcement(message).post()
            }
        }
    }

    // MARK: - Choosing

    private var choices: some View {
        EqualHeightColumn(spacing: Theme.Spacing.sm) {
            choiceButton(
                "Continue with Apple",
                logo: "apple.logo",
                fill: Theme.Colors.signInWithAppleFill,
                ink: Theme.Colors.signInWithAppleInk,
                working: viewModel.activity == .apple
            ) {
                Task { await viewModel.signInWithApple() }
            }
            .accessibilityHint("Signs in with your Apple Account")

            // Text only: Google's mark is a licensed asset this app does not ship
            // (docs/asset-attribution.md), and a stand-in glyph would misrepresent it.
            choiceButton(
                "Continue with Google",
                fill: Theme.Colors.surface,
                ink: Theme.Colors.textPrimary,
                working: viewModel.activity == .google
            ) {
                Task { await viewModel.signInWithGoogle() }
            }
            .accessibilityHint("Opens Google sign-in")

            choiceButton("Continue with email", fill: Theme.Colors.surface, ink: Theme.Colors.textPrimary, working: false) {
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

    // MARK: - Another account's phone

    private func anotherAccount(_ attempted: AccountIdentity) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(Self.anotherAccountTitle)
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(Self.anotherAccountText(attempted, canErase: viewModel.canEraseThisDevice))
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            primaryButton("Sign in to my account", working: false, enabled: true) {
                viewModel.showChoices()
            }
            if viewModel.canEraseThisDevice {
                Button(role: .destructive) {
                    viewModel.requestErase()
                } label: {
                    HStack(spacing: Theme.Spacing.sm) {
                        if viewModel.activity == .erasing {
                            ProgressView()
                        }
                        Text("Erase this phone's Rep Today data")
                            .font(Theme.Typography.body)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(minHeight: Theme.Spacing.minTouchTarget, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.Colors.danger)
                .disabled(viewModel.isWorking)
                .accessibilityHint("Asks you to confirm first")
            }
        }
    }

    static let anotherAccountTitle = "This phone saves to another account"

    static func anotherAccountText(_ attempted: AccountIdentity, canErase: Bool) -> String {
        let who = attempted.email.map { "You signed in as \($0)." } ?? "You signed in to a different account."
        let keep = "Rep Today keeps each account's plan and sessions to that account, so this phone stays with the one it already saves to."
        return canErase
            ? "\(who) \(keep) Sign in to that account, or erase this phone's Rep Today data to start again with another one."
            : "\(who) \(keep) Sign in to that account to carry on."
    }

    static let eraseConfirmationTitle = "Erase this phone's Rep Today data?"
    static let eraseConfirmationMessage = "Your plan, sessions and activities are erased from this phone, including changes not yet saved to your account. Your account is not deleted. You'll set Rep Today up again and choose an account at the end."

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

    /// One sign-in choice: the same type, weight, padding and corner radius for every choice, filling the
    /// height its column gives it so the three always match.
    private func choiceButton(
        _ title: String,
        logo: String? = nil,
        fill: Color,
        ink: Color,
        working: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.sm) {
                if working {
                    ProgressView().tint(ink)
                }
                // The logo sits inside the title text, so the title wraps exactly like the other
                // choices' at large text sizes instead of being pushed narrower by a separate glyph.
                // VoiceOver reads the button's own label, so the logo is never spoken.
                (logo.map { Text("\(Image(systemName: $0))\u{00A0}\u{00A0}") } ?? Text("")) + Text(title)
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .font(Theme.Typography.button)
            .foregroundStyle(ink)
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            .frame(maxWidth: .infinity, minHeight: Theme.Spacing.buttonHeight, maxHeight: .infinity)
            .background(fill, in: RoundedRectangle(cornerRadius: Theme.Spacing.cardCornerRadius))
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

/// Stacks its children full width and gives every one the height of the tallest, so buttons whose
/// titles wrap differently at large text sizes still match.
private struct EqualHeightColumn: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? subviews.map { $0.sizeThatFits(.unspecified).width }.max() ?? 0
        let height = rowHeight(width: width, subviews: subviews)
        let count = CGFloat(subviews.count)
        return CGSize(width: width, height: height * count + spacing * max(count - 1, 0))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let height = rowHeight(width: bounds.width, subviews: subviews)
        var y = bounds.minY
        for subview in subviews {
            subview.place(
                at: CGPoint(x: bounds.minX, y: y),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: bounds.width, height: height)
            )
            y += height + spacing
        }
    }

    private func rowHeight(width: CGFloat, subviews: Subviews) -> CGFloat {
        subviews.map { $0.sizeThatFits(ProposedViewSize(width: width, height: nil)).height }.max() ?? 0
    }
}
