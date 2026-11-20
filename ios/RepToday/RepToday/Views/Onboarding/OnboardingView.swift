import SwiftUI

/// The minimal v6 onboarding flow (US-I01).
///
/// A short, focused, step-by-step flow that collects only what the deterministic engine needs, then
/// hands off to the Ready Screen with the first session already generated. There is no XP, no
/// levels, and no badges anywhere; every color, font, and dimension comes from `Theme`.
///
/// The view owns an `@Observable` `OnboardingViewModel`, built from the injected `ServiceContainer`
/// so the final save/seed goes through the real services. The flow ends at "Save your plan" (M3,
/// US-AU02): `onComplete` is called with the signed-in account once its plan is on the phone - brought
/// back from the account, or created from these answers - so the router can link the account and flip
/// `AppState` to the main app.
struct OnboardingView: View {
    @State private var viewModel: OnboardingViewModel
    @State private var signIn: AccountSignInViewModel
    /// Hands the signed-in account to the router once there is a plan on the phone.
    private let onComplete: (AccountIdentity) throws -> Void

    init(services: ServiceContainer, onComplete: @escaping (AccountIdentity) throws -> Void) {
        self.init(
            viewModel: OnboardingViewModel(
                userService: services.userService,
                sessionPolicyService: services.sessionPolicyService,
                accountRestorer: services.syncEngine,
                analytics: services.analyticsService
            ),
            accountAuth: services.accountAuthService,
            onComplete: onComplete
        )
    }

    /// Opens the flow on an already-built view model, so a caller can render a step other than the
    /// first. Previews and tests use it to reach a mid-flow step through the production view rather
    /// than by reimplementing it.
    init(
        viewModel: OnboardingViewModel,
        accountAuth: any AccountAuthServiceProtocol = StubAccountAuthService(),
        onComplete: @escaping (AccountIdentity) throws -> Void = { _ in }
    ) {
        _viewModel = State(initialValue: viewModel)
        self.onComplete = onComplete
        _signIn = State(initialValue: AccountSignInViewModel(auth: accountAuth, context: .onboarding) { identity in
            // An account with no plan, signed in to from the Welcome step, answers the questions first
            // and finishes from the last of them.
            guard try await viewModel.completeSignIn(as: identity) != .needsAnswers else { return }
            try onComplete(identity)
        })
    }

