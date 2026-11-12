import Observation
import SwiftUI

/// Backs the Reminders screen in Settings (M4, US-CA08): every reminder the Coach or the user set, each
/// editable, switchable and deletable. Notification permission is asked only when a reminder is first
/// switched on or added.
@MainActor
@Observable
final class RemindersViewModel {
    private(set) var reminders: [CoachReminder] = []
    private(set) var message: String?

    private let service: CoachReminderService
    private let now: () -> Date

    init(service: CoachReminderService, now: @escaping () -> Date = { Date() }) {
        self.service = service
        self.now = now
    }

    func load() async {
        reminders = await service.reminders()
    }

    /// A new reminder's starting point: 7:30 AM on weekdays, not yet saved.
    func draft() -> CoachReminder {
        CoachReminder(hour: 7, minute: 30, weekdays: Array(2...6), createdAt: now())
    }

    func save(_ reminder: CoachReminder) async {
        message = nil
        do {
            try await service.save(reminder)
        } catch {
            message = CoachReminderCopy.permissionDenied
        }
        await load()
    }

    func setEnabled(_ enabled: Bool, for reminder: CoachReminder) async {
        var changed = reminder
        changed.isEnabled = enabled
        await save(changed)
    }

    func delete(_ reminder: CoachReminder) async {
        await service.delete(id: reminder.id)
        await load()
    }
}

/// The Reminders screen (US-CA08): identity-framed, never a nag.
struct RemindersView: View {
    @State private var viewModel: RemindersViewModel
    @State private var editing: CoachReminder?

    init(service: CoachReminderService) {
        _viewModel = State(initialValue: RemindersViewModel(service: service))
    }

    init(viewModel: RemindersViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        List {
            Section {
                if viewModel.reminders.isEmpty {
                    Text(CoachReminderCopy.empty)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .frame(minHeight: Theme.Spacing.minTouchTarget)
                }
                ForEach(viewModel.reminders) { reminder in
                    ReminderRow(
                        reminder: reminder,
                        onEdit: { editing = reminder },
                        onToggle: { enabled in Task { await viewModel.setEnabled(enabled, for: reminder) } }
                    )
                    .swipeActions {
                        Button(role: .destructive) {
                            Task { await viewModel.delete(reminder) }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
                Button {
                    editing = viewModel.draft()
                } label: {
                    Label(CoachReminderCopy.addReminder, systemImage: "plus")
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.accent)
                        .frame(minHeight: Theme.Spacing.minTouchTarget)
                }
            } footer: {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    if let message = viewModel.message {
                        Text(message)
                            .foregroundStyle(Theme.Colors.danger)
                    }
                    Text(CoachReminderCopy.settingsFooter)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                .font(Theme.Typography.caption)
                .fixedSize(horizontal: false, vertical: true)
            }
            .listRowBackground(Theme.Colors.surface)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.Colors.background)
        .navigationTitle(CoachReminderCopy.settingsTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
        .sheet(item: $editing) { reminder in
            ReminderEditor(
                reminder: reminder,
                isNew: !viewModel.reminders.contains { $0.id == reminder.id },
                onSave: { edited in Task { await viewModel.save(edited) } },
                onDelete: { Task { await viewModel.delete(reminder) } }
            )
        }
    }
}

private struct ReminderRow: View {
    let reminder: CoachReminder
    let onEdit: () -> Void
    let onToggle: (Bool) -> Void

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            Button(action: onEdit) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(CoachReminderCopy.time(hour: reminder.hour, minute: reminder.minute))
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text(CoachReminderCopy.days(reminder.weekdays))
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                .frame(maxWidth: .infinity, minHeight: Theme.Spacing.minTouchTarget, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                "Reminder at \(CoachReminderCopy.time(hour: reminder.hour, minute: reminder.minute)), \(CoachReminderCopy.spokenDays(reminder.weekdays))"
            )
            .accessibilityHint("Edit or delete this reminder")

            Toggle("", isOn: Binding(get: { reminder.isEnabled }, set: onToggle))
                .labelsHidden()
                .tint(Theme.Colors.accent)
                // Names which reminder it switches; VoiceOver reads its on or off state after.
                .accessibilityLabel("Reminder at \(CoachReminderCopy.time(hour: reminder.hour, minute: reminder.minute))")
        }
    }
}

/// Edits one reminder's time and days.
private struct ReminderEditor: View {
    let isNew: Bool
    let onSave: (CoachReminder) -> Void
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var reminder: CoachReminder
    @State private var time: Date

    init(reminder: CoachReminder, isNew: Bool, onSave: @escaping (CoachReminder) -> Void, onDelete: @escaping () -> Void) {
        _reminder = State(initialValue: reminder)
        var components = DateComponents()
        components.hour = reminder.hour
        components.minute = reminder.minute
        _time = State(initialValue: Calendar.current.date(from: components) ?? Date())
        self.isNew = isNew
        self.onSave = onSave
        self.onDelete = onDelete
    }

    /// Monday first, the way a week reads.
    private static let weekOrder = [2, 3, 4, 5, 6, 7, 1]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                        .font(Theme.Typography.body)
                        .frame(minHeight: Theme.Spacing.minTouchTarget)
                }
                Section {
                    ForEach(Self.weekOrder, id: \.self) { weekday in
                        let name = Calendar.current.weekdaySymbols[weekday - 1]
                        Toggle(name, isOn: Binding(
                            get: { reminder.weekdays.contains(weekday) },
                            set: { on in
                                var days = Set(reminder.weekdays)
                                if on { days.insert(weekday) } else { days.remove(weekday) }
                                reminder.weekdays = days.sorted()
                            }
                        ))
                        .font(Theme.Typography.body)
                        .tint(Theme.Colors.accent)
                        .frame(minHeight: Theme.Spacing.minTouchTarget)
                    }
                } header: {
                    Text("Days")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                if !isNew {
                    Section {
                        Button(role: .destructive) {
                            onDelete()
                            dismiss()
                        } label: {
                            Label("Delete reminder", systemImage: "trash")
                                .font(Theme.Typography.body)
                                .foregroundStyle(Theme.Colors.danger)
                                .frame(minHeight: Theme.Spacing.minTouchTarget)
                        }
                    }
                }
            }
            .navigationTitle(isNew ? CoachReminderCopy.addReminder : "Edit reminder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let parts = Calendar.current.dateComponents([.hour, .minute], from: time)
                        reminder.hour = parts.hour ?? reminder.hour
                        reminder.minute = parts.minute ?? reminder.minute
                        reminder.isEnabled = true
                        onSave(reminder)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(reminder.weekdays.isEmpty)
                }
            }
        }
    }
}
