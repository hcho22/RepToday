import SwiftUI

struct ProfileEditView: View {
    @Binding var profile: UserProfile
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var heightFeet: Int = 5
    @State private var heightInches: Int = 7
    @State private var weightLbs: Double = 155

    private var isValid: Bool {
        !profile.displayName.trimmingCharacters(in: .whitespaces).isEmpty
            && profile.age >= 13 && profile.age <= 99
    }

    var body: some View {
        Form {
            // Name
            Section("Name") {
                TextField("Your name", text: $profile.displayName)
                    .font(AppTypography.body)
            }

            // Age & Sex
            Section("Personal Info") {
                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    Text("Age: \(profile.age)")
                        .font(AppTypography.headline)
                    Slider(
                        value: Binding(
                            get: { Double(profile.age) },
                            set: { profile.age = Int($0) }
                        ),
                        in: 13...99, step: 1
                    )
                    .tint(AppColors.brand)
                }

                Picker("Sex", selection: $profile.sex) {
                    ForEach(UserProfile.Sex.allCases) { sex in
                        Text(sex.displayName).tag(sex)
                    }
                }
            }

            // Unit toggle + Height & Weight
            Section("Body Measurements") {
                Picker("Units", selection: $profile.unitSystem) {
                    ForEach(UserProfile.UnitSystem.allCases) { system in
                        Text(system.displayName).tag(system)
                    }
                }
                .pickerStyle(.segmented)

                if profile.unitSystem == .imperial {
                    VStack(alignment: .leading, spacing: AppSpacing.sm) {
                        Text("Height: \(heightFeet)' \(heightInches)\"")
                            .font(AppTypography.headline)
                        HStack {
                            Stepper("Feet: \(heightFeet)", value: $heightFeet, in: 4...7)
                            Stepper("In: \(heightInches)", value: $heightInches, in: 0...11)
                        }
                        .font(AppTypography.subheadline)
                    }
                    .onChange(of: heightFeet) { _, _ in syncHeightToMetric() }
                    .onChange(of: heightInches) { _, _ in syncHeightToMetric() }

                    VStack(alignment: .leading, spacing: AppSpacing.sm) {
                        Text("Weight: \(Int(weightLbs)) lbs")
                            .font(AppTypography.headline)
                        Slider(value: $weightLbs, in: 80...400, step: 1)
                            .tint(AppColors.brand)
                    }
                    .onChange(of: weightLbs) { _, newValue in
                        profile.weightKg = newValue / 2.20462
                    }
                } else {
                    VStack(alignment: .leading, spacing: AppSpacing.sm) {
                        Text("Height: \(Int(profile.heightCm)) cm")
                            .font(AppTypography.headline)
                        Slider(value: $profile.heightCm, in: 120...220, step: 1)
                            .tint(AppColors.brand)
                    }

                    VStack(alignment: .leading, spacing: AppSpacing.sm) {
                        Text("Weight: \(Int(profile.weightKg)) kg")
                            .font(AppTypography.headline)
                        Slider(value: $profile.weightKg, in: 35...180, step: 1)
                            .tint(AppColors.brand)
                    }
                }
            }

            // Fitness Level
            Section("Fitness Level") {
                Picker("Level", selection: $profile.fitnessLevel) {
                    ForEach(FitnessLevel.allCases) { level in
                        Text(level.displayName).tag(level)
                    }
                }
                .pickerStyle(.segmented)
            }

            // Primary Goal
            Section("Primary Goal") {
                Picker("Goal", selection: $profile.primaryGoal) {
                    ForEach(PrimaryGoal.allCases) { goal in
                        Label(goal.displayName, systemImage: goal.icon).tag(goal)
                    }
                }
            }

            // Weekly Goal
            Section("Weekly Workout Goal") {
                Stepper("\(profile.weeklyWorkoutGoal) days per week", value: $profile.weeklyWorkoutGoal, in: 1...7)
            }

            // Injury Notes
            Section("Injuries & Notes") {
                TextEditor(text: $profile.injuries)
                    .frame(minHeight: 80)
                    .font(AppTypography.body)
            }
        }
        .navigationTitle("Edit Profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    profile.updatedAt = Date()
                    onSave()
                    dismiss()
                }
                .disabled(!isValid)
            }
        }
        .onAppear {
            // Initialize imperial values from metric
            let totalInches = profile.heightCm / 2.54
            heightFeet = Int(totalInches) / 12
            heightInches = Int(totalInches) % 12
            weightLbs = profile.weightKg * 2.20462
        }
    }

    private func syncHeightToMetric() {
        profile.heightCm = Double(heightFeet * 12 + heightInches) * 2.54
    }
}
