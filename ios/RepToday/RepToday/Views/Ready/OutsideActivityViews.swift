import SwiftUI

// MARK: - Copy

/// The Outside Activity copy (US-HO04, US-HO05), one source for Today, the entry sheet and the tests that
/// pin it. Identity-framed: an outside workout is showing up, never a gap to explain.
enum OutsideActivityCopy {
    static let sectionTitle = "Outside activity"
    static let logButton = "Log outside activity"
    static let sectionEmpty = "Ran, swam or climbed today? Log it and your plan gives those muscles a day off."
    static let newTitle = "Log activity"
    static let editTitle = "Edit activity"
    static let save = "Save"
    static let cancel = "Cancel"
    static let delete = "Delete activity"
    static let deleteConfirm = "Delete this activity?"
    static let healthSource = "From Apple Health"
    static let addIt = "Add it"
    static let ignore = "Ignore"
    static let healthOptInTitle = "Suggest from Apple Health"
    static let healthOptInDetail = "Have an Apple Watch? Rep Today can suggest the workouts you record in Apple "
        + "Health, like runs and swims. Nothing is logged until you tap Add it."

    /// What logging this kind of workout does to the plan (decision 21).
    static func effect(of type: OutsideActivityType) -> String {
        switch type.group {
        case .legs?: return "Runs, rides and hikes work your legs, so your next Legs Day waits a day. It counts as showing up."
        case .pull?: return "Swims, rows and climbs work your pulling muscles, so your next Pull Day waits a day. It counts as showing up."
        case .push?: return "It works your pushing muscles, so your next Push Day waits a day. It counts as showing up."
        case nil: return "It counts as showing up. Your Training Days stay as they are."
        }
    }

    /// "Run · 30 min · 3.1 mi"
    static func summary(type: OutsideActivityType, durationMinutes: Int, distanceMeters: Double?) -> String {
        var parts = [type.label, "\(durationMinutes) min"]
        if type.hasDistance, let distanceMeters, distanceMeters > 0 {
            parts.append(DistanceFormatting.short(meters: distanceMeters))
        }
        return parts.joined(separator: " · ")
    }

    /// "Run, 30 minutes, 3.1 miles"
    static func spokenSummary(type: OutsideActivityType, durationMinutes: Int, distanceMeters: Double?) -> String {
        var parts = [type.label, CountWording.phrase(durationMinutes, singular: "minute", plural: "minutes")]
        if type.hasDistance, let distanceMeters, distanceMeters > 0 {
            parts.append(DistanceFormatting.spoken(meters: distanceMeters))
        }
        return parts.joined(separator: ", ")
    }

    /// "Today", "Yesterday", or the weekday.
    static func day(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return "Today" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return "Yesterday"
        }
        return date.formatted(.dateTime.weekday(.wide))
    }
}

/// Distances in the unit the user's region reads them in: miles in the US, kilometers elsewhere.
enum DistanceFormatting {
    static var unit: UnitLength {
        Locale.current.measurementSystem == .metric ? .kilometers : .miles
    }

    static var unitSymbol: String { unit == .kilometers ? "km" : "mi" }

    static func value(meters: Double) -> Double {
        Measurement(value: meters, unit: UnitLength.meters).converted(to: unit).value
    }

    static func meters(fromValue value: Double) -> Double {
        Measurement(value: value, unit: unit).converted(to: .meters).value
    }

    static func short(meters: Double) -> String {
        "\(value(meters: meters).formatted(.number.precision(.fractionLength(0...1)))) \(unitSymbol)"
    }

    static func spoken(meters: Double) -> String {
        let amount = value(meters: meters).formatted(.number.precision(.fractionLength(0...1)))
        let noun = unit == .kilometers ? "kilometers" : "miles"
        return "\(amount) \(noun)"
    }
}

// MARK: - Today card