    var body: some View {
        ZStack {
            Theme.Colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                progressBar
                    .padding(.top, Theme.Spacing.sm)
                    .padding(.bottom, Theme.Spacing.mlg)

                // The step fills at least the screen's height, so a step can push its last lines (the
                // Welcome step's disclosure) down to the bottom and still scroll when the text is large.
                GeometryReader { viewport in
                    ScrollView {
                        stepContent
                            .padding(.horizontal, Theme.Spacing.screenMargin)
                            // The story screens sit their overline 2 pt nearer the pager, as the mockups do.
                            .padding(.top, viewModel.step.isStory ? 10 : Theme.Spacing.smd)
                            .padding(.bottom, Theme.Spacing.mlg)
                            .frame(maxWidth: .infinity, minHeight: viewport.size.height, alignment: .topLeading)
                    }
                    .scrollDismissesKeyboard(.interactively)
                }

                // The sign-in panel explains its own outcome on the last step.
                if let errorMessage = viewModel.errorMessage, viewModel.step != .saveYourPlan {
                    Text(errorMessage)
                        .font(Theme.Typography.footnote)
                        .foregroundStyle(Theme.Colors.danger)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, Theme.Spacing.screenMargin)
                        .padding(.bottom, Theme.Spacing.sm)
                }

                VStack(spacing: 10) {
                    if viewModel.offersSignInFromWelcome && !dynamicTypeSize.isAccessibilitySize {
                        WelcomeSignInLink(viewModel: viewModel, alignment: .center)
                    }
                    navigationControls
                }
                .padding(.horizontal, Theme.Spacing.screenMargin)
                .padding(.top, 10)
                .padding(.bottom, Theme.Spacing.sm)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: viewModel.step)
        .onAppear {
            // US-T08: `onboarding_started` fires on the first onboarding screen's appearance. The view
            // model guards it to one emission per flow, so a re-`onAppear` does not double-fire; the
            // sink enforces consent, so an opted-out install produces no durable/network work.
            viewModel.onboardingStarted()
        }
    }

    // MARK: - Progress

    /// One 6 pt segment per step of the bar on screen - the four story screens, or the questions - filled
    /// `sun` up to and including this one, on `surface3`.
    private var progressBar: some View {
        HStack(spacing: 5) {
            ForEach(Array(viewModel.progressSteps.enumerated()), id: \.element) { index, _ in
                Capsule()
                    .fill(index < viewModel.progressPosition
                          ? Theme.Colors.sun
                          : Theme.Colors.surface3)
                    .frame(height: 6)
            }
        }
        .padding(.horizontal, Theme.Spacing.screenMargin)
        .accessibilityElement()
        .accessibilityLabel("Step \(viewModel.progressPosition) of \(viewModel.progressSteps.count)")
    }

    // MARK: - Step content

    @ViewBuilder
    private var stepContent: some View {
        switch viewModel.step {
        case .welcome:         WelcomeStep(viewModel: viewModel)
        case .storyWho:        StoryWhoStep()
        case .storyHow:        StoryHowStep()
        case .storyDiscipline: StoryDisciplineStep()
        case .basics:          BasicsStep(viewModel: viewModel)
        case .fitnessLevel:    FitnessLevelStep(viewModel: viewModel)
        case .focusAreas:      FocusAreasStep(viewModel: viewModel)
        case .why:             WhyStep(viewModel: viewModel)
        case .lifestyle:       LifestyleStep(viewModel: viewModel)
        case .duration:        DurationStep(viewModel: viewModel)
        case .saveYourPlan:    SaveYourPlanStep(signIn: signIn)
        }
    }

    // MARK: - Navigation controls

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Back and the primary action side by side, or stacked (primary first) at the accessibility text
    /// sizes, where two half-width buttons would truncate their titles.
    private var navigationControls: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 10))
            : AnyLayout(HStackLayout(spacing: 10))
        return layout {
            if viewModel.step == .saveYourPlan {
                // Signing in is the only way forward from here, so Back stands alone.
                backButton
            } else if dynamicTypeSize.isAccessibilitySize {
                primaryButton
                backButton
            } else {
                backButton
                primaryButton
            }
        }
    }

    @ViewBuilder
    private var backButton: some View {
        if !viewModel.isFirstStep {
            // Its own width beside the primary action; the full width when it stands alone (Save your
            // plan) or stacks under it at the accessibility text sizes.
            let fills = viewModel.step == .saveYourPlan || dynamicTypeSize.isAccessibilitySize
            // Back keeps the question screens' size on the story screens too, beside their taller Continue.
            Button(action: viewModel.goBack) {
                Text("Back")
                    .font(Theme.Typography.button)
                    .padding(.horizontal, Theme.Spacing.sm)
                    .frame(maxWidth: fills ? .infinity : nil)
                    .frame(minHeight: Theme.Spacing.buttonHeight)
            }
            .secondaryButtonStyle()
            .disabled(isBusy)
        }
    }

    private var primaryButton: some View {
        Button(action: primaryAction) {
            ZStack {
                if viewModel.isFinishing {
                    ProgressView().tint(Theme.Colors.onAccent)
                } else {
                    Text(viewModel.primaryActionTitle)
                        .font(viewModel.step.isStory ? Theme.Typography.storyButton : Theme.Typography.button)
                }
            }
            .frame(maxWidth: .infinity)
            // The story screens' primary action stands taller (60 pt, Inter Bold 19), as their mockups set it.
            .frame(minHeight: viewModel.step.isStory ? Theme.Spacing.startButtonHeight : Theme.Spacing.buttonHeight)
        }
        .accentFilledButtonStyle()
        .disabled(!viewModel.canAdvance || viewModel.isFinishing)
    }

    /// Saving or signing in: the flow holds still until it ends.
    private var isBusy: Bool { viewModel.isFinishing || signIn.isWorking }

    private func primaryAction() {
        guard viewModel.finishesSignedIn, let identity = viewModel.signedInIdentity else {
            viewModel.advance()
            return
        }
        Task {
            guard await viewModel.finish() else { return }
            do {
                try onComplete(identity)
            } catch {
                viewModel.reportFinishingFailed()
            }
        }
    }
}

