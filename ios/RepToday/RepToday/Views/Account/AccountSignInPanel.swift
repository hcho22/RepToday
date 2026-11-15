import AuthenticationServices
import SwiftUI

/// The account sign-in controls (M3, decision 23): Apple, Google and an email code, then the
/// signed-in confirmation. Shared by onboarding's "Save your plan" step and the existing-user sign-in
/// screen, which each supply their own heading.
///
/// Every color, font and dimension comes from `Theme`; controls are full-width, at least 56pt tall, and
/// grow with Dynamic Type instead of truncating. Continue with Apple is the system
/// `ASAuthorizationAppleIDButton` in its white style (DESIGN "Icons and marks"), fully round, which
/// draws its own title at a fixed size; Continue with Google is Google's dark-theme button with its
/// official "G" (`GoogleSignInButton`); email is a `surface2` button. The last two titles wrap.
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
                Text(message)
                    .font(Theme.Typography.callout)
                    .foregroundStyle(Theme.Colors.text1)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(Theme.Spacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.Colors.surface2, in: RoundedRectangle(cornerRadius: Theme.Spacing.inputCornerRadius))
                    .accessibilityElement(children: .combine)
            }

            #if DEBUG
            if !viewModel.isConfigured {
                Text("Development build: sign-in is simulated and nothing leaves this phone. On the email code screen, use \(StubAccountAuthService.acceptedCode).")
                    .font(Theme.Typography.footnote)
                    .foregroundStyle(Theme.Colors.text2)
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

    /// The three choices share one height at every text size, so none looks bigger than another: Apple's
    /// button, whose title stays its system size, takes the height the wrapped titles beside it need.
    private var choices: some View {
        EqualHeightColumn(spacing: 10) {
            AppleSignInButton(working: viewModel.activity == .apple) {
                Task { await viewModel.signInWithApple() }
            }
            .disabled(viewModel.isWorking)
            .opacity(viewModel.isWorking && viewModel.activity != .apple ? 0.4 : 1)
            .accessibilityLabel("Continue with Apple")
            .accessibilityHint("Signs in with your Apple Account")

            GoogleSignInButton(working: viewModel.activity == .google) {
                Task { await viewModel.signInWithGoogle() }
            }
            .disabled(viewModel.isWorking)
            .accessibilityLabel("Continue with Google")
            .accessibilityHint("Opens Google sign-in")

            choiceButton("Continue with email", icon: .mail, working: false) {
                viewModel.chooseEmail()
                focusedField = .email
            }
            .accessibilityHint("Sends a one-time code to your email")
        }
    }

    // MARK: - Email

    private var emailEntry: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            FieldLabel("Your email")
            inputField(isFocused: focusedField == .email) {
                TextField("you@example.com", text: $viewModel.email, prompt: Text(verbatim: "you@example.com").foregroundStyle(Theme.Colors.text3))
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
                .foregroundStyle(Theme.Colors.text2)
                .fixedSize(horizontal: false, vertical: true)
            CodeBoxes(code: viewModel.code, isFocused: focusedField == .code) {
                TextField("Code", text: $viewModel.code)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .focused($focusedField, equals: .code)
                    .accessibilityLabel("Code from your email")
            }
            .padding(.vertical, Theme.Spacing.xs)
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
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
                // Success is `legs`, always with the check glyph.
                ScaledIcon(icon: .check, size: 22, relativeTo: .headline)
                    .foregroundStyle(Theme.Colors.legs)
                    .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 6 }
                Text(Self.signedInText(identity))
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.text1)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)

            if viewModel.activity == .finishing {
                HStack(spacing: Theme.Spacing.sm) {
                    ProgressView()
                        .tint(Theme.Colors.sun)
                    Text("Saving your plan")
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.text2)
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
                .font(Theme.Typography.cardTitle)
                .foregroundStyle(Theme.Colors.text1)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(Self.anotherAccountText(attempted, canErase: viewModel.canEraseThisDevice))
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.text2)
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
                                .tint(Theme.Colors.danger)
                        } else {
                            ScaledIcon(icon: .trash, size: 20, relativeTo: .body)
                        }
                        Text("Erase this phone's Rep Today data")
                            .font(Theme.Typography.body.weight(.semibold))
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
        .disabled(!enabled || viewModel.isWorking)
        .accessibilityLabel(title)
    }

    /// The email choice: a `surface2` capsule with a white label and an optional icon, filling the height
    /// its column gives it so it always matches the other choices.
    private func choiceButton(
        _ title: String,
        icon: AppIcon? = nil,
        working: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.sm) {
                if working {
                    ProgressView().tint(Theme.Colors.text1)
                } else if let icon {
                    ScaledIcon(icon: icon, size: 22, relativeTo: .headline)
                }
                Text(title)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(Theme.Typography.button)
            .padding(.vertical, Theme.Spacing.sm)
            .frame(maxWidth: .infinity, minHeight: Theme.Spacing.buttonHeight, maxHeight: .infinity)
        }
        .secondaryButtonStyle()
        .disabled(viewModel.isWorking)
        .accessibilityLabel(title)
    }

    private func textButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            InlineLinkLabel(title: title, font: Theme.Typography.callout)
                .multilineTextAlignment(.leading)
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isWorking)
    }

    private func inputField<Content: View>(isFocused: Bool, @ViewBuilder _ content: () -> Content) -> some View {
        content()
            .themeInputField(isFocused: isFocused)
    }
}

