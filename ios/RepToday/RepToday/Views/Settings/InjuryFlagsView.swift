import SwiftUI

/// The canonical copy for the injury control (US-AC08), in one place so the screen, the Settings row
/// that leads to it, and the tests that pin its honesty cannot drift apart.
enum InjuryFlagsCopy {

    /// The screen title, and the Settings row that navigates to it.
    static let title = "Areas to protect"

    /// What turning an area on actually does. Stated in terms of what the engine does next time it
    /// builds a session - never as a claim about a session already on screen.
    static let intro = "Switch on anything you'd rather work around. Rep Today stops choosing movements "
        + "that load that area when it builds your next session."

    /// The Settings section footer. It names who is allowed to change this, which is the point of the
    /// control existing at all.
    static let settingsFooter = "Only you set these. The coach can suggest flagging an area if you "
        + "mention it, but it never turns one on or off for you."

    /// The confirm control. Named as a confirmation of a staged change rather than an ambient switch.
    static let confirm = "Save changes"

    /// The reassurance under the confirm control: this is reversible, always.
    static let reversible = "You can switch any of these back off here at any time."

    /// Shown after a save lands, so the user sees that their action - not the coach's - is what changed.
    static let saved = "Saved. Your next session will use this."

    /// The explicit way out of the coach-routed sheet: back out having changed nothing. Named for what
    /// it does, so it can never read as confirming the staged area.
    static let cancel = "Cancel"

    /// The retry control on a failed read, so a screen that could not load is never a dead end.
    static let retry = "Try again"
}

/// The injury control: the one place an injury safety filter is set or cleared after onboarding
/// (US-AC08).
///
/// Reachable two ways, and it is the *same* screen both times: from Settings, and from the coach's
/// routing offer, which opens it pre-targeted at the area the user mentioned. The coach never writes a
/// flag - it can only bring the user here.
///
/// Edits are **staged then confirmed**: a toggle changes nothing on the profile, the summary above the
/// confirm control names exactly what the tap will start or stop protecting, and backing out without
/// confirming writes nothing. Every flag is reversible from this same screen.
struct InjuryFlagsView: View {
    @Environment(\.dismiss) private var dismiss
    /// Optional so the hosted evidence surfaces that mount this screen without an `AppState` still
    /// render. When present, a confirmed change bumps its US-AC08 revision so the Ready screen
    /// regenerates today's session against the new safety filter without a relaunch.
    @Environment(AppState.self) private var appState: AppState?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var viewModel: InjuryFlagsViewModel

    /// The area to open pre-targeted (staged on, unconfirmed), when arriving from the coach's route.
    private let preselect: InjuryOption?

    /// Whether to dismiss once a save lands. True when presented as a sheet from the coach, where the
    /// user came to do one thing; false in Settings, where they stay on the screen they navigated to.
    private let dismissesOnSave: Bool

    /// Production entry from Settings: builds the view model over the container's user service.
    init(services: ServiceContainer, preselect: InjuryOption? = nil, dismissesOnSave: Bool = false) {
        _viewModel = State(initialValue: InjuryFlagsViewModel(userService: services.userService))
        self.preselect = preselect
        self.dismissesOnSave = dismissesOnSave
    }

