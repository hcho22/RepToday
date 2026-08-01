import AuthenticationServices
import SwiftUI

/// The minimal v6 onboarding flow (US-I01).
///
/// A short, focused, step-by-step flow that collects only what the deterministic engine needs, then
/// hands off to the Ready Screen with the first session already generated. There is no XP, no
/// levels, and no badges anywhere; every color, font, and dimension comes from `Theme`.
///
/// The view owns an `@Observable` `OnboardingViewModel`, built from the injected `ServiceContainer`
/// so the final save/seed goes through the real services. `onComplete` is called once the user is
/// saved and the cold-start policy seeded, so the router can flip `AppState` to the main app.
struct OnboardingView: View {
    @State private var viewModel: OnboardingViewModel
    private let onComplete: () -> Void

    init(services: ServiceContainer, onComplete: @escaping () -> Void) {
        self.init(
            viewModel: OnboardingViewModel(
                userService: services.userService,
                sessionPolicyService: services.sessionPolicyService,
                authService: services.authService
            ),
            onComplete: onComplete
        )
    }

    /// Opens the flow on an already-built view model, so a caller can render a step other than the
    /// first. Previews and tests use it to reach a mid-flow step through the production view rather
    /// than by reimplementing it.
    init(viewModel: OnboardingViewModel, onComplete: @escaping () -> Void = {}) {
        _viewModel = State(initialValue: viewModel)
        self.onComplete = onComplete
    }

    var body: some View {
        ZStack {
            Theme.Colors.background.ignoresSafeArea()

            VStack(spacing: Theme.Spacing.lg) {
                progressBar

                ScrollView {
                    stepContent
                        .padding(.horizontal, Theme.Spacing.lg)
                        .padding(.top, Theme.Spacing.sm)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Theme.Spacing.lg)
                }

                navigationControls
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.bottom, Theme.Spacing.md)
            }
            .padding(.top, Theme.Spacing.md)
        }
        .animation(.easeInOut(duration: 0.2), value: viewModel.step)
    }

    // MARK: - Progress

    private var progressBar: some View {
        HStack(spacing: Theme.Spacing.xs) {
            ForEach(OnboardingViewModel.Step.allCases) { step in
                Capsule()
                    .fill(step.rawValue <= viewModel.step.rawValue
                          ? Theme.Colors.accent
                          : Theme.Colors.secondaryBackground)
                    .frame(height: 6)
            }
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .accessibilityElement()
        .accessibilityLabel("Step \(viewModel.step.rawValue + 1) of \(OnboardingViewModel.Step.allCases.count)")
    }

    // MARK: - Step content

    @ViewBuilder
    private var stepContent: some View {
        switch viewModel.step {
        case .welcome:      WelcomeStep(viewModel: viewModel)
        case .basics:       BasicsStep(viewModel: viewModel)
        case .fitnessLevel: FitnessLevelStep(viewModel: viewModel)
        case .why:          WhyStep(viewModel: viewModel)
        case .lifestyle:    LifestyleStep(viewModel: viewModel)
        case .duration:     DurationStep(viewModel: viewModel)
        }
    }

    // MARK: - Navigation controls

    private var navigationControls: some View {
        HStack(spacing: Theme.Spacing.md) {
            if !viewModel.isFirstStep {
                Button(action: viewModel.goBack) {
                    Text("Back")
                        .font(Theme.Typography.button)
                        .frame(maxWidth: .infinity)
                        .frame(height: Theme.Spacing.buttonHeight)
                }
                .buttonStyle(.bordered)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Spacing.cardCornerRadius))
                .disabled(viewModel.isFinishing)
            }

            Button(action: primaryAction) {
                ZStack {
                    if viewModel.isFinishing {
                        ProgressView().tint(Theme.Colors.onAccent)
                    } else {
                        Text(primaryTitle)
                            .font(Theme.Typography.button)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: Theme.Spacing.buttonHeight)
            }
            .buttonStyle(.borderedProminent)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Spacing.cardCornerRadius))
            .disabled(!viewModel.canAdvance || viewModel.isFinishing)
        }
    }

    private var primaryTitle: String {
        viewModel.isLastStep ? "Start moving" : "Continue"
    }

    private func primaryAction() {
        if viewModel.isLastStep {
            Task {
                if await viewModel.finish() {
                    onComplete()
                }
            }
        } else {
            viewModel.advance()
        }
    }
}