// MARK: - Step scaffold

/// Shared header (title + subtitle) above each step's inputs, so every step reads consistently: the
/// question in Display M, capped at the accessibility sizes so it wraps rather than overflows, over the
/// subtitle in `text2`.
private struct StepHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .cappedDisplayFont(size: 40)
                .foregroundStyle(Theme.Colors.text1)
                .fixedSize(horizontal: false, vertical: true)
            Text(subtitle)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.text2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Welcome (story 1)

/// The first story screen (`screens/F02-Onboarding-Welcome`): the promise, the session lengths and both
/// Trainers, then the anonymous-usage-data disclosure at the foot of the page. Its "Already have an
/// account? Sign in" sits above Continue (`OnboardingView`), or in the page at the accessibility text
/// sizes, where the footer has no room left for it.
private struct WelcomeStep: View {
    @Bindable var viewModel: OnboardingViewModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            StoryWelcomeVisual()

            if viewModel.offersSignInFromWelcome && dynamicTypeSize.isAccessibilitySize {
                WelcomeSignInLink(viewModel: viewModel, alignment: .leading)
            }

            Spacer(minLength: 0)

            // The anonymous-usage-data disclosure (US-T06). It sits on the *first* screen rather
            // than the last because the first event the app emits hangs off app entry (US-T07's
            // `app_install`), so a disclosure shown at the end of onboarding would come after the
            // thing it discloses. It says where the off switch is, which is what makes an opt-out
            // model honest rather than merely legal.
            telemetryDisclosure
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    /// The disclosure with its "Privacy Policy" link set inline at the end, as the mockup draws it. To
    /// VoiceOver it stays two elements - the sentence, then a link - so the link is found on its own.
    private var telemetryDisclosure: some View {
        (Text(Self.disclosure + " ") + Text(privacyPolicyLink))
            .font(Theme.Typography.disclosure)
            .foregroundStyle(Theme.Colors.text2)
            .tint(Theme.Colors.sun)
            .designLineHeight(17, relativeTo: .caption)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityRepresentation {
                VStack(alignment: .leading) {
                    Text(Self.disclosure)
                    Link("Privacy Policy", destination: LegalLinks.privacyPolicy)
                }
            }
    }

    static let disclosure = "Rep Today collects anonymous usage data to see whether it's working. You can turn that off anytime in Profile, under Settings."

    @Environment(\.legibilityWeight) private var legibilityWeight

    private var privacyPolicyLink: AttributedString {
        var link = AttributedString("Privacy Policy")
        link.link = LegalLinks.privacyPolicy
        link.font = Theme.Typography.disclosure.weight(.bold).font(for: legibilityWeight)
        link.underlineStyle = .single
        return link
    }
}

/// "Already have an account? Sign in" on the first story screen: someone who already has an account -
/// back after signing out, or on a new phone - goes straight to the sign-in instead of answering the
/// questions again.
private struct WelcomeSignInLink: View {
    let viewModel: OnboardingViewModel
    let alignment: TextAlignment

