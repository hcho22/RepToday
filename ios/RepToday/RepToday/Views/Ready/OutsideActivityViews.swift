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

    /// What a played Custom Workout did to the plan (decision 27, FR-8): it counts like an Outside Activity.
    static func customWorkoutEffect(group: TrainingDay?) -> String {
        switch group {
        case .legs?: return "This Custom Workout worked your legs, so your next Legs Day waits a day. It counts as showing up."
        case .pull?: return "This Custom Workout worked your pulling muscles, so your next Pull Day waits a day. It counts as showing up."
        case .push?: return "This Custom Workout worked your pushing muscles, so your next Push Day waits a day. It counts as showing up."
        case nil: return "This Custom Workout counts as showing up. Your Training Days stay as they are."
        }
    }

    /// "Custom Workout: Desk Reset · 20 min", or the type summary for any other activity.
    static func summary(of activity: OutsideActivity) -> String {
        guard activity.isCustomWorkout else {
            return summary(type: activity.type, durationMinutes: activity.durationMinutes, distanceMeters: activity.distanceMeters)
        }
        return [activity.label, "\(activity.durationMinutes) min"].joined(separator: " · ")
    }

    /// The spoken form of `summary(of:)`.
    static func spokenSummary(of activity: OutsideActivity) -> String {
        guard activity.isCustomWorkout else {
            return spokenSummary(type: activity.type, durationMinutes: activity.durationMinutes, distanceMeters: activity.distanceMeters)
        }
        return [activity.label, CountWording.phrase(activity.durationMinutes, singular: "minute", plural: "minutes")].joined(separator: ", ")
    }

    /// The icon an activity row shows: the kind of workout, or the Coach's mark for a Custom Workout it
    /// wrote.
    static func icon(of activity: OutsideActivity) -> AppIcon {
        activity.isCustomWorkout ? .coach : activity.type.icon
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
        VStack(alignment: .leading, spacing: Theme.Spacing.smd) {
            Text(OutsideActivityCopy.sectionTitle)
                .font(Theme.Typography.cardTitle)
                .foregroundStyle(Theme.Colors.text1)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            if activities.isEmpty {
                Text(OutsideActivityCopy.sectionEmpty)
                    .font(Theme.Typography.callout)
                    .foregroundStyle(Theme.Colors.text2)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(activities.enumerated()), id: \.element.id) { index, activity in
                        OutsideActivityRow(activity: activity) { onEdit(activity) }
                        if index < activities.count - 1 {
                            GroupSeparator()
                        }
                    }
                }
            }

            Button(action: onLog) {
                HStack(spacing: Theme.Spacing.sm) {
                    ScaledIcon(icon: .plus, size: 22, relativeTo: .headline)
                    Text(OutsideActivityCopy.logButton)
                        .font(Theme.Typography.button)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, Theme.Spacing.sm)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 52)
            }
            .secondaryButtonStyle()
            .accessibilityLabel(OutsideActivityCopy.logButton)
            .accessibilityHint("Adds a run, swim or other workout you did outside Rep Today")
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
        .accessibilityElement(children: .contain)
    }
}

