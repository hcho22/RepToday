import SwiftUI

/// Review and edit a Custom Workout before accepting it (M4, US-CA05): swap a movement, remove one,
/// reorder them, and change sets, reps, time or rest. Nothing is saved - and nothing can play - until
/// **Accept** (FR-11); **Cancel** keeps the Coach's proposal as it was.
struct CustomWorkoutEditorView: View {
    let library: [Exercise]
    let trainer: Trainer?
    /// The edited workout, and whether to play it straight away.
    let onAccept: (CustomWorkout, Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var workout: CustomWorkout
    @State private var editingStep: CustomWorkoutStep?
    @State private var swappingStep: CustomWorkoutStep?

    init(workout: CustomWorkout, library: [Exercise], trainer: Trainer?, onAccept: @escaping (CustomWorkout, Bool) -> Void) {
        _workout = State(initialValue: workout)
        self.library = library
        self.trainer = trainer
        self.onAccept = onAccept
    }

    private var prescriptions: [PrescribedExercise] { workout.prescriptions(library: library) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(workout.note)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("About \(workout.estimatedMinutes) min · plays hands-free · counts like an Outside Activity")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Section {
                    ForEach(prescriptions) { prescription in
                        Button {
                            editingStep = workout.steps.first { $0.id == prescription.id }
                        } label: {
                            HStack {
                                CustomWorkoutStepRow(prescription: prescription, trainer: trainer)
                                Image(systemName: "chevron.right")
                                    .font(Theme.Typography.caption)
                                    .foregroundStyle(Theme.Colors.textSecondary)
                                    .accessibilityHidden(true)
                            }
                            .frame(minHeight: Theme.Spacing.minTouchTarget)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Change sets, reps or time, or swap this movement")
                        .swipeActions(edge: .leading) {
                            Button("Swap") { swappingStep = workout.steps.first { $0.id == prescription.id } }
                                .tint(Theme.Colors.accentFill)
                        }
                    }
                    .onMove { from, to in workout.steps.move(fromOffsets: from, toOffset: to) }
                    .onDelete { offsets in
                        guard workout.steps.count - offsets.count >= 1 else { return }
                        workout.steps.remove(atOffsets: offsets)
                    }
                } header: {
                    Text("Steps")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                } footer: {
                    Text("Tap a step to change it. Use Edit to reorder or remove steps.")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
            .navigationTitle(workout.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    EditButton()
                }
            }
            .safeAreaInset(edge: .bottom) { acceptBar }
            .sheet(item: $editingStep) { step in
                CustomWorkoutStepEditor(
                    step: step,
                    library: library,
                    canRemove: workout.steps.count > 1,
                    onSave: { edited in replace(edited) },
                    onRemove: { workout.steps.removeAll { $0.id == step.id } },
                    onSwap: { swappingStep = step }
                )
            }
            .sheet(item: $swappingStep) { step in
                MovementPickerView(library: library, current: step.exerciseId) { exercise in
                    replace(step.swapped(to: exercise))
                }
            }
        }
    }

    private var acceptBar: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Button {
                onAccept(workout, false)
                dismiss()
            } label: {
                Text("Accept")
                    .font(Theme.Typography.button)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: Theme.Spacing.buttonHeight)
            }
            .buttonStyle(.bordered)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Spacing.cardCornerRadius))
            .accessibilityHint("Saves this workout. It does not start yet.")

            Button {
                onAccept(workout, true)
                dismiss()
            } label: {
                Label("Accept and play", systemImage: "play.fill")
                    .font(Theme.Typography.button)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: Theme.Spacing.buttonHeight)
            }
            .accentFilledButtonStyle()
            .clipShape(RoundedRectangle(cornerRadius: Theme.Spacing.cardCornerRadius))
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.background)
    }

    private func replace(_ step: CustomWorkoutStep) {
        guard let index = workout.steps.firstIndex(where: { $0.id == step.id }) else { return }
        workout.steps[index] = step
    }
}

extension CustomWorkoutStep {
    /// This step done as a different catalog movement: its name, its hold or rep shape and its per-side
    /// flag follow the new movement, while sets and rest stay.
    func swapped(to exercise: Exercise) -> CustomWorkoutStep {
        var step = self
        step.name = exercise.displayName
        step.exerciseId = exercise.id
        step.perSide = exercise.isPerSide == true
        if exercise.isHold {
            step.seconds = seconds ?? exercise.defaultDurationSeconds ?? 30
            step.reps = nil
        } else {
            step.reps = reps ?? exercise.defaultReps ?? 10
            step.seconds = nil
        }
        return step
    }
}