    var body: some View {
        Button(action: viewModel.goToSignIn) {
            (Text("Already have an account? ")
                .foregroundStyle(Theme.Colors.text1)
             + Text("Sign in")
                .foregroundStyle(Theme.Colors.sun)
                .fontWeight(.bold)
                .underline())
                .font(Theme.Typography.callout)
                .multilineTextAlignment(alignment)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: alignment == .center ? .center : .leading)
                // A 44 pt target around a 22 pt line: the target overhangs the line rather than spacing
                // it out, so the link sits where the mockup sets it, 10 pt above Continue.
                .padding(.vertical, Self.targetOverhang)
                .contentShape(Rectangle())
                .padding(.vertical, -Self.targetOverhang)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Self.label)
        .accessibilityHint("Signs in to your account and brings your plan back")
    }

    /// The one label the sign-in link is known by, to VoiceOver and the XCUITests.
    static let label = "Already have an account? Sign in"

    /// How far the touch target reaches past the line above and below.
    private static let targetOverhang: CGFloat = 11
}

// MARK: - Basics

private struct BasicsStep: View {
    @Bindable var viewModel: OnboardingViewModel
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.mlg) {
            StepHeader(title: "The basics", subtitle: "Just enough to tailor your sessions.")

            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                FieldLabel("Your name")
                TextField("First name", text: $viewModel.displayName)
                    .textFieldStyle(.plain)
                    .textInputAutocapitalization(.words)
                    .focused($nameFocused)
                    .themeInputField(isFocused: nameFocused)
            }

            SexPicker(sex: $viewModel.sex)

            VStack(spacing: 0) {

            LabeledStepper(
                label: "Age",
                value: $viewModel.age,
                range: 13...100,
                display: { "\($0) years" },
                spoken: { "\($0) years" }
            )

            // Imperial in, metric stored (US-O04). The two rows step whole inches and whole pounds;
            // `OnboardingViewModel` converts once, in `buildUser`.
            //
            // Height is one row over total inches rather than two controls: it keeps the step's
            // label-value-stepper rhythm, and the split it writes back is always normalized, so
            // "5 ft 12 in" is unreachable by construction.
            //
            // The bounds are the imperial cover of the metric sliders they replace (120...220 cm,
            // 35...200 kg), rounded outward at all four ends: 47 in is 119.4 cm and 87 in is 221.0 cm;
            // 70 lb is 31.8 kg and 445 lb is 201.8 kg. Narrowing them would silently clamp somebody:
            // there is no profile-edit surface yet, so a weight capped on the way in under-reports
            // every HealthKit energy estimate (`MET x weightKg x hours`) for the life of the account.
            LabeledStepper(
                label: "Height",
                value: $viewModel.heightTotalInches,
                range: 47...87,
                display: UnitConversion.heightLabel(totalInches:),
                spoken: UnitConversion.heightAccessibilityLabel(totalInches:)
            )
            // Weight moves in 5lb steps: the range is wide enough that single pounds would be a long
            // walk, and the only thing downstream reads this number for is the HealthKit MET energy
            // estimate, where 5lb is far inside the approximation's own error. Both bounds sit on the
            // step, so the whole range is reachable from either end.
            LabeledStepper(
                label: "Weight",
                value: $viewModel.weightPounds,
                range: 70...445,
                step: 5,
                display: UnitConversion.weightLabel(pounds:),
                spoken: UnitConversion.weightAccessibilityLabel(pounds:)
            )
            }
        }
    }
}

private struct SexPicker: View {
    @Binding var sex: Sex

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            FieldLabel("Sex")
            ThemeSegmentedPicker(label: "Sex", options: Sex.allCases, selection: $sex, title: \.label)
        }
    }
}