private struct OutsideActivityRow: View {
    let activity: OutsideActivity
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: Theme.Spacing.smd) {
                ScaledIcon(icon: OutsideActivityCopy.icon(of: activity), size: 24, relativeTo: .headline)
                    .foregroundStyle(Theme.Colors.sun)
                VStack(alignment: .leading, spacing: 2) {
                    Text(OutsideActivityCopy.summary(of: activity))
                        .font(Theme.Typography.rowName)
                        .foregroundStyle(Theme.Colors.text1)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(OutsideActivityCopy.day(activity.date))
                        .font(Theme.Typography.footnote)
                        .foregroundStyle(Theme.Colors.text2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                IconView(icon: .chevr, size: 18)
                    .foregroundStyle(Theme.Colors.text3)
            }
            .padding(.vertical, Theme.Spacing.sm)
            .frame(minHeight: Theme.Spacing.rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            OutsideActivityCopy.spokenSummary(of: activity) + ", " + OutsideActivityCopy.day(activity.date).lowercased()
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
        VStack(alignment: .leading, spacing: Theme.Spacing.smd) {
            // The icon sits above the words at the accessibility sizes, so it never squeezes them.
            let header = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Spacing.sm))
                : AnyLayout(HStackLayout(alignment: .top, spacing: Theme.Spacing.smd))
            header {
                ScaledIcon(icon: candidate.type.icon, size: 28, relativeTo: .title2)
                    .foregroundStyle(Theme.Colors.sun)
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text(OutsideActivityCopy.healthSource.uppercased())
                        .overlineStyle()
                        .foregroundStyle(Theme.Colors.text2)
                    Text(OutsideActivityCopy.summary(
                        type: candidate.type,
                        durationMinutes: candidate.durationMinutes,
                        distanceMeters: candidate.distanceMeters
                    ))
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.text1)
                    .fixedSize(horizontal: false, vertical: true)
                    Text(OutsideActivityCopy.day(candidate.start))
                        .font(Theme.Typography.footnote)
                        .foregroundStyle(Theme.Colors.text2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
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
                ? AnyLayout(VStackLayout(spacing: 10))
                : AnyLayout(HStackLayout(spacing: 10))
            layout {
                Button(action: onAdd) {
                    Text(OutsideActivityCopy.addIt)
                        .font(Theme.Typography.button)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 48)
                }
                .accentFilledButtonStyle()
                .accessibilityHint("Logs it as an outside activity")

                Button(action: onIgnore) {
                    Text(OutsideActivityCopy.ignore)
                        .font(Theme.Typography.button)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 48)
                }
                .secondaryButtonStyle()
                .accessibilityHint("Won't suggest this workout again")
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Entry sheet

/// The Outside Activity entry sheet (US-HO04): type, when, duration and an optional distance, logged or
/// saved in place; an existing activity can be deleted here too. Drawn on the sheet's `surface1`
/// (`screens/T14-Log-Outside-Activity.html`): the kinds of workout as a grid of tiles, then the When,
/// Duration and Distance rows.
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var type: OutsideActivityType
    @State private var date: Date
    @State private var durationMinutes: Int
    @State private var distanceText: String
    @State private var isSaving = false
    @State private var confirmsDelete = false
    @State private var enabledHealth = false
    @FocusState private var distanceFocused: Bool

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
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.mlg) {
                    activitySection
                    fieldRows

                    if let errorMessage {
                        Text(errorMessage)
                            .font(Theme.Typography.footnote)
                            .foregroundStyle(Theme.Colors.danger)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if existing != nil {
                        Button(role: .destructive) {
                            confirmsDelete = true
                        } label: {
                            HStack(spacing: Theme.Spacing.sm) {
                                ScaledIcon(icon: .trash, size: 22, relativeTo: .headline)
                                Text(OutsideActivityCopy.delete)
                                    .font(Theme.Typography.button)
                                    .multilineTextAlignment(.center)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: Theme.Spacing.buttonHeight)
                        }
                        .dangerButtonStyle()
                        .disabled(isSaving)
                        .accessibilityLabel(OutsideActivityCopy.delete)
                    } else if offersHealthOptIn && !enabledHealth {
                        healthOptIn
                    }
                }
                .padding(.horizontal, Theme.Spacing.screenMargin)
                .padding(.top, Theme.Spacing.sm)
                .padding(.bottom, Theme.Spacing.xl)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.Colors.surface1)
            .navigationTitle(existing == nil ? OutsideActivityCopy.newTitle : OutsideActivityCopy.editTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.Colors.surface1, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(existing == nil ? OutsideActivityCopy.newTitle : OutsideActivityCopy.editTitle)
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Colors.text1)
                        .accessibilityAddTraits(.isHeader)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button(OutsideActivityCopy.cancel) { dismiss() }
                        .font(Theme.Typography.headline.weight(.semibold))
                        .foregroundStyle(Theme.Colors.text2)
                        .disabled(isSaving)
                }
                .plainToolbarItemBackground()
                ToolbarItem(placement: .confirmationAction) {
                    Button(OutsideActivityCopy.save) { save() }
                        .font(Theme.Typography.headline)
                        .foregroundStyle(isSaving || !isDistanceValid ? Theme.Colors.text3 : Theme.Colors.sun)
                        .disabled(isSaving || !isDistanceValid)
                }
                .plainToolbarItemBackground()
            }
            .confirmationDialog(OutsideActivityCopy.deleteConfirm, isPresented: $confirmsDelete, titleVisibility: .visible) {
                Button(OutsideActivityCopy.delete, role: .destructive) { delete() }
                Button(OutsideActivityCopy.cancel, role: .cancel) {}
            }
        }
        .sheetSurface()
        .presentationDragIndicator(.visible)
    }

    // MARK: Activity

    /// The kind of workout: a tile per kind rather than a menu, so the choice is one tap and its name never
    /// truncates at the larger text sizes. Two columns, one at the accessibility text sizes. A played
    /// Custom Workout keeps what it was: only its time and length can change.
    @ViewBuilder
    private var activitySection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.smd) {
            if let existing, existing.isCustomWorkout {
                HStack(spacing: Theme.Spacing.smd) {
                    ScaledIcon(icon: OutsideActivityCopy.icon(of: existing), size: 24, relativeTo: .headline)
                        .foregroundStyle(Theme.Colors.sun)
                    Text(existing.label)
                        .font(Theme.Typography.rowName)
                        .foregroundStyle(Theme.Colors.text1)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, Theme.Spacing.sm)
                .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
                .background(Theme.Colors.surface2, in: RoundedRectangle(cornerRadius: Theme.Spacing.inputCornerRadius))
                .accessibilityElement(children: .combine)
                Text(OutsideActivityCopy.customWorkoutEffect(group: existing.customWorkoutGroup))
                    .font(Theme.Typography.footnote)
                    .foregroundStyle(Theme.Colors.text2)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                let columns = Array(
                    repeating: GridItem(.flexible(), spacing: Theme.Spacing.sm, alignment: .top),
                    count: dynamicTypeSize.isAccessibilitySize ? 1 : 2
                )
                LazyVGrid(columns: columns, alignment: .leading, spacing: Theme.Spacing.sm) {
                    ForEach(OutsideActivityType.allCases) { option in
                        typeTile(option)
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Activity")
                Text(OutsideActivityCopy.effect(of: type))
                    .font(Theme.Typography.footnote)
                    .foregroundStyle(Theme.Colors.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// A tile for one kind of workout: its icon, its name, and a check when chosen - when the tile also
    /// fills with the `sun` tint inside a 2 pt `sun` outline.
    private func typeTile(_ option: OutsideActivityType) -> some View {
        let isSelected = type == option
        return Button {
            type = option
        } label: {
            HStack(spacing: 10) {
                ScaledIcon(icon: option.icon, size: 24, relativeTo: .headline)
                    .foregroundStyle(isSelected ? Theme.Colors.sun : Theme.Colors.text2)
                Text(option.label)
                    .font(Theme.Typography.chip)
                    .foregroundStyle(Theme.Colors.text1)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if isSelected {
                    ScaledIcon(icon: .check, size: 18, relativeTo: .headline)
                        .foregroundStyle(Theme.Colors.sun)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, Theme.Spacing.sm)
            .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
            .animation(.easeOut(duration: 0.12)) {
                $0.background(isSelected ? Theme.Colors.sunTint : Theme.Colors.surface2,
                              in: RoundedRectangle(cornerRadius: Theme.Spacing.inputCornerRadius))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Spacing.inputCornerRadius)
                            .strokeBorder(isSelected ? Theme.Colors.sun : .clear, lineWidth: 2)
                    )
            }
            .contentShape(RoundedRectangle(cornerRadius: Theme.Spacing.inputCornerRadius))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option.label)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: Fields

    /// When, Duration and (for a workout with a distance) Distance, as rows split by 1 pt separators.
    private var fieldRows: some View {
        VStack(spacing: 0) {
            fieldRow("When") {
                DatePicker("When", selection: $date, in: earliestDate...now, displayedComponents: [.date, .hourAndMinute])
                    .labelsHidden()
                    .datePickerStyle(.compact)
                    .tint(Theme.Colors.sun)
                    .font(Theme.Typography.chip)
            }
            GroupSeparator()
            durationRow
            if type.hasDistance && existing?.isCustomWorkout != true {
                GroupSeparator()
                fieldRow("Distance") {
                    HStack(spacing: Theme.Spacing.sm) {
                        TextField("Optional", text: $distanceText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(dynamicTypeSize.isAccessibilitySize ? .leading : .trailing)
                            .focused($distanceFocused)
                            .themeInputField(isFocused: distanceFocused)
                            .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : 140)
                            .accessibilityLabel("Distance in \(DistanceFormatting.unit == .kilometers ? "kilometers" : "miles"), optional")
                        Text(DistanceFormatting.unitSymbol)
                            .font(Theme.Typography.calloutMedium)
                            .foregroundStyle(Theme.Colors.text2)
                            .accessibilityHidden(true)
                    }
                }
            }
        }
    }

    /// The duration, in 5-minute steps, as one adjustable VoiceOver element - "Duration, 30 minutes",
    /// swipe up or down to change it - with two 44 pt step buttons for touch.
    private var durationRow: some View {
        fieldRow("Duration") {
            HStack(spacing: Theme.Spacing.sm) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(durationMinutes)")
                        .font(Theme.Typography.stepperValue)
                        .monospacedDigit()
                        .foregroundStyle(Theme.Colors.text1)
                    Text("min")
                        .font(Theme.Typography.calloutMedium)
                        .foregroundStyle(Theme.Colors.text2)
                }
                .lineLimit(1)
                .fixedSize()
                .padding(.trailing, Theme.Spacing.sm)
                stepButton(.minus, enabled: durationMinutes > 5) {
                    durationMinutes = max(5, durationMinutes - 5)
                }
                stepButton(.plus, enabled: durationMinutes < OutsideActivity.maxDurationMinutes) {
                    durationMinutes = min(OutsideActivity.maxDurationMinutes, durationMinutes + 5)
                }
            }
        }
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
    }

    private func stepButton(_ icon: AppIcon, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            IconView(icon: icon, size: 22)
                .foregroundStyle(Theme.Colors.text1)
                .frame(width: Theme.Spacing.minTouchTarget, height: Theme.Spacing.minTouchTarget)
                .background(Theme.Colors.surface2, in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
    }

    /// A field's name and its control side by side, at least 60 pt tall, or stacked at the accessibility
    /// text sizes so neither is squeezed.
    @ViewBuilder
    private func fieldRow<Value: View>(_ title: String, @ViewBuilder value: () -> Value) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Spacing.sm))
            : AnyLayout(HStackLayout(spacing: Theme.Spacing.sm))
        layout {
            Text(title)
                .font(Theme.Typography.rowName)
                .foregroundStyle(Theme.Colors.text1)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? nil : .infinity, alignment: .leading)
            value()
        }
        .padding(.vertical, Theme.Spacing.sm)
        .frame(maxWidth: .infinity, minHeight: Theme.Spacing.rowHeight, alignment: .leading)
    }

    // MARK: Apple Health

    private var healthOptIn: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Button {
                enabledHealth = true
                onEnableHealthSuggestions()
            } label: {
                HStack(spacing: Theme.Spacing.sm) {
                    ScaledIcon(icon: .health, size: 22, relativeTo: .headline)
                    Text(OutsideActivityCopy.healthOptInTitle)
                        .font(Theme.Typography.button)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: 52)
            }
            .secondaryButtonStyle()
            .accessibilityLabel(OutsideActivityCopy.healthOptInTitle)
            Text(OutsideActivityCopy.healthOptInDetail)
                .font(Theme.Typography.footnote)
                .foregroundStyle(Theme.Colors.text2)
                .fixedSize(horizontal: false, vertical: true)
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
            distanceMeters: type.hasDistance && existing?.isCustomWorkout != true
                ? parsedDistance.map(DistanceFormatting.meters(fromValue:))
                : nil,
            healthWorkoutId: existing?.healthWorkoutId,
            customWorkoutId: existing?.customWorkoutId,
            customWorkoutTitle: existing?.customWorkoutTitle,
            customWorkoutGroup: existing?.customWorkoutGroup
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

private extension ToolbarItem {
    /// The sheet's Cancel and Save as plain text (`screens/T14-Log-Outside-Activity.html`), without the
    /// glass capsule iOS 26 puts behind a toolbar item.
    @ToolbarContentBuilder
    func plainToolbarItemBackground() -> some ToolbarContent {
        if #available(iOS 26.0, *) {
            sharedBackgroundVisibility(.hidden)
        } else {
            self
        }
    }
}
