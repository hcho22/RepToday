import SwiftUI

@Observable
final class OnboardingViewModel {
    var currentStep = 0
    let totalSteps = 8

    // Profile fields
    var displayName = ""
    var age = 30
    var sex: UserProfile.Sex = .male
    var heightCm: Double = 170
    var weightKg: Double = 70
    var fitnessLevel: FitnessLevel = .beginner
    var primaryGoal: PrimaryGoal = .stayActive
    var availableEquipment: Set<Equipment> = [.none]
    var weeklyWorkoutGoal = 3
    var injuries = ""
    var selectedDuration = 15
    var unitSystem: UserProfile.UnitSystem = .imperial

    // Imperial display values
    var heightFeet: Int { Int(heightCm / 30.48) }
    var heightInches: Int { Int((heightCm / 2.54).truncatingRemainder(dividingBy: 12)) }
    var weightLbs: Double { weightKg * 2.20462 }

    var canAdvance: Bool {
        switch currentStep {
        case 0: true
        case 1: !displayName.trimmingCharacters(in: .whitespaces).isEmpty && age >= 13 && age <= 99
        case 2: true
        case 3: true
        case 4: !availableEquipment.isEmpty
        case 5: true
        case 6: true
        case 7: true
        default: false
        }
    }

    func next() {
        guard currentStep < totalSteps - 1 else { return }
        currentStep += 1
        persistStep()
    }

    func back() {
        guard currentStep > 0 else { return }
        currentStep -= 1
        persistStep()
    }

    func toggleEquipment(_ item: Equipment) {
        if item == .none {
            availableEquipment = [.none]
        } else {
            availableEquipment.remove(.none)
            if availableEquipment.contains(item) {
                availableEquipment.remove(item)
            } else {
                availableEquipment.insert(item)
            }
            if availableEquipment.isEmpty {
                availableEquipment = [.none]
            }
        }
    }

    func setHeightImperial(feet: Int, inches: Int) {
        heightCm = Double(feet * 12 + inches) * 2.54
    }

    func setWeightImperial(lbs: Double) {
        weightKg = lbs / 2.20462
    }

    func buildProfile(userId: String) -> UserProfile {
        UserProfile(
            id: userId,
            displayName: displayName,
            age: age,
            sex: sex,
            heightCm: heightCm,
            weightKg: weightKg,
            fitnessLevel: fitnessLevel,
            primaryGoal: primaryGoal,
            injuries: injuries,
            availableEquipment: Array(availableEquipment),
            weeklyWorkoutGoal: weeklyWorkoutGoal,
            typicalAvailableMinutes: selectedDuration,
            unitSystem: unitSystem,
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    func completeOnboarding(services: ServiceContainer?, appState: AppState) async {
        guard let services else { return }
        do {
            let userId = try await services.auth.signIn(displayName: displayName)
            let profile = buildProfile(userId: userId)
            try await services.user.saveProfile(profile)
            appState.isOnboarded = true
        } catch {
            // In dev mode, just proceed
            appState.isOnboarded = true
        }
    }

    private func persistStep() {
        UserDefaults.standard.set(currentStep, forKey: "onboardingStep")
    }

    func restoreStep() {
        currentStep = UserDefaults.standard.integer(forKey: "onboardingStep")
    }
}