/// One measurement row: the name on the left, the current value on the right, and a pair of step
/// buttons that move it by exactly one unit a tap.
///
/// Every measurement this step collects is a whole unit (a year, an inch, a pound), and each is a
/// number the user already knows, so an exact control beats a draggable one - the answer is recalled,
/// not explored. `display` renders the compact on-screen read-out and `spoken` the VoiceOver value,
/// kept apart so the screen can stay terse ("5 ft 8 in") while VoiceOver reads a real sentence
/// ("5 feet 8 inches") instead of spelling out abbreviations.
///
/// The buttons are drawn rather than delegated to `Stepper`, whose halves lay out at 46.5 x 32pt -
/// under the app's 44pt floor in the dimension a thumb is least accurate in. The row is one
/// *adjustable* accessibility element rather than two buttons, which is the idiom VoiceOver already
/// knows for a value control: it reads "Height, 5 feet 8 inches" and swipe up/down moves it.
private struct LabeledStepper: View {
    let label: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    var step: Int = 1
    let display: (Int) -> String
    let spoken: (Int) -> String

    /// At an accessibility type size the name, the value, and the buttons no longer share a line
    /// without the value wrapping mid-row, so the row stacks instead of squeezing.
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.legibilityWeight) private var legibilityWeight

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    name
                    HStack(spacing: Theme.Spacing.sm) {
                        readOut
                        Spacer(minLength: Theme.Spacing.sm)
                        buttons
                    }
                }
            } else {
                HStack(spacing: Theme.Spacing.sm) {
                    name
                    Spacer(minLength: Theme.Spacing.sm)
                    readOut
                        .padding(.trailing, Theme.Spacing.sm)
                    buttons
                }
            }
        }
        .padding(.vertical, Theme.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: Theme.Spacing.rowHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(spoken(value))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: _ = adjust(by: step)
            case .decrement: _ = adjust(by: -step)
            @unknown default: break
            }
        }
    }

    private var name: some View {
        Text(label)
            .font(Theme.Typography.rowName)
            .foregroundStyle(Theme.Colors.text1)
    }

    /// The read-out with its numbers in big Bricolage and its units in small Inter ("35 years",
    /// "5 ft 8 in"), on one baseline.
    private var readOut: some View {
        let number = Theme.Typography.stepperValue.font(for: legibilityWeight).monospacedDigit()
        let unit = Theme.Typography.calloutMedium.font(for: legibilityWeight)
        let words = display(value).split(separator: " ").map(String.init)
        return words.enumerated().reduce(Text("")) { text, item in
            let (index, word) = item
            let isNumber = word.allSatisfy(\.isNumber)
            let piece = Text((index == 0 ? "" : " ") + word)
                .font(isNumber ? number : unit)
                .foregroundStyle(isNumber ? Theme.Colors.text1 : Theme.Colors.text2)
            return text + piece
        }
        .lineLimit(1)
        .fixedSize()
    }

    private var buttons: some View {
        HStack(spacing: Theme.Spacing.sm) {
            StepButton(icon: .minus, isEnabled: value > range.lowerBound) {
                adjust(by: -step)
            }
            StepButton(icon: .plus, isEnabled: value < range.upperBound) {
                adjust(by: step)
            }
        }
    }

    /// Move the value and clamp it to `range`, so neither the buttons nor the VoiceOver adjustment can
    /// walk it out of bounds. Reports whether the value actually moved, which is what tells a held
    /// button it has reached the end of the range and can stop.
    @discardableResult
    private func adjust(by delta: Int) -> Bool {
        let adjusted = min(range.upperBound, max(range.lowerBound, value + delta))
        guard adjusted != value else { return false }
        value = adjusted
        return true
    }
}

