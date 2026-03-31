import SwiftUI

struct NotificationSettingsView: View {
    @State private var notificationsEnabled = true
    @State private var reminderHour = 8
    @State private var reminderMinute = 0

    var body: some View {
        Form {
            Section {
                Toggle("Daily Reminder", isOn: $notificationsEnabled)
            }

            if notificationsEnabled {
                Section("Reminder Time") {
                    DatePicker(
                        "Time",
                        selection: Binding(
                            get: {
                                var components = DateComponents()
                                components.hour = reminderHour
                                components.minute = reminderMinute
                                return Calendar.current.date(from: components) ?? Date()
                            },
                            set: { date in
                                let components = Calendar.current.dateComponents([.hour, .minute], from: date)
                                reminderHour = components.hour ?? 8
                                reminderMinute = components.minute ?? 0
                            }
                        ),
                        displayedComponents: .hourAndMinute
                    )
                }

                Section {
                    Text("You'll receive a maximum of 1 notification per day.")
                        .font(AppTypography.footnote)
                        .foregroundStyle(AppColors.textSecondary)
                }
            }
        }
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
    }
}