/// Today's Outside Activity card (US-HO04): the activities logged this past week, each tappable to edit
/// or delete, and "Log outside activity".
struct OutsideActivityCard: View {
    let activities: [OutsideActivity]
    let onLog: () -> Void
    let onEdit: (OutsideActivity) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text(OutsideActivityCopy.sectionTitle)
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.textPrimary)
                .accessibilityAddTraits(.isHeader)

            if activities.isEmpty {
                Text(OutsideActivityCopy.sectionEmpty)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(spacing: Theme.Spacing.sm) {
                    ForEach(activities) { activity in
                        OutsideActivityRow(activity: activity) { onEdit(activity) }
                    }
                }
            }

            Button(action: onLog) {
                Label(OutsideActivityCopy.logButton, systemImage: "plus")
                    .font(Theme.Typography.button)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: Theme.Spacing.buttonHeight)
            }
            .buttonStyle(.bordered)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Spacing.cardCornerRadius))
            .accessibilityLabel(OutsideActivityCopy.logButton)
            .accessibilityHint("Adds a run, swim or other workout you did outside Rep Today")
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Spacing.cardCornerRadius))
        .accessibilityElement(children: .contain)
    }
}

private struct OutsideActivityRow: View {
    let activity: OutsideActivity
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: Theme.Spacing.md) {
                Image(systemName: activity.type.systemImage)
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.accent)
                    .frame(width: Theme.Spacing.minTouchTarget)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text(OutsideActivityCopy.summary(
                        type: activity.type,
                        durationMinutes: activity.durationMinutes,
                        distanceMeters: activity.distanceMeters
                    ))
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    Text(OutsideActivityCopy.day(activity.date))
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                Spacer(minLength: Theme.Spacing.sm)
                Image(systemName: "chevron.right")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: Theme.Spacing.minTouchTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            OutsideActivityCopy.spokenSummary(
                type: activity.type,
                durationMinutes: activity.durationMinutes,
                distanceMeters: activity.distanceMeters
            ) + ", " + OutsideActivityCopy.day(activity.date).lowercased()
        )
        .accessibilityHint("Edit or delete this activity")
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Health suggestion card

/// One Apple Health workout offered on Today (US-HO05): "Add it" logs it as an Outside Activity, "Ignore"
/// takes it away for good. Nothing changes without a tap.
struct HealthSuggestionCard: View {
    let candidate: HealthWorkoutCandidate
    let onAdd: () -> Void
    let onIgnore: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(alignment: .top, spacing: Theme.Spacing.md) {
                Image(systemName: candidate.type.systemImage)
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.Colors.accent)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text(OutsideActivityCopy.healthSource)
                        .font(Theme.Typography.caption.weight(.semibold))
                        .foregroundStyle(Theme.Colors.textSecondary)
                    Text(OutsideActivityCopy.summary(
                        type: candidate.type,
                        durationMinutes: candidate.durationMinutes,
                        distanceMeters: candidate.distanceMeters
                    ))
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    Text(OutsideActivityCopy.day(candidate.start))
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                "\(OutsideActivityCopy.healthSource): "
                    + OutsideActivityCopy.spokenSummary(
                        type: candidate.type,
                        durationMinutes: candidate.durationMinutes,
                        distanceMeters: candidate.distanceMeters
                    )
                    + ", " + OutsideActivityCopy.day(candidate.start).lowercased()
            )

            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(spacing: Theme.Spacing.sm))
                : AnyLayout(HStackLayout(spacing: Theme.Spacing.md))
            layout {
                Button(action: onAdd) {
                    Text(OutsideActivityCopy.addIt)
                        .font(Theme.Typography.button)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: Theme.Spacing.minTouchTarget)
                }
                .accentFilledButtonStyle()
                .clipShape(RoundedRectangle(cornerRadius: Theme.Spacing.cardCornerRadius))
                .accessibilityHint("Logs it as an outside activity")

                Button(action: onIgnore) {
                    Text(OutsideActivityCopy.ignore)
                        .font(Theme.Typography.button)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: Theme.Spacing.minTouchTarget)
                }
                .buttonStyle(.bordered)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Spacing.cardCornerRadius))
                .accessibilityHint("Won't suggest this workout again")
            }
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Spacing.cardCornerRadius))
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Entry sheet

