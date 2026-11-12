import Foundation
@testable import RepToday

/// The one way the Coach suites build a `CoachViewModel` (M4): a scripted `MockCoachService`, an
/// in-memory entitlement, and in-memory stores for everything a confirmed proposal writes - so a test
/// reads back exactly what an action changed, and nothing reaches a network or a real notification.
@MainActor
struct CoachFixture {
    let coach: MockCoachService
    let entitlements: MockPremiumEntitlementService
    let subscription: MockSubscriptionService
    let authority: PremiumSessionAuthority
    let userService: MockUserService
    let workoutLogService: MockWorkoutLogService
    let outsideActivityService: InMemoryOutsideActivityService
    let todayChoices: InMemoryTodayChoicesStore
    let scheduler: RecordingReminderNotificationScheduler
    let reminders: CoachReminderService
    let customWorkouts: InMemoryCustomWorkoutService
    let exerciseService: MockExerciseService
    let defaults: UserDefaults
    let viewModel: CoachViewModel

    /// The fixed moment every fixture runs at: noon on 2026-11-11, local time.
    nonisolated static let now: Date = {
        var components = DateComponents()
        components.year = 2026
        components.month = 11
        components.day = 11
        components.hour = 12
        return Calendar.current.date(from: components) ?? Date(timeIntervalSinceReferenceDate: 0)
    }()

    nonisolated static var today: String { TodayChoices.dayKey(for: now) }

    init(
        coach: MockCoachService = MockCoachService(now: { CoachFixture.now }),
        premium: Bool = true,
        subscription: Subscription = .free,
        user: User? = MockPersistence.sampleUser,
        notifications: NotificationPermission = .notDetermined,
        grantsNotifications: Bool = true,
        consent: Bool = true
    ) {
        self.coach = coach
        entitlements = MockPremiumEntitlementService(premium: premium)
        self.subscription = MockSubscriptionService(subscription: subscription)
        authority = PremiumSessionAuthority()
        userService = MockUserService(user: user)
        workoutLogService = MockWorkoutLogService()
        outsideActivityService = InMemoryOutsideActivityService()
        todayChoices = InMemoryTodayChoicesStore()
        scheduler = RecordingReminderNotificationScheduler(permission: notifications, grantsOnRequest: grantsNotifications)
        let suite = "CoachFixture.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        reminders = CoachReminderService(defaults: defaults, scheduler: scheduler)
        customWorkouts = InMemoryCustomWorkoutService()
        exerciseService = try! MockExerciseService()
        let engine = OnDeviceWorkoutEngine(exerciseService: exerciseService)
        let policyService = MockSessionPolicyService()
        viewModel = CoachViewModel(
            coach: coach,
            entitlements: entitlements,
            subscriptionService: self.subscription,
            premiumAuthority: authority,
            applier: CoachProposalApplier(
                userService: userService,
                outsideActivityService: outsideActivityService,
                todayChoices: todayChoices,
                reminders: reminders,
                customWorkouts: customWorkouts,
                planInputsChanged: {},
                now: { CoachFixture.now }
            ),
            today: CoachTodayReader(
                userService: userService,
                workoutLogService: workoutLogService,
                outsideActivityService: outsideActivityService,
                sessionPolicyService: policyService,
                workoutEngine: engine,
                todayChoices: todayChoices,
                now: { CoachFixture.now }
            ),
            customWorkouts: customWorkouts,
            userService: userService,
            exerciseService: exerciseService,
            now: { CoachFixture.now }
        )
        if consent { viewModel.grantDataSharingConsent() }
    }

    /// A Coach reply carrying one proposal.
    nonisolated static func proposal(_ action: CoachProposal.Action, id: String = UUID().uuidString.lowercased()) -> CoachProposal {
        CoachProposal(id: id, status: .proposed, action: action)
    }

    /// A short Custom Workout draft: one catalog movement, one text-only step.
    nonisolated static let draft = CustomWorkoutDraft(
        title: "Desk Reset",
        note: "A short circuit to undo a day of sitting.",
        steps: [
            .init(name: "Incline Push-Up", exerciseId: "push_incline", sets: 3, reps: 10, seconds: nil, perSide: false, restSeconds: 30),
            .init(name: "Doorway Chest Opener", exerciseId: nil, sets: 2, reps: nil, seconds: 30, perSide: false, restSeconds: 15),
        ]
    )
}