// MARK: - Step scaffold

/// Shared header (title + subtitle) above each step's inputs, so every step reads consistently.
private struct StepHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(title)
                .font(Theme.Typography.largeTitle)
                .foregroundStyle(Theme.Colors.textPrimary)
            Text(subtitle)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Welcome

private struct WelcomeStep: View {
    @Bindable var viewModel: OnboardingViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            Image(systemName: "figure.run")
                .font(.system(size: 56, weight: .bold))
                .foregroundStyle(Theme.Colors.accent)
                .padding(.top, Theme.Spacing.xl)

            StepHeader(
                title: "Welcome to Rep Today",
                subtitle: "A few minutes is enough. Tell us a little about you and we'll have a session ready before you know it."
            )

            // Sign in with Apple is optional and never gates the first session (US-N01). When the
            // user signs in, the record is keyed by their stable Apple identifier; if they skip it
            // (or it fails offline), onboarding falls back to a local identifier and moves on.
            signInSection
        }
    }

    @ViewBuilder
    private var signInSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            if viewModel.signedInIdentifier != nil {
                Label("Signed in with Apple", systemImage: "checkmark.seal.fill")
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.accent)
                    .frame(minHeight: Theme.Spacing.minTouchTarget)
                    .accessibilityLabel("Signed in with Apple")
            } else if viewModel.canSignInWithApple {
                SignInWithAppleButton(.signIn) { request in
                    request.requestedScopes = [.fullName, .email]
                } onCompletion: { result in
                    viewModel.handleAppleSignIn(result)
                }
                .signInWithAppleButtonStyle(.black)
                .frame(maxWidth: .infinity)
                .frame(height: Theme.Spacing.buttonHeight)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Spacing.cardCornerRadius))
                .disabled(viewModel.isSigningIn)
                .accessibilityHint("Optional. You can start moving without signing in.")

                Text("Optional - keeps your identity private. You can start without it.")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
        .padding(.top, Theme.Spacing.sm)
    }
}

// MARK: - Basics

private struct BasicsStep: View {
    @Bindable var viewModel: OnboardingViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            StepHeader(title: "The basics", subtitle: "Just enough to tailor your sessions.")

            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("Your name")
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                TextField("First name", text: $viewModel.displayName)
                    .textFieldStyle(.plain)
                    .padding(Theme.Spacing.md)
                    .frame(minHeight: Theme.Spacing.minTouchTarget)
                    .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Spacing.cardCornerRadius))
                    .textInputAutocapitalization(.words)
            }

            SexPicker(sex: $viewModel.sex)

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

private struct SexPicker: View {
    @Binding var sex: Sex

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Sex")
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.textPrimary)
            Picker("Sex", selection: $sex) {
                ForEach(Sex.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
            .pickerStyle(.segmented)
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
                    buttons
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: Theme.Spacing.minTouchTarget)
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
            .font(Theme.Typography.headline)
            .foregroundStyle(Theme.Colors.textPrimary)
    }

    private var readOut: some View {
        Text(display(value))
            .font(Theme.Typography.body)
            .foregroundStyle(Theme.Colors.textSecondary)
    }

    private var buttons: some View {
        HStack(spacing: 0) {
            StepButton(systemName: "minus", isEnabled: value > range.lowerBound) {
                adjust(by: -step)
            }
            Divider().frame(height: Theme.Spacing.lg)
            StepButton(systemName: "plus", isEnabled: value < range.upperBound) {
                adjust(by: step)
            }
        }
        .background(
            Theme.Colors.surface,
            in: RoundedRectangle(cornerRadius: Theme.Spacing.cardCornerRadius)
        )
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
    let systemName: String
    let isEnabled: Bool
    /// Steps the value, reporting whether it actually moved.
    let action: () -> Bool

    @State private var repeater = PressRepeater()

    var body: some View {
        Button {
            repeater.pressReleased(step: action)
        } label: {
            Image(systemName: systemName)
                .font(Theme.Typography.headline)
                // The glyph scales with Dynamic Type like everything else, but only up to the point
                // where it still fits its 44pt target - past that it drew straight through the
                // button's own background. The row's text carries the larger sizes; this is chrome.
                .dynamicTypeSize(...DynamicTypeSize.xxLarge)
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

/// A step button's chrome: a 44pt square whose glyph tints while the finger is down.
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
                .contentShape(Rectangle())
                .animation(pressAnimation, value: configuration.isPressed)
                .onChange(of: configuration.isPressed) { _, isPressing in
                    onPressingChanged(isPressing)
                }
        }

        private var tint: Color {
            guard isEnabled else { return Theme.Colors.textSecondary }
            return configuration.isPressed ? Theme.Colors.accent : Theme.Colors.textPrimary
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
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            StepHeader(
                title: "How active are you?",
                subtitle: "We start you at a gentle, winnable level and let your sessions earn their way up."
            )

            VStack(spacing: Theme.Spacing.md) {
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

// MARK: - Why

private struct WhyStep: View {
    @Bindable var viewModel: OnboardingViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            StepHeader(
                title: "What's your why?",
                subtitle: "One line, in your words. It reminds you why you showed up. (Optional.)"
            )

            TextField(
                "e.g. get on the floor with my grandkids",
                text: $viewModel.whyStatement,
                axis: .vertical
            )
            .lineLimit(3, reservesSpace: true)
            .padding(Theme.Spacing.md)
            .frame(minHeight: Theme.Spacing.minTouchTarget)
            .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Spacing.cardCornerRadius))
        }
    }
}