/// One half of a `LabeledStepper`: a 44pt-square target that steps on release and repeats while held.
///
/// The repeat is what a hand-drawn stepper otherwise gives up against the platform one, and the
/// ranges here need it - 70...445 lb is a long walk in single taps. Only the *drawing* is hand-rolled,
/// though: this is a real `Button`, so everything about when a press counts is the platform's, touch
/// slop and all. A press belongs to the button it *landed* on for its whole life, and the platform's
/// touch-up-inside decides whether the lift still counts - so on a row where `-` and `+` are adjacent
/// 44pt squares, a finger that lands on `+` and drifts a little over `-` steps `+` and never `-`, and
/// one that travels clear of the slop steps nothing at all. That is how every other button in the app
/// behaves; inheriting the rule rather than restating it here is the point. A press the enclosing
/// `ScrollView` takes over commits nothing either, and the button's highlight is delayed exactly as
/// long as the platform delays every other button's inside a scroll view.
///
/// Deciding that here is what went wrong three times: a radius measured from where the finger landed
/// is not a button's bounds, and two gestures measuring it differently silently dropped the step.
/// There is now one rule, it lives in the layer that owns hit testing, and this view holds no geometry
/// at all.
///
/// That leaves `PressRepeater` the one job the platform has no notion of: a press held past the hold
/// delay repeats, and the release ending it adds nothing on top of what the read-out already showed.
/// It runs off the style's press state - the same signal that tints the glyph - so the repeat and the
/// highlight start and stop together, on release, on cancel, and on disappear.
private struct StepButton: View {
    let icon: AppIcon
    let isEnabled: Bool
    /// Steps the value, reporting whether it actually moved.
    let action: () -> Bool

    @State private var repeater = PressRepeater()

    var body: some View {
        Button {
            repeater.pressReleased(step: action)
        } label: {
            // A fixed 22 pt glyph in its 44 pt circle: the row's text carries the larger sizes; this is
            // chrome, and a glyph that grew would draw past its own background.
            IconView(icon: icon, size: 22)
        }
        .buttonStyle(
            StepButtonStyle { isPressing in
                if isPressing {
                    repeater.pressBegan(step: action)
                } else {
                    repeater.pressEnded()
                }
            }
        )
        .disabled(!isEnabled)
        .onDisappear { repeater.pressEnded() }
        .accessibilityHidden(true)
    }
}

/// A step button's chrome: a 44pt `surface2` circle whose glyph tints while the finger is down.
///
/// The press state is the platform's own - true while the finger is down on the button, false the
/// moment it lifts, drags off, or the enclosing scroll view takes the press over - so one signal
/// drives both the highlight and the repeat, and no press can end somewhere this view never hears
/// about. Nothing else acknowledges a press, since the value only moves on release, and this is the
/// one hand-drawn control on a screen where every other button gets the platform's highlight free.
private struct StepButtonStyle: ButtonStyle {
    /// Fast in, so a tap well under 100ms still shows the highlight it was added to give; slower out,
    /// so the release fades rather than snaps. `Theme` carries no animation tokens, so these are the
    /// one named place for them rather than literals at the call site.
    static let pressInDuration: TimeInterval = 0.1
    static let pressOutDuration: TimeInterval = 0.2

    let onPressingChanged: (Bool) -> Void

    func makeBody(configuration: Configuration) -> some View {
        Chrome(configuration: configuration, onPressingChanged: onPressingChanged)
    }

    /// A view rather than modifiers applied straight to the label, so it can read `isEnabled` and
    /// Reduce Motion from the environment and own the `onChange` that drives the repeat.
    private struct Chrome: View {
        let configuration: Configuration
        let onPressingChanged: (Bool) -> Void

        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            configuration.label
                .foregroundStyle(tint)
                .frame(
                    width: Theme.Spacing.minTouchTarget,
                    height: Theme.Spacing.minTouchTarget
                )
                .background(Theme.Colors.surface2, in: Circle())
                .opacity(isEnabled ? 1 : 0.4)
                .contentShape(Circle())
                .animation(pressAnimation, value: configuration.isPressed)
                .onChange(of: configuration.isPressed) { _, isPressing in
                    onPressingChanged(isPressing)
                }
        }

        private var tint: Color {
            guard isEnabled else { return Theme.Colors.text2 }
            return configuration.isPressed ? Theme.Colors.sun : Theme.Colors.text1
        }

