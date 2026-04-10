import SwiftUI

struct SettingsView: View {
    @Binding var profile: UserProfile
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            // Account
            Section("Account") {
                NavigationLink("Edit Profile") {
                    ProfileEditView(profile: $profile, onSave: onSave)
                }
                NavigationLink("Equipment") {
                    EquipmentEditView(equipment: $profile.availableEquipment, onSave: onSave)
                }
            }

            // Workout Preferences
            Section("Workout Preferences") {
                Picker("Fitness Level", selection: $profile.fitnessLevel) {
                    ForEach(FitnessLevel.allCases) { level in
                        Text(level.displayName).tag(level)
                    }
                }
                Picker("Primary Goal", selection: $profile.primaryGoal) {
                    ForEach(PrimaryGoal.allCases) { goal in
                        Text(goal.displayName).tag(goal)
                    }
                }
                Stepper("Weekly Goal: \(profile.weeklyWorkoutGoal) days", value: $profile.weeklyWorkoutGoal, in: 2...7)
                Stepper("Default Duration: \(profile.typicalAvailableMinutes) min", value: $profile.typicalAvailableMinutes, in: 5...30, step: 5)
            }

            // App Preferences
            Section("App Preferences") {
                Picker("Units", selection: $profile.unitSystem) {
                    ForEach(UserProfile.UnitSystem.allCases) { system in
                        Text(system.displayName).tag(system)
                    }
                }
            }

            // Streak Freezes (premium only)
            if profile.streakFreezes > 0 || profile.lastFreezeReplenishDate != nil {
                Section("Streak Freezes") {
                    HStack {
                        Label("Available", systemImage: "snowflake")
                        Spacer()
                        Text("\(profile.streakFreezes)")
                            .foregroundStyle(AppColors.brand)
                            .fontWeight(.semibold)
                    }
                    HStack {
                        Label("Next Replenish", systemImage: "calendar")
                        Spacer()
                        Text(Constants.StreakFreeze.nextReplenishDate().formatted(.dateTime.month(.abbreviated).day()))
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }
            }

            // About
            Section("About") {
                HStack {
                    Text("Version")
                    Spacer()
                    Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                        .foregroundStyle(AppColors.textSecondary)
                }
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: profile.fitnessLevel) { _, _ in onSave() }
        .onChange(of: profile.primaryGoal) { _, _ in onSave() }
        .onChange(of: profile.weeklyWorkoutGoal) { _, _ in onSave() }
        .onChange(of: profile.typicalAvailableMinutes) { _, _ in onSave() }
        .onChange(of: profile.unitSystem) { _, _ in onSave() }
    }
}