    /// Test/preview entry: inject a pre-built view model.
    init(viewModel: InjuryFlagsViewModel, preselect: InjuryOption? = nil, dismissesOnSave: Bool = false) {
        _viewModel = State(initialValue: viewModel)
        self.preselect = preselect
        self.dismissesOnSave = dismissesOnSave
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.smd) {
                RowGroup {
                    VStack(spacing: 0) {
                        ForEach(InjuryOption.allCases) { area in
                            if area != InjuryOption.allCases.first {
                                GroupSeparator()
                            }
                            SwitchRow(title: area.label, isOn: binding(for: area))
                                // A screen that could not read the profile has nothing to stage against, so
                                // its switches do not pretend otherwise while the confirmation sits inert.
                                .disabled(!viewModel.canEdit)
                                .accessibilityLabel(area.label)
                                .accessibilityHint("Stages \(area.label.lowercased()) as an area to work around. Nothing changes until you save.")
                        }
                    }
                    .padding(.vertical, Theme.Spacing.xs)
                }
                GroupFooter(InjuryFlagsCopy.intro)

                if viewModel.loadFailed {
                    RowGroup {
                        Button {
                            Task { await viewModel.retryLoad(preselecting: preselect) }
                        } label: {
                            Text(InjuryFlagsCopy.retry)
                                .font(Theme.Typography.headline)
                                .foregroundStyle(Theme.Colors.accentOnElevatedSurface)
                                .frame(maxWidth: .infinity, minHeight: Theme.Spacing.rowHeight, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(InjuryFlagsCopy.retry)
                        .accessibilityHint("Reads your saved areas again")
                    }
                }

                GroupFooter(InjuryFlagsCopy.reversible)

                if dynamicTypeSize.isAccessibilitySize {
                    changeSummary
                }
            }
            .padding(.horizontal, Theme.Spacing.screenMargin)
            .padding(.bottom, Theme.Spacing.mlg)
        }
        // The confirmation, pinned: the change is named immediately above the control that makes it, so the
        // user is confirming something specific rather than pressing an opaque Save. At accessibility sizes
        // the named change ends the scrolling column instead, so the pinned block never covers a switch; what
        // the save did stays pinned above the button either way.
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                if !dynamicTypeSize.isAccessibilitySize {
                    changeSummary
                }
                saveResult

                Button(action: confirm) {
                    Text(InjuryFlagsCopy.confirm)
                        .font(Theme.Typography.button)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: Theme.Spacing.buttonHeight)
                }
                .accentFilledButtonStyle()
                .disabled(!viewModel.canSave)
                .accessibilityLabel(InjuryFlagsCopy.confirm)
                .accessibilityHint("Applies the areas you switched on to your future sessions")
            }
            .padding(.horizontal, Theme.Spacing.screenMargin)
            .padding(.vertical, Theme.Spacing.smd)
            .background(Theme.Colors.background)
        }
        .background(Theme.Colors.background)
        .screenTitle(InjuryFlagsCopy.title)
        .toolbar {
            // Presented as a sheet from the coach's route, backing out is the "I changed my mind"
            // path, and a swipe-down is the least discoverable control on the screen. So it is an
            // explicit affordance that drops the staged edits and leaves without writing anything.
            // In Settings the screen is pushed and the back button already says this, so no item.
            if dismissesOnSave {
                ToolbarItem(placement: .cancellationAction) {
                    Button(InjuryFlagsCopy.cancel, action: cancel)
                        .frame(minHeight: Theme.Spacing.minTouchTarget)
                        .accessibilityLabel(InjuryFlagsCopy.cancel)
                        .accessibilityHint("Closes without changing any of your areas")
                }
            }
        }
        .task { await viewModel.load(preselecting: preselect) }
    }

    /// The named change: what the confirmation is about.
    @ViewBuilder
    private var changeSummary: some View {
        if let summary = viewModel.changeSummary {
            Text(summary)
                .font(Theme.Typography.callout)
                .foregroundStyle(Theme.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel(summary)
        }
    }

    /// The Saved line and any error: what the confirmation did.
    @ViewBuilder
    private var saveResult: some View {
        if viewModel.didSave {
            Label {
                Text(InjuryFlagsCopy.saved)
            } icon: {
                ScaledIcon(icon: .check, size: 16, relativeTo: .footnote)
                    .foregroundStyle(Theme.Colors.legs)
            }
            .font(Theme.Typography.footnote)
            .foregroundStyle(Theme.Colors.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(InjuryFlagsCopy.saved)
        }

        if let error = viewModel.errorMessage {
            Text(error)
                .font(Theme.Typography.footnote)
                .foregroundStyle(Theme.Colors.danger)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel(error)
        }
    }

    private func binding(for area: InjuryOption) -> Binding<Bool> {
        Binding(
            get: { viewModel.isSelected(area) },
            set: { viewModel.set(area, to: $0) }
        )
    }

    private func confirm() {
        Task {
            await viewModel.save()
            guard viewModel.didSave else { return }
            // A safety filter has to reach the session the user is about to start, not the one after
            // the next relaunch, so tell the Ready screen to rebuild today's session.
            appState?.markInjuryFlagsChanged()
            if dismissesOnSave { dismiss() }
        }
    }

    /// Leave without confirming: drop every staged edit, then dismiss. Nothing was written, so this
    /// changes nothing on the profile - it is the control's own "declining changes nothing" path.
    private func cancel() {
        viewModel.discardChanges()
        dismiss()
    }
}

#if DEBUG
#Preview("Settings entry") {
    NavigationStack {
        InjuryFlagsView(viewModel: InjuryFlagsViewModel(userService: MockUserService(user: MockPersistence.sampleUser)))
    }
}

#Preview("Routed from the coach") {
    NavigationStack {
        InjuryFlagsView(
            viewModel: InjuryFlagsViewModel(userService: MockUserService(user: MockPersistence.sampleUser)),
            preselect: .knees,
            dismissesOnSave: true
        )
    }
}
#endif