/// The Outside Activity entry sheet (US-HO04): type, when, duration and an optional distance, logged or
/// saved in place; an existing activity can be deleted here too.
struct OutsideActivitySheet: View {
    /// The activity being edited, or `nil` for a new one.
    let existing: OutsideActivity?
    /// Whether to offer the Apple Health opt-in (a new entry, suggestions not yet on).
    let offersHealthOptIn: Bool
    let onSave: (OutsideActivity) async -> Bool
    let onDelete: (OutsideActivity) async -> Bool
    let onEnableHealthSuggestions: () -> Void
    var errorMessage: String?

    @Environment(\.dismiss) private var dismiss
    @State private var type: OutsideActivityType
    @State private var date: Date
    @State private var durationMinutes: Int
    @State private var distanceText: String
    @State private var isSaving = false
    @State private var confirmsDelete = false
    @State private var enabledHealth = false

    private let now: Date

    init(
        existing: OutsideActivity?,
        offersHealthOptIn: Bool,
        errorMessage: String? = nil,
        now: Date = Date(),
        onSave: @escaping (OutsideActivity) async -> Bool,
        onDelete: @escaping (OutsideActivity) async -> Bool,
        onEnableHealthSuggestions: @escaping () -> Void
    ) {
        self.existing = existing
        self.offersHealthOptIn = offersHealthOptIn
        self.errorMessage = errorMessage
        self.now = now
        self.onSave = onSave
        self.onDelete = onDelete
        self.onEnableHealthSuggestions = onEnableHealthSuggestions
        _type = State(initialValue: existing?.type ?? .run)
        _date = State(initialValue: existing?.date ?? now)
        _durationMinutes = State(initialValue: existing?.durationMinutes ?? OutsideActivity.defaultDurationMinutes)
        _distanceText = State(initialValue: existing?.distanceMeters.map {
            DistanceFormatting.value(meters: $0).formatted(.number.precision(.fractionLength(0...2)).grouping(.never))
        } ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Activity", selection: $type) {
                        ForEach(OutsideActivityType.allCases) { option in
                            Label(option.label, systemImage: option.systemImage).tag(option)
                        }
                    }
                    .font(Theme.Typography.body)
                    .frame(minHeight: Theme.Spacing.minTouchTarget)
                } footer: {
                    Text(OutsideActivityCopy.effect(of: type))
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Section {
                    DatePicker("When", selection: $date, in: earliestDate...now, displayedComponents: [.date, .hourAndMinute])
                        .font(Theme.Typography.body)
                        .frame(minHeight: Theme.Spacing.minTouchTarget)
                    Stepper(value: $durationMinutes, in: 5...OutsideActivity.maxDurationMinutes, step: 5) {
                        HStack {
                            Text("Duration")
                                .font(Theme.Typography.body)
                                .foregroundStyle(Theme.Colors.textPrimary)
                            Spacer(minLength: Theme.Spacing.sm)
                            Text("\(durationMinutes) min")
                                .font(Theme.Typography.body)
                                .foregroundStyle(Theme.Colors.textSecondary)
                                .monospacedDigit()
                        }
                    }
                    .frame(minHeight: Theme.Spacing.minTouchTarget)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Duration")
                    .accessibilityValue(CountWording.phrase(durationMinutes, singular: "minute", plural: "minutes"))
                    .accessibilityAdjustableAction { direction in
                        switch direction {
                        case .increment: durationMinutes = min(OutsideActivity.maxDurationMinutes, durationMinutes + 5)
                        case .decrement: durationMinutes = max(5, durationMinutes - 5)
                        @unknown default: break
                        }
                    }
                    if type.hasDistance {
                        HStack {
                            Text("Distance")
                                .font(Theme.Typography.body)
                                .foregroundStyle(Theme.Colors.textPrimary)
                            Spacer(minLength: Theme.Spacing.sm)
                            TextField("Optional", text: $distanceText)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .font(Theme.Typography.body)
                                .accessibilityLabel("Distance in \(DistanceFormatting.unit == .kilometers ? "kilometers" : "miles"), optional")
                            Text(DistanceFormatting.unitSymbol)
                                .font(Theme.Typography.body)
                                .foregroundStyle(Theme.Colors.textSecondary)
                                .accessibilityHidden(true)
                        }
                        .frame(minHeight: Theme.Spacing.minTouchTarget)
                    }
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.danger)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if existing != nil {
                    Section {
                        Button(role: .destructive) {
                            confirmsDelete = true
                        } label: {
                            Label(OutsideActivityCopy.delete, systemImage: "trash")
                                .font(Theme.Typography.body)
                                .foregroundStyle(Theme.Colors.danger)
                                .frame(minHeight: Theme.Spacing.minTouchTarget)
                        }
                        .disabled(isSaving)
                    }
                } else if offersHealthOptIn && !enabledHealth {
                    Section {
                        Button {
                            enabledHealth = true
                            onEnableHealthSuggestions()
                        } label: {
                            Label(OutsideActivityCopy.healthOptInTitle, systemImage: "heart.text.square")
                                .font(Theme.Typography.body)
                                .foregroundStyle(Theme.Colors.accent)
                                .frame(minHeight: Theme.Spacing.minTouchTarget)
                        }
                    } footer: {
                        Text(OutsideActivityCopy.healthOptInDetail)
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .navigationTitle(existing == nil ? OutsideActivityCopy.newTitle : OutsideActivityCopy.editTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(OutsideActivityCopy.cancel) { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(OutsideActivityCopy.save) { save() }
                        .fontWeight(.semibold)
                        .disabled(isSaving || !isDistanceValid)
                }
            }
            .confirmationDialog(OutsideActivityCopy.deleteConfirm, isPresented: $confirmsDelete, titleVisibility: .visible) {
                Button(OutsideActivityCopy.delete, role: .destructive) { delete() }
                Button(OutsideActivityCopy.cancel, role: .cancel) {}
            }
        }
    }

    /// An activity may be logged up to a week back - the window that still shapes the plan and this
    /// week's score - or kept at its own date when editing an older one.
    private var earliestDate: Date {
        let weekBack = HealthWorkoutSuggestions.windowStart(asOf: now)
        return min(existing?.date ?? weekBack, weekBack)
    }

    private var parsedDistance: Double? {
        let trimmed = distanceText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let normalized = trimmed.replacingOccurrences(of: ",", with: ".")
        return Double(normalized)
    }

    private var isDistanceValid: Bool {
        guard type.hasDistance, !distanceText.trimmingCharacters(in: .whitespaces).isEmpty else { return true }
        guard let value = parsedDistance else { return false }
        return value > 0 && value < 1000
    }

    private func save() {
        isSaving = true
        let activity = OutsideActivity(
            id: existing?.id ?? UUID(),
            type: type,
            date: min(date, Date()),
            durationMinutes: durationMinutes,
            distanceMeters: type.hasDistance ? parsedDistance.map(DistanceFormatting.meters(fromValue:)) : nil,
            healthWorkoutId: existing?.healthWorkoutId
        )
        Task {
            let saved = await onSave(activity)
            isSaving = false
            if saved { dismiss() }
        }
    }

    private func delete() {
        guard let existing else { return }
        isSaving = true
        Task {
            let deleted = await onDelete(existing)
            isSaving = false
            if deleted { dismiss() }
        }
    }
}
