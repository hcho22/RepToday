import SwiftUI

/// The canonical copy for Focus Areas (US-HO02), shared by the onboarding step, the Settings editor and
/// the tests that pin it, so they cannot drift apart.
enum FocusAreasCopy {
    static let onboardingTitle = "Anything you want to build?"
    static let onboardingSubtitle = "Pick the areas you'd like a bit more attention on. "
        + "Your Push, Pull and Legs days stay in order. (Optional.)"

    /// The Settings row and screen title.
    static let title = "Focus Areas"

    /// The Settings row's value when nothing is chosen.
    static let noneChosen = "None"

    /// The editor's explanation, shown as its section footer.
    static let intro = "A focus area gets a bit more attention on its day: its movement comes first, "
        + "gets extra reps first when there's time, and gets the practice spot first. "
        + "Abs adds a second core move. Your Push, Pull and Legs order never changes."

    static let save = "Save changes"
    static let saved = "Saved. Your next session will use this."
    static let loadFailed = "We couldn't read your focus areas."
    static let saveFailed = "We couldn't save that. Please try again."

    /// The Settings row's value: the chosen areas in canonical order, or "None".
    static func summary(_ areas: [FocusArea]) -> String {
        areas.isEmpty ? noneChosen : areas.canonicallyOrdered.map(\.label).joined(separator: ", ")
    }
}

/// The onboarding Focus Areas choice (US-HO02): one card per area, multi-select, each naming what it
/// changes. Styled like the onboarding fitness-level cards.
struct FocusAreaList: View {
    @Binding var selection: Set<FocusArea>

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            ForEach(FocusArea.allCases) { area in
                let isSelected = selection.contains(area)
                Button {
                    if isSelected { selection.remove(area) } else { selection.insert(area) }
                } label: {
                    HStack(alignment: .top, spacing: Theme.Spacing.md) {
                        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                            Text(area.label)
                                .font(Theme.Typography.headline)
                                .foregroundStyle(Theme.Colors.textPrimary)
                            Text(area.detail)
                                .font(Theme.Typography.caption)
                                .foregroundStyle(Theme.Colors.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .multilineTextAlignment(.leading)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(isSelected ? Theme.Colors.accent : Theme.Colors.textSecondary)
                            .accessibilityHidden(true)
                    }
                    .padding(Theme.Spacing.md)
                    .frame(maxWidth: .infinity, minHeight: Theme.Spacing.minTouchTarget, alignment: .leading)
                    .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Spacing.cardCornerRadius))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Spacing.cardCornerRadius)
                            .stroke(isSelected ? Theme.Colors.accent : .clear, lineWidth: 2)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: Theme.Spacing.cardCornerRadius))
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(area.label)
                .accessibilityValue(area.detail)
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            }
        }
    }
}

/// The Settings editor for Focus Areas (US-HO02). The choice is staged, then saved; a save rebuilds the
/// session on Today right away (`AppState.planInputsRevision`).
struct FocusAreasView: View {
    /// Optional so a hosted evidence surface can mount the screen without an `AppState`.
    @Environment(AppState.self) private var appState: AppState?

    @State private var viewModel: FocusAreasViewModel
    @State private var didSave = false

    init(services: ServiceContainer) {
        _viewModel = State(initialValue: FocusAreasViewModel(userService: services.userService))
    }

    init(viewModel: FocusAreasViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        List {
            Section {
                ForEach(FocusArea.allCases) { area in
                    row(area)
                }
            } footer: {
                Text(FocusAreasCopy.intro)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .listRowBackground(Theme.Colors.surface)

            Section {
                if didSave && !viewModel.hasChanges {
                    Label(FocusAreasCopy.saved, systemImage: "checkmark.circle.fill")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let error = viewModel.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button {
                    Task {
                        if await viewModel.save() {
                            didSave = true
                            appState?.markPlanInputsChanged()
                        }
                    }
                } label: {
                    Text(FocusAreasCopy.save)
                        .font(Theme.Typography.button)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: Theme.Spacing.buttonHeight)
                }
                .accentFilledButtonStyle()
                .clipShape(RoundedRectangle(cornerRadius: Theme.Spacing.cardCornerRadius))
                .disabled(!viewModel.hasChanges || viewModel.isSaving)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
        }
        .task { await viewModel.load() }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.Colors.background)
        .navigationTitle(FocusAreasCopy.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ area: FocusArea) -> some View {
        let isSelected = viewModel.selection.contains(area)
        return Button {
            viewModel.toggle(area)
            didSave = false
        } label: {
            HStack(spacing: Theme.Spacing.md) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text(area.label)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text(area.detail)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: Theme.Spacing.sm)
                Image(systemName: "checkmark")
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.accent)
                    .opacity(isSelected ? 1 : 0)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: Theme.Spacing.minTouchTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!viewModel.isLoaded)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(area.label)
        .accessibilityValue(area.detail)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
