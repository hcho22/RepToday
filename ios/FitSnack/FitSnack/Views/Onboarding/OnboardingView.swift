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
        _viewModel = State(
            initialValue: OnboardingViewModel(
                userService: services.userService,
                sessionPolicyService: services.sessionPolicyService
            )
        )
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
        case .welcome:      WelcomeStep()
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
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            Image(systemName: "figure.run")
                .font(.system(size: 56, weight: .bold))
                .foregroundStyle(Theme.Colors.accent)
                .padding(.top, Theme.Spacing.xl)

            StepHeader(
                title: "Welcome to FitSnack",
                subtitle: "A few minutes is enough. Tell us a little about you and we'll have a session ready before you know it."
            )
        }
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

            LabeledStepper(label: "Age", value: $viewModel.age, range: 13...100, unit: "years")

            LabeledSlider(label: "Height", value: $viewModel.heightCm, range: 120...220, step: 1, unit: "cm")
            LabeledSlider(label: "Weight", value: $viewModel.weightKg, range: 35...200, step: 1, unit: "kg")
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

private struct LabeledStepper: View {
    let label: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let unit: String

    var body: some View {
        Stepper(value: $value, in: range) {
            HStack {
                Text(label)
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Spacer()
                Text("\(value) \(unit)")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
        .frame(minHeight: Theme.Spacing.minTouchTarget)
    }
}

private struct LabeledSlider: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack {
                Text(label)
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Spacer()
                Text("\(Int(value)) \(unit)")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            Slider(value: $value, in: range, step: step)
                .accessibilityValue("\(Int(value)) \(unit)")
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