// MARK: - Lifestyle (sitting + injuries)

private struct LifestyleStep: View {
    @Bindable var viewModel: OnboardingViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            StepHeader(
                title: "A couple of specifics",
                subtitle: "So we keep every session safe and useful for your day."
            )

            Toggle(isOn: $viewModel.sitsLong) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text("I sit 6+ hours most days")
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text("We'll lean your shorter sessions toward mobility.")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
            .tint(Theme.Colors.accent)
            .frame(minHeight: Theme.Spacing.minTouchTarget)

            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("Anything we should work around?")
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text("Select any areas to protect. (Optional.)")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)

                ChipFlow(options: InjuryOption.allCases, selection: $viewModel.selectedInjuries)
            }
        }
    }
}

// MARK: - Duration

private struct DurationStep: View {
    @Bindable var viewModel: OnboardingViewModel

    private let options = DefaultDurationLearning.chipValues

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            StepHeader(
                title: "How long do you usually have?",
                subtitle: "This is just your starting point - your sessions learn what you actually finish."
            )

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 88), spacing: Theme.Spacing.md)],
                spacing: Theme.Spacing.md
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

private struct DurationChip: View {
    let minutes: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: Theme.Spacing.xs) {
                Text("\(minutes)")
                    .font(Theme.Typography.title)
                Text("min")
                    .font(Theme.Typography.caption)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 72)
            .foregroundStyle(isSelected ? Theme.Colors.onAccent : Theme.Colors.textPrimary)
            .background(
                isSelected ? Theme.Colors.accent : Theme.Colors.surface,
                in: RoundedRectangle(cornerRadius: Theme.Spacing.cardCornerRadius)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(minutes) minutes")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

// MARK: - Shared components

/// A tappable card used for single-select choices (fitness level), styled per `Theme`.
private struct SelectableCard: View {
    let title: String
    let subtitle: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: Theme.Spacing.md) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text(title)
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text(subtitle)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Theme.Colors.accent : Theme.Colors.textSecondary)
            }
            .padding(Theme.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Spacing.cardCornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Spacing.cardCornerRadius)
                    .stroke(isSelected ? Theme.Colors.accent : .clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

/// A wrapping row of multi-select injury chips.
private struct ChipFlow: View {
    let options: [InjuryOption]
    @Binding var selection: Set<InjuryOption>

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 100), spacing: Theme.Spacing.sm)],
            alignment: .leading,
            spacing: Theme.Spacing.sm
        ) {
            ForEach(options) { option in
                let isSelected = selection.contains(option)
                Button {
                    if isSelected { selection.remove(option) } else { selection.insert(option) }
                } label: {
                    Text(option.label)
                        .font(Theme.Typography.body)
                        .foregroundStyle(isSelected ? Theme.Colors.onAccent : Theme.Colors.textPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: Theme.Spacing.minTouchTarget)
                        .background(
                            isSelected ? Theme.Colors.accent : Theme.Colors.surface,
                            in: Capsule()
                        )
                }
                .buttonStyle(.plain)
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
    OnboardingView(services: .mock(), onComplete: {})
}