        private var pressAnimation: Animation? {
            guard !reduceMotion else { return nil }
            return .easeOut(
                duration: configuration.isPressed
                    ? StepButtonStyle.pressInDuration
                    : StepButtonStyle.pressOutDuration
            )
        }
    }
}

// MARK: - Fitness level

private struct FitnessLevelStep: View {
    @Bindable var viewModel: OnboardingViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.mlg) {
            StepHeader(
                title: "How active are you?",
                subtitle: "We start you at a gentle, winnable level and let your sessions earn their way up."
            )

            VStack(spacing: 10) {
                ForEach(FitnessLevel.allCases) { level in
                    SelectableCard(
                        title: level.label,
                        subtitle: level.blurb,
                        isSelected: viewModel.fitnessLevel == level
                    ) {
                        viewModel.fitnessLevel = level
                    }
                }
            }
        }
    }
}

// MARK: - Focus Areas (US-HO02)

private struct FocusAreasStep: View {
    @Bindable var viewModel: OnboardingViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.mlg) {
            StepHeader(
                title: FocusAreasCopy.onboardingTitle,
                subtitle: FocusAreasCopy.onboardingSubtitle
            )

            FocusAreaList(selection: $viewModel.selectedFocusAreas)
        }
    }
}

// MARK: - Why

private struct WhyStep: View {
    @Bindable var viewModel: OnboardingViewModel
    @FocusState private var whyFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.mlg) {
            StepHeader(
                title: "What's your why?",
                subtitle: "One line, in your words. It reminds you why you showed up. (Optional.)"
            )

            TextField(
                "e.g. get on the floor with my grandkids",
                text: $viewModel.whyStatement,
                prompt: Text("e.g. get on the floor with my grandkids").foregroundStyle(Theme.Colors.text3),
                axis: .vertical
            )
            .lineLimit(3, reservesSpace: true)
            .focused($whyFocused)
            .font(Theme.Typography.input)
            .foregroundStyle(Theme.Colors.text1)
            .tint(Theme.Colors.sun)
            .padding(18)
            .frame(minHeight: 140, alignment: .topLeading)
            .background(Theme.Colors.surface2, in: RoundedRectangle(cornerRadius: Theme.Spacing.tileCornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Spacing.tileCornerRadius)
                    .strokeBorder(whyFocused ? Theme.Colors.sun : .clear, lineWidth: 2)
            )
        }
    }
}

// MARK: - Lifestyle (sitting + injuries)

private struct LifestyleStep: View {
    @Bindable var viewModel: OnboardingViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.mlg) {
            StepHeader(
                title: "A couple of specifics",
                subtitle: "So we keep every session safe and useful for your day."
            )

            Toggle(isOn: $viewModel.sitsLong) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text("I sit 6+ hours most days")
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Colors.text1)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("We'll lean your warm-ups and cooldowns toward hip and posture stretches.")
                        .font(Theme.Typography.callout)
                        .foregroundStyle(Theme.Colors.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .toggleStyle(ThemeToggleStyle())
            .padding(18)
            .frame(minHeight: Theme.Spacing.rowHeight)
            .cardSurface()

            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("Anything we should work around?")
                    .font(Theme.Typography.cardTitle)
                    .foregroundStyle(Theme.Colors.text1)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Select any areas to protect. (Optional.)")
                    .font(Theme.Typography.callout)
                    .foregroundStyle(Theme.Colors.text2)
                    .fixedSize(horizontal: false, vertical: true)

                ChipFlow(options: InjuryOption.allCases, selection: $viewModel.selectedInjuries)
                    .padding(.top, Theme.Spacing.sm)
            }
        }
    }
}

// MARK: - Duration

private struct DurationStep: View {
    @Bindable var viewModel: OnboardingViewModel

