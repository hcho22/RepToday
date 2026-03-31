import SwiftUI

struct ProfileSetupView: View {
    @Bindable var viewModel: OnboardingViewModel
    @State private var heightFeet = 5
    @State private var heightInches = 7
    @State private var weightLbs: Double = 155

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.lg) {
                Text("Tell us about yourself")
                    .font(AppTypography.title)
                    .foregroundStyle(AppColors.textPrimary)

                Text("This helps us personalize your workouts")
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textSecondary)

                // Name
                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    Text("Name")
                        .font(AppTypography.headline)
                    TextField("Your name", text: $viewModel.displayName)
                        .textFieldStyle(.roundedBorder)
                        .font(AppTypography.body)
                }

                // Age
                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    Text("Age: \(viewModel.age)")
                        .font(AppTypography.headline)
                    Slider(value: Binding(
                        get: { Double(viewModel.age) },
                        set: { viewModel.age = Int($0) }
                    ), in: 13...99, step: 1)
                    .tint(AppColors.brand)
                }

                // Sex
                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    Text("Sex")
                        .font(AppTypography.headline)
                    HStack(spacing: AppSpacing.sm) {
                        ForEach(UserProfile.Sex.allCases) { sex in
                            SelectableChip(
                                title: sex.displayName,
                                isSelected: viewModel.sex == sex
                            ) {
                                viewModel.sex = sex
                            }
                        }
                    }
                }

                // Unit toggle
                Picker("Units", selection: $viewModel.unitSystem) {
                    ForEach(UserProfile.UnitSystem.allCases) { system in
                        Text(system.displayName).tag(system)
                    }
                }
                .pickerStyle(.segmented)

                // Height
                if viewModel.unitSystem == .imperial {
                    VStack(alignment: .leading, spacing: AppSpacing.sm) {
                        Text("Height: \(heightFeet)' \(heightInches)\"")
                            .font(AppTypography.headline)
                        HStack {
                            Stepper("Feet: \(heightFeet)", value: $heightFeet, in: 4...7)
                            Stepper("Inches: \(heightInches)", value: $heightInches, in: 0...11)
                        }
                        .font(AppTypography.subheadline)
                    }
                    .onChange(of: heightFeet) { _, _ in viewModel.setHeightImperial(feet: heightFeet, inches: heightInches) }
                    .onChange(of: heightInches) { _, _ in viewModel.setHeightImperial(feet: heightFeet, inches: heightInches) }
                } else {
                    VStack(alignment: .leading, spacing: AppSpacing.sm) {
                        Text("Height: \(Int(viewModel.heightCm)) cm")
                            .font(AppTypography.headline)
                        Slider(value: $viewModel.heightCm, in: 120...220, step: 1)
                            .tint(AppColors.brand)
                    }
                }

                // Weight
                if viewModel.unitSystem == .imperial {
                    VStack(alignment: .leading, spacing: AppSpacing.sm) {
                        Text("Weight: \(Int(weightLbs)) lbs")
                            .font(AppTypography.headline)
                        Slider(value: $weightLbs, in: 80...400, step: 1)
                            .tint(AppColors.brand)
                    }
                    .onChange(of: weightLbs) { _, newValue in viewModel.setWeightImperial(lbs: newValue) }
                } else {
                    VStack(alignment: .leading, spacing: AppSpacing.sm) {
                        Text("Weight: \(Int(viewModel.weightKg)) kg")
                            .font(AppTypography.headline)
                        Slider(value: $viewModel.weightKg, in: 35...180, step: 1)
                            .tint(AppColors.brand)
                    }
                }

                PrimaryButton(title: "Continue", isEnabled: viewModel.canAdvance) {
                    viewModel.next()
                }
            }
            .padding(AppSpacing.lg)
        }
    }
}
