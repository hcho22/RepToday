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
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, Theme.Spacing.smd)
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
                            Label { Text("Delete") } icon: { AppIcon.trash.fixedImage }
                        }
                    }
                }
                Button {
                    editing = viewModel.draft()
                } label: {
                    HStack(spacing: Theme.Spacing.smd) {
                        ScaledIcon(icon: .plus, size: 22, relativeTo: .headline)
                            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                        Text(CoachReminderCopy.addReminder)
                            .font(Theme.Typography.headline)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .foregroundStyle(Theme.Colors.accent)
                    .padding(.vertical, Theme.Spacing.smd)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(CoachReminderCopy.addReminder)
            }
            .listRowBackground(Theme.Colors.surface1)
            .listRowSeparatorTint(Theme.Colors.line)
            .listRowInsets(EdgeInsets(top: 0, leading: 18, bottom: 0, trailing: 18))

            // The footnote as a clear row of its own, so it lines up with the group's edge like every
            // other group's footnote rather than taking a list footer's deeper inset.
            Section {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    if let message = viewModel.message {
                        GroupFooter(message, color: Theme.Colors.danger)
                    }
                    GroupFooter(CoachReminderCopy.settingsFooter)
                }
                // Held to the top of its row, which is at least the list's 60 pt row height.
                .frame(maxHeight: .infinity, alignment: .top)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets())
            }
        }
        // A list rather than a stack of groups, so each reminder keeps its swipe-to-delete; drawn in the
        // group tokens: `surface1` rows at least 60 pt tall, `line` separators, the 20 pt screen margin.
        .listStyle(.insetGrouped)
        .listSectionSpacing(Theme.Spacing.smd)
        .environment(\.defaultMinListRowHeight, Theme.Spacing.rowHeight)
        .environment(\.defaultMinListHeaderHeight, 0)
        .contentMargins(.top, Theme.Spacing.xs, for: .scrollContent)
        .contentMargins(.horizontal, Theme.Spacing.screenMargin, for: .scrollContent)
        .scrollContentBackground(.hidden)
        .background(Theme.Colors.background)
        .screenTitle(CoachReminderCopy.settingsTitle)
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

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        // At accessibility sizes the switch moves under the time, so the time keeps the row's width.
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 0))
            : AnyLayout(HStackLayout(spacing: Theme.Spacing.md))
        layout {
            Button(action: onEdit) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(CoachReminderCopy.time(hour: reminder.hour, minute: reminder.minute))
                        .cappedDisplayFont(Theme.Typography.FontName.displaySmall, size: 28, relativeTo: .title2)
                        .monospacedDigit()
                        .foregroundStyle(Theme.Colors.textPrimary)
                        // A time is one word: it shrinks rather than break between the digits and AM.
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Text(CoachReminderCopy.days(reminder.weekdays))
                        .font(Theme.Typography.callout)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, Theme.Spacing.smd)
                .frame(maxWidth: .infinity, minHeight: Theme.Spacing.rowHeight, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                "Reminder at \(CoachReminderCopy.time(hour: reminder.hour, minute: reminder.minute)), \(CoachReminderCopy.spokenDays(reminder.weekdays))"
            )
            .accessibilityHint("Edit or delete this reminder")

            // Names which reminder it switches; VoiceOver reads its on or off state after.
            ThemeSwitch(
                label: "Reminder at \(CoachReminderCopy.time(hour: reminder.hour, minute: reminder.minute))",
                isOn: Binding(get: { reminder.isEnabled }, set: onToggle)
            )
            .padding(.bottom, dynamicTypeSize.isAccessibilitySize ? Theme.Spacing.smd : 0)
        }
    }
}

/// Edits one reminder's time and days.
private struct ReminderEditor: View {
    let isNew: Bool
    let onSave: (CoachReminder) -> Void
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
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
            ScrollView {
                VStack(spacing: 0) {
                    // At accessibility sizes the picker moves under its name, so neither splits a word.
                    let timeLayout = dynamicTypeSize.isAccessibilitySize
                        ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Spacing.sm))
                        : AnyLayout(HStackLayout(spacing: Theme.Spacing.md))
                    timeLayout {
                        Text("Time")
                            .font(Theme.Typography.headline)
                            .foregroundStyle(Theme.Colors.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            // The picker carries the same name, so VoiceOver hears it once.
                            .accessibilityHidden(true)
                        DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                            .font(Theme.Typography.body)
                    }
                    .padding(.vertical, Theme.Spacing.smd)
                    .frame(minHeight: Theme.Spacing.rowHeight)

                    GroupHeader("Days")
                        .padding(.top, Theme.Spacing.md)
                        .padding(.bottom, Theme.Spacing.xs)

                    ForEach(Self.weekOrder, id: \.self) { weekday in
                        let name = Calendar.current.weekdaySymbols[weekday - 1]
                        if weekday != Self.weekOrder.first {
                            GroupSeparator()
                        }
                        SwitchRow(title: name, isOn: Binding(
                            get: { reminder.weekdays.contains(weekday) },
                            set: { on in
                                var days = Set(reminder.weekdays)
                                if on { days.insert(weekday) } else { days.remove(weekday) }
                                reminder.weekdays = days.sorted()
                            }
                        ))
                    }

                    if !isNew {
                        Button(role: .destructive) {
                            onDelete()
                            dismiss()
                        } label: {
                            HStack(spacing: Theme.Spacing.sm) {
                                ScaledIcon(icon: .trash, size: 20, relativeTo: .headline)
                                    .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                                Text("Delete reminder")
                                    .font(Theme.Typography.button)
                                    .multilineTextAlignment(.center)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: Theme.Spacing.buttonHeight)
                        }
                        .dangerButtonStyle()
                        .accessibilityLabel("Delete reminder")
                        .padding(.top, Theme.Spacing.lg)
                    }
                }
                .padding(.horizontal, Theme.Spacing.screenMargin)
                .padding(.bottom, Theme.Spacing.mlg)
            }
            .background(Theme.Colors.surface1)
            .screenTitle(isNew ? CoachReminderCopy.addReminder : "Edit reminder")
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
        .tint(Theme.Colors.sun)
        .sheetSurface()
    }
}
