import SwiftUI

struct ExerciseDisplayView: View {
    let exercise: WorkoutExercise
    let currentSet: Int
    let totalSets: Int
    let blockName: String
    let onComplete: () -> Void
    let onSkip: () -> Void
    let onSwap: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showSetComplete = false

    var body: some View {
        VStack(spacing: AppSpacing.lg) {
            Spacer()

            // Block name
            Text(blockName)
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textSecondary)
                .textCase(.uppercase)

            // Exercise icon placeholder
            Image(systemName: iconForExercise)
                .font(.system(size: 64))
                .foregroundStyle(AppColors.brand)
                .frame(height: 100)

            // Exercise name
            Text(exercise.exercise.displayName)
                .font(AppTypography.title)
                .foregroundStyle(AppColors.textPrimary)
                .multilineTextAlignment(.center)

            // Set/rep display
            if let reps = exercise.reps {
                Text("Set \(currentSet) of \(totalSets) — \(reps) reps")
                    .font(AppTypography.title2)
                    .foregroundStyle(AppColors.textSecondary)
            } else if let duration = exercise.durationSeconds {
                Text("Set \(currentSet) of \(totalSets) — \(duration) seconds")
                    .font(AppTypography.title2)
                    .foregroundStyle(AppColors.textSecondary)
            }

            // Set tracker
            SetTrackerView(currentSet: currentSet, totalSets: totalSets)

            // Form tip
            if let tip = exercise.notes ?? exercise.exercise.instructions.first {
                Text(tip)
                    .font(AppTypography.footnote)
                    .foregroundStyle(AppColors.textSecondary)
                    .padding(.horizontal, AppSpacing.xl)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            // Done button — large touch target
            Button {
                if !reduceMotion {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                        showSetComplete = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        showSetComplete = false
                        onComplete()
                    }
                } else {
                    onComplete()
                }
            } label: {
                Text("Done with Set \(currentSet)")
                    .font(AppTypography.title2)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 64)
                    .background(AppColors.success)
                    .clipShape(RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusCard))
            }
            .padding(.horizontal, AppSpacing.lg)
            .accessibilityLabel("Complete set \(currentSet) of \(totalSets)")
            .overlay {
                if showSetComplete {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 72))
                        .foregroundStyle(AppColors.success)
                        .scaleEffect(showSetComplete ? 1.2 : 0.5)
                        .opacity(showSetComplete ? 1.0 : 0.0)
                        .transition(.scale.combined(with: .opacity))
                }
            }

            // Skip/Swap buttons
            HStack(spacing: AppSpacing.xl) {
                Button(action: onSwap) {
                    Label("Swap", systemImage: "arrow.triangle.2.circlepath")
                        .font(AppTypography.subheadline)
                        .foregroundStyle(AppColors.textSecondary)
                }
                .accessibilityLabel("Swap exercise")
                .accessibilityHint("Replace this exercise with an alternative")

                Button(action: onSkip) {
                    Label("Skip", systemImage: "forward.fill")
                        .font(AppTypography.subheadline)
                        .foregroundStyle(AppColors.textSecondary)
                }
                .accessibilityLabel("Skip exercise")
                .accessibilityHint("Skip this exercise and move to the next one")
            }
            .padding(.bottom, AppSpacing.xl)
        }
    }

    // Per-exercise SF Symbol overrides for accuracy
    private static let exerciseIcons: [String: String] = [
        // MARK: Push Horizontal — pressing motions
        "push_up": "figure.strengthtraining.traditional",
        "diamond_push_up": "figure.strengthtraining.traditional",
        "incline_push_up": "figure.strengthtraining.traditional",
        "dips_on_chair": "figure.strengthtraining.traditional",
        "wall_push_up": "figure.strengthtraining.traditional",
        "wide_push_up": "figure.strengthtraining.traditional",
        "archer_push_up": "figure.strengthtraining.traditional",
        "pseudo_planche_push_up": "figure.strengthtraining.traditional",
        "one_arm_push_up": "figure.strengthtraining.traditional",
        "planche_lean_push_up": "figure.strengthtraining.traditional",
        "dumbbell_shoulder_press": "figure.strengthtraining.traditional",
        "dumbbell_lateral_raise": "dumbbell.fill",

        // MARK: Push Vertical — overhead / handstand
        "pike_push_up": "figure.strengthtraining.traditional",
        "decline_push_up": "figure.strengthtraining.traditional",
        "wall_handstand_hold": "figure.strengthtraining.traditional",
        "elevated_pike_push_up": "figure.strengthtraining.traditional",
        "wall_handstand_push_up": "figure.strengthtraining.traditional",
        "deficit_handstand_push_up": "figure.strengthtraining.traditional",
        "handstand_negative": "figure.strengthtraining.traditional",
        "freestanding_handstand_push_up": "figure.strengthtraining.traditional",
        "ninety_degree_push_up": "figure.strengthtraining.traditional",

        // MARK: Pull Vertical — hanging / pulling up
        "dumbbell_curl": "dumbbell.fill",
        "dead_hang": "figure.strengthtraining.functional",
        "scapular_pull_up": "figure.strengthtraining.functional",
        "band_assisted_pull_up": "figure.strengthtraining.functional",
        "negative_pull_up": "figure.strengthtraining.functional",
        "chin_up": "figure.strengthtraining.functional",
        "pull_up": "figure.strengthtraining.functional",
        "wide_pull_up": "figure.strengthtraining.functional",
        "l_sit_pull_up": "figure.strengthtraining.functional",
        "muscle_up": "figure.strengthtraining.functional",
        "typewriter_pull_up": "figure.strengthtraining.functional",

        // MARK: Pull Horizontal — rows
        "dumbbell_row": "figure.rowing",
        "band_pull_apart": "figure.rowing",
        "prone_y_raise": "figure.rowing",
        "inverted_row_high": "figure.rowing",
        "inverted_row": "figure.rowing",
        "ring_row": "figure.rowing",
        "archer_inverted_row": "figure.rowing",
        "tuck_front_lever_row": "figure.rowing",
        "front_lever_row": "figure.rowing",
        "one_arm_inverted_row": "figure.rowing",

        // MARK: Squat
        "bodyweight_squat": "figure.strengthtraining.functional",
        "goblet_squat": "figure.strengthtraining.functional",
        "sumo_squat": "figure.strengthtraining.functional",
        "jump_squat": "figure.highintensity.intervaltraining",
        "cossack_squat": "figure.cross.training",
        "shrimp_squat": "figure.strengthtraining.functional",
        "sissy_squat": "figure.strengthtraining.functional",
        "pistol_squat": "figure.strengthtraining.functional",
        "dragon_squat": "figure.strengthtraining.functional",

        // MARK: Hinge
        "superman": "figure.flexibility",
        "glute_bridge": "figure.core.training",
        "dumbbell_rdl": "figure.strengthtraining.functional",
        "hip_hinge_drill": "figure.flexibility",
        "single_leg_glute_bridge": "figure.core.training",
        "good_morning_bodyweight": "figure.flexibility",
        "single_leg_rdl": "figure.strengthtraining.functional",
        "hip_thrust": "figure.core.training",
        "nordic_curl": "figure.strengthtraining.functional",
        "natural_glute_ham_raise": "figure.strengthtraining.functional",

        // MARK: Lunge / step
        "reverse_lunge": "figure.step.training",
        "step_up": "figure.stair.stepper",
        "lateral_lunge": "figure.cross.training",
        "dumbbell_split_squat": "figure.step.training",
        "calf_raise": "figure.step.training",
        "split_squat": "figure.step.training",
        "assisted_lunge": "figure.step.training",
        "walking_lunge": "figure.step.training",
        "deficit_reverse_lunge": "figure.step.training",
        "curtsy_lunge": "figure.cross.training",
        "jumping_lunge": "figure.highintensity.intervaltraining",
        "skater_squat": "figure.step.training",

        // MARK: Carry
        "plank_shoulder_tap": "figure.core.training",
        "farmer_walk_band": "figure.walk",
        "bear_crawl": "figure.cross.training",
        "overhead_carry_band": "figure.walk",
        "crab_walk": "figure.cross.training",
        "suitcase_carry_band": "figure.walk",
        "alligator_walk": "figure.cross.training",
        "single_arm_overhead_carry": "figure.walk",

        // MARK: Core Anti-Extension
        "plank": "figure.core.training",
        "dead_bug": "figure.core.training",
        "hollow_hold": "figure.core.training",
        "bird_dog": "figure.core.training",
        "kneeling_plank": "figure.core.training",
        "extended_plank": "figure.core.training",
        "body_saw": "figure.core.training",
        "long_lever_plank": "figure.core.training",
        "dragon_flag": "figure.core.training",
        "ring_body_saw": "figure.core.training",

        // MARK: Core Flexion
        "crunch": "figure.core.training",
        "lying_knee_tuck": "figure.core.training",
        "reverse_crunch": "figure.core.training",
        "v_up": "figure.core.training",
        "lying_leg_raise": "figure.core.training",
        "toe_touch_crunch": "figure.core.training",
        "hanging_knee_raise": "figure.strengthtraining.functional",
        "pike_crunch": "figure.core.training",
        "hanging_leg_raise": "figure.strengthtraining.functional",
        "toes_to_bar": "figure.strengthtraining.functional",

        // MARK: Core Rotation
        "bicycle_crunch": "figure.core.training",
        "dead_bug_twist": "figure.core.training",
        "seated_twist": "figure.cross.training",
        "russian_twist": "figure.cross.training",
        "woodchop_band": "figure.cross.training",
        "plank_rotation": "figure.core.training",
        "windshield_wiper": "figure.cross.training",
        "hanging_windshield_wiper": "figure.cross.training",
        "full_windshield_wiper": "figure.cross.training",
        "dragon_flag_twist": "figure.core.training",

        // MARK: Core Compression
        "seated_knee_tuck": "figure.core.training",
        "boat_hold": "figure.core.training",
        "v_sit_hold": "figure.core.training",
        "pike_pulse": "figure.core.training",
        "tuck_l_sit": "figure.core.training",
        "l_sit_floor": "figure.core.training",
        "l_sit": "figure.core.training",
        "v_sit": "figure.core.training",

        // MARK: Cardio
        "mountain_climber": "figure.highintensity.intervaltraining",
        "jumping_jack": "figure.jumprope",
        "high_knee_march": "figure.walk",
        "high_knees": "figure.run",
        "butt_kick": "figure.run",
        "skater_hop": "figure.cross.training",
        "squat_thrust": "figure.highintensity.intervaltraining",
        "burpee": "figure.highintensity.intervaltraining",
        "tuck_jump": "figure.highintensity.intervaltraining",
        "burpee_pull_up": "figure.highintensity.intervaltraining",
        "plyometric_push_up": "figure.highintensity.intervaltraining",

        // MARK: Primal
        "frog_squat": "figure.mixed.cardio",
        "crawl_forward": "figure.mixed.cardio",
        "inchworm": "figure.flexibility",
        "monkey_walk": "figure.mixed.cardio",
        "scorpion_reach": "figure.flexibility",
        "lizard_crawl": "figure.mixed.cardio",

        // MARK: Mobility / stretching
        "arm_circles": "figure.cooldown",
        "leg_swings": "figure.flexibility",
        "cat_cow": "figure.flexibility",
        "childs_pose": "figure.mind.and.body",
        "standing_quad_stretch": "figure.cooldown",
        "seated_hamstring_stretch": "figure.flexibility",
    ]

    private var iconForExercise: String {
        Self.exerciseIcons[exercise.exercise.id] ?? movementPatternFallbackIcon
    }

    private var movementPatternFallbackIcon: String {
        switch exercise.exercise.movementPattern {
        case .pushHorizontal: "figure.strengthtraining.traditional"
        case .pushVertical: "figure.strengthtraining.traditional"
        case .pullVertical: "figure.strengthtraining.functional"
        case .pullHorizontal: "figure.rowing"
        case .squat: "figure.strengthtraining.functional"
        case .hinge: "figure.flexibility"
        case .lunge: "figure.step.training"
        case .coreAntiExtension: "figure.core.training"
        case .coreFlexion: "figure.core.training"
        case .coreRotation: "figure.cross.training"
        case .coreCompression: "figure.core.training"
        case .cardio: "figure.run"
        case .carry: "figure.walk"
        case .mobility: "figure.flexibility"
        case .primal: "figure.mixed.cardio"
        }
    }
}