    private let options = DefaultDurationLearning.chipValues

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.mlg) {
            StepHeader(
                title: "How long do you usually have?",
                subtitle: "This is just your starting point - your sessions learn what you actually finish."
            )

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3),
                spacing: 10
            ) {
                ForEach(options, id: \.self) { minutes in
                    DurationChip(
                        minutes: minutes,
                        isSelected: viewModel.durationMinutes == minutes
                    ) {
                        viewModel.durationMinutes = minutes
                    }
                }
            }
        }
    }
}

// MARK: - Save your plan

/// The last onboarding step (M3, US-AU02, decision 23): signing in to a Rep Today account, required to
/// finish. Copy stays discipline-first - what the account keeps, not what could be lost.
private struct SaveYourPlanStep: View {
    let signIn: AccountSignInViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.mlg) {
            StepHeader(
                title: "Save your plan",
                subtitle: "Sign in to keep your plan and every session you finish, on this phone and the next. Rep Today still works offline - it saves to your account whenever you're connected."
            )

            AccountSignInPanel(viewModel: signIn)

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text("Already have an account? Sign in and your plan comes back.")
                    .font(Theme.Typography.fieldLabel.weight(.regular))
                    .foregroundStyle(Theme.Colors.text2)
                    .fixedSize(horizontal: false, vertical: true)
                Link(destination: LegalLinks.privacyPolicy) {
                    InlineLinkLabel(title: "Privacy Policy", font: Theme.Typography.fieldLabel)
                }
                .accessibilityLabel("Privacy Policy")
            }
        }
    }
}

private struct DurationChip: View {
    let minutes: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                Text("\(minutes)")
                    .cappedDisplayFont(Theme.Typography.FontName.displaySmall, size: 40, relativeTo: .title1)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text("min")
                    .font(Theme.Typography.unitLabel)
                    .foregroundStyle(isSelected ? Theme.Colors.onAccent : Theme.Colors.text2)
            }
            .padding(.vertical, Theme.Spacing.sm)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 92)
            .foregroundStyle(isSelected ? Theme.Colors.onAccent : Theme.Colors.text1)
            .animation(.easeOut(duration: 0.12)) {
                $0.background(
                    isSelected ? Theme.Colors.sun : Theme.Colors.surface1,
                    in: RoundedRectangle(cornerRadius: 22)
                )
            }
            .contentShape(RoundedRectangle(cornerRadius: 22))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(minutes) minutes")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

// MARK: - Shared components

/// A tappable option card for single-select choices (fitness level): DESIGN's option card.
private struct SelectableCard: View {
    let title: String
    let subtitle: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            OptionCard(title: title, detail: subtitle, isSelected: isSelected)
                .multilineTextAlignment(.leading)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

/// A wrapping row of multi-select injury chips, filled `sun` when chosen.
private struct ChipFlow: View {
    let options: [InjuryOption]
    @Binding var selection: Set<InjuryOption>

    var body: some View {
        FlowLayout(spacing: Theme.Spacing.sm, lineSpacing: Theme.Spacing.sm) {
            ForEach(options) { option in
                let isSelected = selection.contains(option)
                Button {
                    if isSelected { selection.remove(option) } else { selection.insert(option) }
                } label: {
                    Text(option.label)
                }
                .buttonStyle(ChipButtonStyle(isSelected: isSelected))
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            }
        }
    }
}

// MARK: - Enum display helpers (onboarding-local copy)

private extension Sex {
    var label: String {
        switch self {
        case .male: return "Male"
        case .female: return "Female"
        case .other: return "Other"
        }
    }
}

private extension FitnessLevel {
    var label: String {
        switch self {
        case .beginner: return "Just starting"
        case .intermediate: return "Fairly active"
        case .advanced: return "Very active"
        }
    }

    var blurb: String {
        switch self {
        case .beginner: return "New to this, or coming back after a while."
        case .intermediate: return "I move a few times a week."
        case .advanced: return "Training is already part of my routine."
        }
    }
}

#Preview {
    OnboardingView(services: .mock(), onComplete: { _ in })
}
