import SwiftUI

/// The app's Settings screen, pushed from the Profile tab.
///
/// It exists because US-T06 needs a reachable, clearly-labelled home for the anonymous-telemetry
/// opt-out, and burying that control would defeat the point of an opt-out. It is deliberately a real
/// sectioned Settings surface rather than an inline toggle on the Profile placeholder, so a later,
/// broader Profile/Settings story **extends** it - another `Section` - rather than replacing it, which
/// is how it has grown since: Privacy (US-T06), AI Coach (US-AC04), Reminders (US-CA08), Training
/// safety (US-AC08), Trainer (US-TP11), and Account (US-AD01, with Sign Out since US-SO01). Nothing else
/// about Profile changes here.
struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.services) private var services

    /// The account-deletion flow's view model (US-AD01/US-AD04/US-AD05). Built lazily on first use
    /// from the environment (services + `AppState`), which a `@State` default cannot capture at init.
    @State private var deletion: AccountDeletionViewModel?

    /// The sign-out flow's view model (US-SO01), built lazily on first use like `deletion`.
    @State private var signOut: AccountSignOutViewModel?

    /// The Trainer row's model (US-TP11), built on first appearance from the environment's services.
    @State private var trainerSettings: TrainerSettingsViewModel?

    /// The Focus Areas row's value (US-HO02), re-read on every appearance so a save shows on return.
    @State private var focusAreas: [FocusArea] = []

    /// How many reminders are set (US-CA08), re-read on every appearance.
    @State private var reminderCount = 0

    /// "None", "1 reminder", "2 reminders".
    static func reminderSummary(_ count: Int) -> String {
        count == 0 ? "None" : CountWording.phrase(count, singular: "reminder", plural: "reminders")
    }

    /// Production creates the deletion model lazily from the environment. Focused hosted-surface
    /// coverage can inject the same model directly so both confirmation variants are renderable
    /// without reaching a live Sign in with Apple service.
    init(deletion: AccountDeletionViewModel? = nil, trainerSettings: TrainerSettingsViewModel? = nil) {
        _deletion = State(initialValue: deletion)
        _trainerSettings = State(initialValue: trainerSettings)
    }

    var body: some View {
        @Bindable var appState = appState

        List {
            Section {
                Toggle(isOn: $appState.analyticsEnabled) {
                    Text(Self.toggleTitle)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.textPrimary)
                }
                .tint(Theme.Colors.accent)
                .frame(minHeight: Theme.Spacing.minTouchTarget)
                .accessibilityLabel(Self.toggleTitle)
                .accessibilityHint(Self.toggleHint)

                Link(destination: LegalLinks.privacyPolicy) {
                    HStack(spacing: Theme.Spacing.sm) {
                        Text("Privacy Policy")
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.Colors.accent)
                        Spacer(minLength: 0)
                        Image(systemName: "arrow.up.right.square")
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    .frame(minHeight: Theme.Spacing.minTouchTarget)
                }
                .accessibilityLabel("Privacy Policy")
                .accessibilityHint("Opens Rep Today's privacy policy in your browser")
            } header: {
                Text("Privacy")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            } footer: {
                Text(Self.explanation)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .listRowBackground(Theme.Colors.surface)

            // US-AC04: the coach data disclosure, mirrored into Settings so the same facts are
            // documented where a user looks for privacy choices. It is deliberately its **own** section,
            // separate from the telemetry opt-out above - it is informational (the consent gesture is
            // the one-time acknowledgement at first coach use, and using the coach at all is the opt-in),
            // and it neither reads nor writes the telemetry flag. The footer states the same disclosure
            // the pre-use modal shows.
            Section {
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .foregroundStyle(Theme.Colors.textSecondary)
                    Text(CoachDataDisclosureCopy.settingsRowTitle)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Spacer(minLength: 0)
                }
                .frame(minHeight: Theme.Spacing.minTouchTarget)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(CoachDataDisclosureCopy.settingsRowTitle)
            } header: {
                Text("AI Coach")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            } footer: {
                Text(CoachDataDisclosureCopy.settingsFooter)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .listRowBackground(Theme.Colors.surface)

            // US-CA08: the training reminders the Coach or the user set, listed, editable and deletable.
            Section {
                NavigationLink {
                    RemindersView(service: services.reminders)
                } label: {
                    HStack(spacing: Theme.Spacing.sm) {
                        Image(systemName: "bell")
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .accessibilityHidden(true)
                        Text(CoachReminderCopy.settingsTitle)
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.Colors.textPrimary)
                        Spacer(minLength: Theme.Spacing.sm)
                        Text(Self.reminderSummary(reminderCount))
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    .frame(minHeight: Theme.Spacing.minTouchTarget)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(CoachReminderCopy.settingsTitle)
                .accessibilityValue(Self.reminderSummary(reminderCount))
                .accessibilityHint("See, change or delete your training reminders")
                .accessibilityAddTraits(.isButton)
            }
            .listRowBackground(Theme.Colors.surface)

            // US-HO02: Focus Areas, the body parts a user wants a bit more attention on. A preference, not a
            // safety filter, so it sits apart from the injury control below.
            Section {
                NavigationLink {
                    FocusAreasView(services: services)
                } label: {
                    HStack(spacing: Theme.Spacing.sm) {
                        Image(systemName: "scope")
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .accessibilityHidden(true)
                        Text(FocusAreasCopy.title)
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.Colors.textPrimary)
                        Spacer(minLength: Theme.Spacing.sm)
                        Text(FocusAreasCopy.summary(focusAreas))
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .multilineTextAlignment(.trailing)
                            .lineLimit(2)
                    }
                    .frame(minHeight: Theme.Spacing.minTouchTarget)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(FocusAreasCopy.title)
                .accessibilityValue(FocusAreasCopy.summary(focusAreas))
                .accessibilityHint("Choose the body parts you want a bit more attention on")
                .accessibilityAddTraits(.isButton)

                Toggle(isOn: healthSuggestionsBinding) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text(Self.healthToggleTitle)
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.Colors.textPrimary)
                    }
                }
                .tint(Theme.Colors.accent)
                .frame(minHeight: Theme.Spacing.minTouchTarget)
                .accessibilityLabel(Self.healthToggleTitle)
                .accessibilityHint("Turns Apple Health workout suggestions on or off")
            } header: {
                Text("Training")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            } footer: {
                Text(Self.healthToggleFooter)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .listRowBackground(Theme.Colors.surface)

            // US-AC08: the injury control - the one place an injury safety filter is set or cleared
            // after onboarding, and the destination the coach's routing offer navigates to. It is a
            // real, findable Settings row precisely because the coach must never be the thing that
            // sets it; the footer says so plainly.
            Section {
                NavigationLink {
                    InjuryFlagsView(services: services)
                } label: {
                    HStack(spacing: Theme.Spacing.sm) {
                        Image(systemName: "shield.lefthalf.filled")
                            .foregroundStyle(Theme.Colors.textSecondary)
                        Text(InjuryFlagsCopy.title)
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.Colors.textPrimary)
                        Spacer(minLength: 0)
                    }
                    .frame(minHeight: Theme.Spacing.minTouchTarget)
                }
                .accessibilityLabel(InjuryFlagsCopy.title)
                .accessibilityHint("Choose areas Rep Today should work around in future sessions")
            } header: {
                Text("Training safety")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            } footer: {
                Text(InjuryFlagsCopy.settingsFooter)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .listRowBackground(Theme.Colors.surface)

            // US-TP11: the Trainer who demonstrates each movement, switchable at any time. Its own section
            // above Account (captain, Open Question 5), so the destructive action stays last.
            Section {
                trainerRow
            } header: {
                Text(TrainerChoiceCopy.settingsTitle)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            } footer: {
                Text(trainerSettings?.errorMessage ?? TrainerChoiceCopy.settingsFooter)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(trainerSettings?.errorMessage == nil ? Theme.Colors.textSecondary : Theme.Colors.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .listRowBackground(Theme.Colors.surface)

            // US-AD01: the mandatory account-deletion path (App Store Guideline 5.1.1(v)). A
            // destructive, clearly-labelled row in its own section, so it is findable in one tap from
            // the Profile tab's Settings and never mistaken for a benign control. US-SO01 puts Sign Out
            // above it, in plain styling (decision 13), for a signed-in user.
            Section {
                if appState.account != nil {
                    signOutRow
                }

                Button(role: .destructive) {
                    let model = deletionModel()
                    Task { await model.deleteAccountTapped() }
                } label: {
                    HStack(spacing: Theme.Spacing.sm) {
                        Image(systemName: "trash")
                        Text(Self.deleteAccountTitle)
                            .font(Theme.Typography.body)
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(Theme.Colors.danger)
                    .frame(minHeight: Theme.Spacing.minTouchTarget)
                }
                .disabled(isAccountActionRunning)
                .accessibilityLabel(Self.deleteAccountTitle)
                .accessibilityHint("Permanently deletes your profile and workout history")
            } header: {
                Text("Account")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            } footer: {
                Text(appState.account != nil ? Self.signOutFooter + "\n\n" + Self.deleteAccountFooter : Self.deleteAccountFooter)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .listRowBackground(Theme.Colors.surface)
        }
        // Every appearance re-reads: the player's one-time choice may have stored a Trainer while
        // Settings sat open on the Profile tab.
        .task {
            await trainerModel().load()
            focusAreas = (try? await services.userService.currentUser())?.profile.focusAreas ?? focusAreas
            reminderCount = await services.reminders.reminders().count
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.Colors.background)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        // US-AD04: the confirmation names exactly what is destroyed and warns that deleting the
        // account does not cancel an App Store subscription. The destructive button carries
        // `role: .destructive` so it renders red and is *not* the default; `.cancel` is. The message
        // names the Apple sign-in link only when this account used it (US-AD05), resolved before the
        // alert is presented. The warning is disclosure only: this path never mutates StoreKit state.
        .alert(
            "Delete your account?",
            isPresented: Binding(
                get: { deletion?.isConfirmationPresented ?? false },
                set: { deletion?.isConfirmationPresented = $0 }
            )
        ) {
            Button("Delete Account", role: .destructive) {
                if let deletion { Task { await deletion.confirmDeletion() } }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(deletion?.usedAppleCredential == true ? Self.confirmMessageApple : Self.confirmMessageLocal)
        }
        // US-SO01 (decision 13): sign out only after a plain confirmation. Confirming uploads first.
        .alert(
            Self.signOutConfirmTitle,
            isPresented: Binding(
                get: { signOut?.isConfirmationPresented ?? false },
                set: { signOut?.isConfirmationPresented = $0 }
            )
        ) {
            Button(Self.signOutTitle) {
                if let signOut { Task { await signOut.confirmSignOut() } }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(Self.signOutConfirmMessage)
        }
        // Decision 14: changes the upload could not save are lost only if the user says so. Cancel
        // changes nothing and leaves them signed in.
        .alert(
            Self.unsavedWarningTitle,
            isPresented: Binding(
                get: { signOut?.isUnsavedWarningPresented ?? false },
                set: { signOut?.isUnsavedWarningPresented = $0 }
            )
        ) {
            Button(Self.signOutAnywayTitle, role: .destructive) {
                if let signOut { Task { await signOut.signOut() } }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(Self.unsavedWarningMessage)
        }
        .alert(
            Self.signOutFailureTitle,
            isPresented: Binding(
                get: { signOut?.isFailureAlertPresented ?? false },
                set: { signOut?.isFailureAlertPresented = $0 }
            )
        ) {
            Button("Try Again") {
                if let signOut { Task { await signOut.signOut() } }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(Self.signOutFailureMessage)
        }
        // An honest failure surface: if the teardown throws, the routing reset (its last step) never
        // ran, so the user is still here and onboarded. Tell them deletion did not complete rather than
        // letting the confirmation dismiss silently. The teardown is idempotent, so "Try Again" is safe.
        .alert(
            "Couldn't delete your account",
            isPresented: Binding(
                get: { deletion?.isFailureAlertPresented ?? false },
                set: { deletion?.isFailureAlertPresented = $0 }
            )
        ) {
            Button("Try Again") {
                if let deletion { Task { await deletion.confirmDeletion() } }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(deletion?.failureMessage ?? Self.deleteFailureMessage)
        }
    }

    /// Whether a sign-out or an account deletion is under way, which holds both Account rows still.
    private var isAccountActionRunning: Bool {
        signOut?.isBusy == true || deletion?.isDeleting == true
    }

    /// The Sign Out row (US-SO01): plain, not destructive (decision 13). While the upload or the erase
    /// runs it says so with a spinner and takes no second tap.
    private var signOutRow: some View {
        let progress = Self.signOutProgress(signOut?.phase ?? .idle)
        return Button {
            signOutModel().signOutTapped()
        } label: {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .accessibilityHidden(true)
                Text(progress ?? Self.signOutTitle)
                    .font(Theme.Typography.body)
                    .foregroundStyle(progress == nil ? Theme.Colors.textPrimary : Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: Theme.Spacing.sm)
                if progress != nil {
                    ProgressView()
                        .accessibilityHidden(true)
                }
            }
            .frame(minHeight: Theme.Spacing.minTouchTarget)
            .contentShape(Rectangle())
        }
        .disabled(isAccountActionRunning)
        .accessibilityLabel(Self.signOutTitle)
        .accessibilityValue(progress ?? "")
        .accessibilityHint("Signs you out and removes your Rep Today data from this iPhone")
    }

    /// What the Sign Out row says while it works, or `nil` when it is idle.
    static func signOutProgress(_ phase: AccountSignOutViewModel.Phase) -> String? {
        switch phase {
        case .idle: return nil
        case .uploading: return "Saving your workouts\u{2026}"
        case .signingOut: return "Signing out\u{2026}"
        }
    }

    /// The Trainer row: the effective Trainer (or "Not chosen yet") as its value, opening a menu of the
    /// two Trainers. Choosing one writes it at once; the checkmark marks the stored Trainer.
    private var trainerRow: some View {
        let model = trainerSettings
        return Menu {
            ForEach(Trainer.allCases) { trainer in
                Button {
                    let model = trainerModel()
                    Task { await model.select(trainer) }
                } label: {
                    if model?.trainer == trainer {
                        Label(trainer.displayName, systemImage: "checkmark")
                    } else {
                        Text(trainer.displayName)
                    }
                }
            }
        } label: {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "figure.strengthtraining.functional")
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .accessibilityHidden(true)
                Text(TrainerChoiceCopy.settingsTitle)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Spacer(minLength: Theme.Spacing.sm)
                Text(model?.valueText ?? "")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
                Image(systemName: "chevron.up.chevron.down")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: Theme.Spacing.minTouchTarget)
            .contentShape(Rectangle())
        }
        .disabled(model?.isLoaded != true || model?.isSaving == true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(TrainerChoiceCopy.settingsTitle)
        .accessibilityValue(model?.valueText ?? "")
        .accessibilityHint("Choose who demonstrates each movement")
        .accessibilityAddTraits(.isButton)
    }

    /// The Apple Health suggestions switch (US-HO05). Turning it on records the choice and asks for read
    /// access to workouts at that moment; turning it off stops reading. HealthKit never says whether
    /// read access was granted, so the switch reflects the choice.
    private var healthSuggestionsBinding: Binding<Bool> {
        Binding(
            get: { appState.healthWorkoutSuggestionsEnabled },
            set: { enabled in
                appState.healthWorkoutSuggestionsEnabled = enabled
                if enabled {
                    Task { try? await services.healthKitService.requestWorkoutReadAuthorization() }
                }
            }
        )
    }

    static let healthToggleTitle = "Suggest Apple Health workouts"

    static let healthToggleFooter = """
        Focus areas get a bit more attention on their days. With Apple Health suggestions on, Rep Today \
        reads the workouts you record there, like runs and swims, and offers them on Today. Nothing is \
        logged until you tap Add it.
        """

    /// Builds the Trainer row's model on first use and caches it, like `deletionModel()`.
    private func trainerModel() -> TrainerSettingsViewModel {
        if let trainerSettings { return trainerSettings }
        let model = TrainerSettingsViewModel(userService: services.userService)
        trainerSettings = model
        return model
    }

    /// Builds the deletion view model on first use and caches it. `@State` cannot capture the
    /// environment at init, so it is created here from the live `services` and `AppState`.
    private func deletionModel() -> AccountDeletionViewModel {
        if let deletion { return deletion }
        let model = AccountDeletionViewModel(
            accountDeletionService: services.accountDeletionService,
            authService: services.authService,
            appState: appState
        )
        deletion = model
        return model
    }

    /// Builds the sign-out view model on first use and caches it, like `deletionModel()`.
    private func signOutModel() -> AccountSignOutViewModel {
        if let signOut { return signOut }
        let model = AccountSignOutViewModel(service: services.accountSignOutService, appState: appState)
        signOut = model
        return model
    }

    /// The one label the Sign Out control and its confirm button are known by - to a reader, to
    /// VoiceOver, and to the XCUITest that presses them.
    static let signOutTitle = "Sign Out"

    static let signOutConfirmTitle = "Sign out of Rep Today?"

    static let signOutConfirmMessage = """
        Your plan and workouts stay saved to your account. Signing out removes them from this iPhone \
        until you sign in again.
        """

    static let unsavedWarningTitle = "Recent workouts aren't saved"

    /// Decision 14: what is at stake, said plainly, and how to keep it.
    static let unsavedWarningMessage = """
        Your most recent workouts haven't been saved to your account yet, and signing out now will \
        lose them. To keep them, cancel and sign out once you're connected.
        """

    static let signOutAnywayTitle = "Sign Out Anyway"

    static let signOutFailureTitle = "Couldn't sign out"

    static let signOutFailureMessage = """
        Something went wrong and you may not be fully signed out. Please try again.
        """

    /// The Account section footer's first paragraph, shown with the Sign Out row.
    static let signOutFooter = """
        Signing out removes your Rep Today data from this iPhone. Your account keeps it, and it comes \
        back when you sign in again.
        """

    /// The one label the Delete Account control is known by - to a reader, to VoiceOver, and to the
    /// XCUITest that presses it (US-AD01) - so they cannot drift apart.
    static let deleteAccountTitle = "Delete Account"

    /// The section footer (US-AU05): the account, its server data, this device and the Rep Today data
    /// kept in the user's iCloud from before accounts. It does not assert a Sign in with Apple link;
    /// the confirmation names that only when it applies.
    static let deleteAccountFooter = """
        Permanently deletes your account, your profile and your workout history from Rep Today's \
        servers, this device and your iCloud. This can't be undone.
        """

    /// The confirmation body for an account that signed in with Apple (US-AD04/US-AD05): it names the
    /// Apple sign-in among what is removed, then preserves the shared subscription warning.
    static let confirmMessageApple = """
        This permanently deletes your Rep Today account, which you sign in to with Apple, and your \
        profile and workout history on Rep Today's servers, this device and your iCloud. This can't be \
        undone. Deleting your account does not cancel your App Store subscription.
        """

    /// The failure body for a teardown that stopped part-way on the device. Honest about what
    /// happened - the device teardown deletes durable records first and saves each step, so a
    /// late-step throw may already have removed some data - and points at the safe next action, since
    /// the teardown is idempotent and a retry completes it.
    static let deleteFailureMessage = """
        Something went wrong and your account may not be fully deleted. Please try again.
        """

    /// The failure body when deletion needs a connection: the request never left the phone, so nothing
    /// was deleted anywhere.
    static let deleteNeedsConnectionMessage = """
        Deleting your account needs a connection. Nothing was deleted - try again when you're online.
        """

    /// The failure body when there is no session the server accepts for the linked account, so it
    /// deleted nothing.
    static let deleteNeedsSignInMessage = """
        Sign in again from Profile > Account, then delete your account. Nothing was deleted.
        """

    /// The failure body when the server refused before marking anything because deletion is not
    /// available on it.
    static let deleteUnavailableMessage = """
        Account deletion isn't available right now. Nothing was deleted - please try again later.
        """

    /// The confirmation body for an account that signed in with Google or an email code.
    static let confirmMessageLocal = """
        This permanently deletes your Rep Today account and your profile and workout history on Rep \
        Today's servers, this device and your iCloud. This can't be undone. Deleting your account does \
        not cancel your App Store subscription.
        """

    /// The one label the toggle is known by - to a reader, to VoiceOver, and to the XCUITest suite
    /// that presses it - so the three cannot drift apart.
    static let toggleTitle = "Share anonymous usage data"

    /// What activating the switch *does*, which is what a VoiceOver hint is for. It deliberately
    /// does not restate `explanation`: that sentence is the section's footer, which VoiceOver reads
    /// once, and repeating it here would make the screen speak the whole paragraph twice in a row.
    /// State-neutral because the switch already vends its own on/off value.
    static let toggleHint = "Turns sharing anonymous usage data on or off"

    /// Honest and identity-framed, never dark-patterned: it says what is collected, what it is for,
    /// and what it is *not* tied to, without arguing the user out of turning it off.
    ///
    /// It renders as the Privacy section's **footer** - where iOS natively puts explanatory text,
    /// where VoiceOver reads it exactly once, and where it does not look like another tappable row.
    static let explanation = """
        Anonymous usage data helps us see whether Rep Today is working. It's counted against a \
        random per-install number - never your name, your email, or your device.
        """
}

#Preview {
    NavigationStack {
        SettingsView()
    }
    .environment(\.services, ServiceContainer.mock())
    .environment(AppState.preview(isOnboarded: true, selectedTab: .profile))
}
