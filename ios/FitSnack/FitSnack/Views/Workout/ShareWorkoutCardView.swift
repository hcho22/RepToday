import SwiftUI

struct ShareWorkoutCardView: View {
    let workout: Workout
    let stats: GamificationStats
    let showWatermark: Bool

    private var duration: Int {
        workout.actualDurationMinutes ?? workout.requestedDurationMinutes
    }

    private var exerciseCount: Int {
        workout.allExercises.count
    }

    private var calories: Int {
        workout.actualCalories ?? workout.estimatedCalories ?? duration * 5
    }

    private var muscleNames: [String] {
        Array(Set(workout.allExercises.flatMap { $0.exercise.muscleGroups.primary.map(\.displayName) })).sorted()
    }

    var body: some View {
        ZStack {
            // Gradient background
            LinearGradient(
                colors: [
                    Color(red: 0.310, green: 0.275, blue: 0.898),
                    Color(red: 0.216, green: 0.188, blue: 0.639),
                    Color(red: 0.122, green: 0.161, blue: 0.416)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(spacing: 40) {
                Spacer()

                // Branding
                VStack(spacing: 8) {
                    Image(systemName: "bolt.heart.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.white.opacity(0.9))
                    Text("FitSnack")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }

                // Completion badge
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(.white)
                    Text("Workout Complete!")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }

                // Stats grid
                HStack(spacing: 24) {
                    cardStat(value: "\(duration)", label: "Minutes", icon: "clock.fill")
                    cardStat(value: "\(exerciseCount)", label: "Exercises", icon: "figure.strengthtraining.traditional")
                    cardStat(value: "\(calories)", label: "Calories", icon: "flame.fill")
                }
                .padding(.horizontal, 32)

                // Muscle groups
                if !muscleNames.isEmpty {
                    VStack(spacing: 12) {
                        Text("Muscles Worked")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.7))

                        Text(muscleNames.joined(separator: " \u{2022} "))
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                }

                // Streak and XP row
                HStack(spacing: 32) {
                    if stats.currentWeeklyStreak > 0 {
                        HStack(spacing: 8) {
                            Image(systemName: "flame.fill")
                                .foregroundStyle(Color(red: 0.984, green: 0.573, blue: 0.235))
                            Text("\(stats.currentWeeklyStreak) week streak")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                    }

                    if workout.xpEarned > 0 {
                        HStack(spacing: 8) {
                            Image(systemName: "star.fill")
                                .foregroundStyle(Color(red: 0.984, green: 0.749, blue: 0.141))
                            Text("+\(workout.xpEarned) XP")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                    }
                }

                Spacer()

                // Watermark for free users
                if showWatermark {
                    Text("Made with FitSnack")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                        .padding(.bottom, 24)
                } else {
                    Spacer()
                        .frame(height: 24)
                }
            }
            .padding(32)
        }
        .frame(width: 1080, height: 1080)
    }

    private func cardStat(value: String, label: String, icon: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundStyle(.white.opacity(0.8))
            Text(value)
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text(label)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
    }
}