/// Edits one step's sets, reps or time and rest.
private struct CustomWorkoutStepEditor: View {
    let library: [Exercise]
    let canRemove: Bool
    let onSave: (CustomWorkoutStep) -> Void
    let onRemove: () -> Void
    let onSwap: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var step: CustomWorkoutStep

    init(step: CustomWorkoutStep, library: [Exercise], canRemove: Bool, onSave: @escaping (CustomWorkoutStep) -> Void, onRemove: @escaping () -> Void, onSwap: @escaping () -> Void) {
        _step = State(initialValue: step)
        self.library = library
        self.canRemove = canRemove
        self.onSave = onSave
        self.onRemove = onRemove
        self.onSwap = onSwap
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    stepper("Sets", value: $step.sets, range: CustomWorkout.setRange, step: 1) { "\($0)" }
                    if step.isTimed {
                        stepper("Time per set", value: secondsBinding, range: CustomWorkout.secondsRange, step: 5) { "\($0) sec" }
                    } else {
                        stepper("Reps per set", value: repsBinding, range: CustomWorkout.repRange, step: 1) { "\($0)" }
                    }
                    stepper("Rest after each set", value: $step.restSeconds, range: CustomWorkout.restRange, step: 5) { "\($0) sec" }
                } header: {
                    Text(step.name)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                } footer: {
                    if step.perSide {
                        Text("Per side: each set is done on both sides.")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                }

                Section {
                    Button {
                        dismiss()
                        onSwap()
                    } label: {
                        Label("Swap for another movement", systemImage: "arrow.triangle.2.circlepath")
                            .font(Theme.Typography.body)
                            .frame(minHeight: Theme.Spacing.minTouchTarget)
                    }
                    if canRemove {
                        Button(role: .destructive) {
                            onRemove()
                            dismiss()
                        } label: {
                            Label("Remove this step", systemImage: "trash")
                                .font(Theme.Typography.body)
                                .foregroundStyle(Theme.Colors.danger)
                                .frame(minHeight: Theme.Spacing.minTouchTarget)
                        }
                    }
                }
            }
            .navigationTitle("Edit step")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onSave(step)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var repsBinding: Binding<Int> {
        Binding(get: { step.reps ?? 10 }, set: { step.reps = $0 })
    }

    private var secondsBinding: Binding<Int> {
        Binding(get: { step.seconds ?? 30 }, set: { step.seconds = $0 })
    }

    private func stepper(_ title: String, value: Binding<Int>, range: ClosedRange<Int>, step: Int, format: @escaping (Int) -> String) -> some View {
        Stepper(value: value, in: range, step: step) {
            HStack {
                Text(title)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Spacer(minLength: Theme.Spacing.sm)
                Text(format(value.wrappedValue))
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .monospacedDigit()
            }
        }
        .frame(minHeight: Theme.Spacing.minTouchTarget)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(format(value.wrappedValue))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value.wrappedValue = min(range.upperBound, value.wrappedValue + step)
            case .decrement: value.wrappedValue = max(range.lowerBound, value.wrappedValue - step)
            @unknown default: break
            }
        }
    }
}

/// Picks a catalog movement to swap a step to: the served movements, searchable, grouped by pattern.
private struct MovementPickerView: View {
    let library: [Exercise]
    let current: String?
    let onPick: (Exercise) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var served: [Exercise] {
        library
            .filter { !MovementAccess.isWithdrawn($0) && $0.equipment.isEmpty }
            .filter { query.isEmpty || $0.displayName.localizedCaseInsensitiveContains(query) }
            .sorted { ($0.movementPattern.rawValue, $0.difficulty, $0.displayName) < ($1.movementPattern.rawValue, $1.difficulty, $1.displayName) }
    }

    var body: some View {
        NavigationStack {
            List(served, id: \.id) { exercise in
                Button {
                    onPick(exercise)
                    dismiss()
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(exercise.displayName)
                                .font(Theme.Typography.body)
                                .foregroundStyle(Theme.Colors.textPrimary)
                            Text(exercise.movementPattern.rawValue.capitalized)
                                .font(Theme.Typography.caption)
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                        Spacer(minLength: Theme.Spacing.sm)
                        if exercise.id == current {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Theme.Colors.accent)
                                .accessibilityHidden(true)
                        }
                    }
                    .frame(minHeight: Theme.Spacing.minTouchTarget)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(exercise.id == current ? [.isButton, .isSelected] : .isButton)
            }
            .searchable(text: $query, prompt: "Search movements")
            .navigationTitle("Swap movement")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