// MARK: - Continue with Google

/// Continue with Google as Google's dark-theme button (Sign in with Google branding guidelines,
/// developers.google.com/identity/branding-guidelines): a #131314 fill with a 1 pt #8E918F inside stroke
/// and a #E3E3E3 label, the official full-color "G" at its standard 20 pt with 12 pt after it, fully
/// round. The mark is Google's own artwork (`Assets.xcassets/GoogleG`, see `docs/asset-attribution.md`),
/// never recolored or resized, and sits on the same #131314 it is drawn on in Google's asset. The label
/// keeps the app's button type so the three choices read alike, and it wraps at large text sizes.
private struct GoogleSignInButton: View {
    let working: Bool
    let action: () -> Void

    /// The brand colors the guidelines set for the dark theme. They belong to Google's button, not to the
    /// Theme palette.
    private enum Brand {
        static let fill = Color(hex: 0x131314)
        static let stroke = Color(hex: 0x8E918F)
        static let label = Color(hex: 0xE3E3E3)
    }

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.smd) {
                if working {
                    ProgressView().tint(Brand.label)
                        .frame(width: 20, height: 20)
                } else {
                    Image("GoogleG")
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 20, height: 20)
                        .accessibilityHidden(true)
                }
                Text("Continue with Google")
                    .font(Theme.Typography.button)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(Brand.label)
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            .frame(maxWidth: .infinity, minHeight: Theme.Spacing.buttonHeight, maxHeight: .infinity)
            .background(Brand.fill, in: Capsule())
            .overlay(Capsule().strokeBorder(Brand.stroke, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(GooglePressStyle())
        .opacity(isEnabled ? 1 : 0.4)
    }
}

/// The app's press feedback (92% scale, 80% opacity, still under Reduce Motion) for the Google button,
/// which draws its own brand surface.
private struct GooglePressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .animation(.easeOut(duration: 0.12)) {
                $0.opacity(configuration.isPressed ? 0.8 : 1)
                    .scaleEffect(configuration.isPressed && !reduceMotion ? 0.92 : 1)
            }
    }
}

// MARK: - Continue with Apple

/// Continue with Apple as the system `ASAuthorizationAppleIDButton` in its white style, fully round, at
/// least 56 pt tall. A tap runs the sign-in the view model already owns; the button only draws. While that
/// sign-in works, a spinner covers it.
private struct AppleSignInButton: View {
    let working: Bool
    let action: () -> Void

    var body: some View {
        AppleIDButtonRepresentable(action: action)
            .frame(maxWidth: .infinity, minHeight: Theme.Spacing.buttonHeight, maxHeight: .infinity)
            .overlay {
                if working {
                    ZStack {
                        Capsule().fill(Theme.Colors.signInWithAppleFill)
                        ProgressView().tint(Theme.Colors.signInWithAppleInk)
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { action() }
    }
}

private struct AppleIDButtonRepresentable: UIViewRepresentable {
    let action: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    func makeUIView(context: Context) -> ASAuthorizationAppleIDButton {
        let button = RoundAppleIDButton(authorizationButtonType: .continue, authorizationButtonStyle: .white)
        button.addTarget(context.coordinator, action: #selector(Coordinator.tapped), for: .touchUpInside)
        return button
    }

    func updateUIView(_ button: ASAuthorizationAppleIDButton, context: Context) {
        context.coordinator.action = action
        button.isEnabled = context.environment.isEnabled
    }

    final class Coordinator: NSObject {
        var action: () -> Void

        init(action: @escaping () -> Void) {
            self.action = action
        }

        @objc func tapped() { action() }
    }
}

/// The system button, kept fully round at whatever height it is given.
private final class RoundAppleIDButton: ASAuthorizationAppleIDButton {
    override func layoutSubviews() {
        super.layoutSubviews()
        cornerRadius = bounds.height / 2
    }
}

// MARK: - Email code

/// The email code drawn as one box per digit (`surface2`, radius 16, 64 pt tall, Bricolage digits), the
/// next box to fill outlined in `sun` while the field has focus. The real text field lies over the boxes
/// with its own text and caret cleared, so typing, pasting, AutoFill and VoiceOver all go to it.
private struct CodeBoxes<Field: View>: View {
    let code: String
    let isFocused: Bool
    @ViewBuilder let field: () -> Field

    private static var length: Int { 6 }

    var body: some View {
        let digits = Array(code)
        let count = max(Self.length, digits.count)
        HStack(spacing: Theme.Spacing.sm) {
            ForEach(0..<count, id: \.self) { index in
                Text(index < digits.count ? String(digits[index]) : " ")
                    .font(Theme.Typography.codeDigit)
                    .monospacedDigit()
                    .foregroundStyle(Theme.Colors.text1)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .frame(maxWidth: .infinity, minHeight: 64)
                    .background(Theme.Colors.surface2, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(isFocused && index == min(digits.count, count - 1) ? Theme.Colors.sun : .clear, lineWidth: 2)
                    )
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .accessibilityHidden(true)
        .overlay {
            field()
                .font(Theme.Typography.codeDigit)
                .foregroundStyle(.clear)
                .tint(.clear)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
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
