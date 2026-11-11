import Foundation
import Observation

/// Backs the Welcome Page (US-HO01, decision 19): the tap-through moment on every cold launch that says
/// what today is before the user lands on Today.
///
/// It reads exactly what Today reads - the user, the full log history and the logged Outside Activities
/// - and asks the engine for today's plan and the Cycle strip, so the two screens can never disagree
/// about the day. Everything is best-effort: a failed read still greets the user and lets them through.
@MainActor
@Observable
final class WelcomeViewModel {

    /// The user's name, empty until loaded or when they gave none.
    private(set) var name = ""
    /// Today's plan, `nil` until loaded or when it could not be read.
    private(set) var plan: TrainingPlan?
    /// The Cycle strip: done, today, and still to come.
    private(set) var steps: [CycleStep] = []
    /// True once the load has finished, successfully or not.
    private(set) var isLoaded = false

    private let userService: any UserServiceProtocol
    private let workoutLogService: any WorkoutLogServiceProtocol
    private let outsideActivityService: any OutsideActivityServiceProtocol
    private let workoutEngine: any WorkoutEngineProtocol
    private let now: () -> Date
    private let calendar: Calendar

    init(
        userService: any UserServiceProtocol,
        workoutLogService: any WorkoutLogServiceProtocol,
        outsideActivityService: any OutsideActivityServiceProtocol,
        workoutEngine: any WorkoutEngineProtocol,
        now: @escaping () -> Date = { Date() },
        calendar: Calendar = .current
    ) {
        self.userService = userService
        self.workoutLogService = workoutLogService
        self.outsideActivityService = outsideActivityService
        self.workoutEngine = workoutEngine
        self.now = now
        self.calendar = calendar
    }

    convenience init(services: ServiceContainer) {
        self.init(
            userService: services.userService,
            workoutLogService: services.workoutLogService,
            outsideActivityService: services.outsideActivityService,
            workoutEngine: services.workoutEngine
        )
    }

    func load() async {
        defer { isLoaded = true }
        guard let user = try? await userService.currentUser() else { return }
        name = user.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let history = try? await workoutLogService.workoutLogs(from: nil, to: nil) else { return }
        let activities = (try? await outsideActivityService.activities(from: nil, to: nil)) ?? []
        let asOf = now()
        let lookback = calendar.date(byAdding: .day, value: -ReadyViewModel.recentLogLookbackDays, to: asOf)
        let recentLogs = lookback.map { start in history.filter { $0.completedAt >= start } } ?? history
        plan = try? await workoutEngine.trainingPlan(
            user: user,
            recentLogs: recentLogs,
            history: history,
            activities: activities,
            asOf: asOf
        )
        steps = (try? await workoutEngine.cycleSteps(
            user: user,
            recentLogs: recentLogs,
            history: history,
            activities: activities,
            asOf: asOf
        )) ?? []
    }

    /// "Good morning, Sam." - by the hour of the local clock, with the name when there is one.
    var greeting: String {
        let salutation = WelcomeCopy.salutation(forHour: calendar.component(.hour, from: now()))
        return name.isEmpty ? "\(salutation)." : "\(salutation), \(name)."
    }

    /// "Push Day", "Rest Day", or a neutral line before the plan is known.
    var dayTitle: String {
        switch plan {
        case let .train(day)?: return day.displayName
        case .rest?: return "Rest Day"
        case nil: return WelcomeCopy.fallbackTitle
        }
    }

    /// What the day holds, in the user's words.
    var dayDetail: String {
        switch plan {
        case let .train(day)?: return day.focusLine
        case let .rest(next, isEarly)?: return isEarly ? WelcomeCopy.earlyRest(covering: next) : WelcomeCopy.rest
        case nil: return WelcomeCopy.fallbackDetail
        }
    }
}

/// The Welcome Page's copy, one source for the page and the tests that pin it. Identity-framed: no
/// streaks, no guilt.
enum WelcomeCopy {
    static let fallbackTitle = "Today"
    static let fallbackDetail = "Your session is ready when you are."
    static let rest = "You trained Push, Pull and Legs. Rest is part of the program."
    static let letsGo = "Let's go"
    static let stripTitle = "This cycle"

    static func earlyRest(covering day: TrainingDay) -> String {
        "Your outside workout covered \(day.groupName), so rest comes early."
    }

    static func salutation(forHour hour: Int) -> String {
        switch hour {
        case 4..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<24: return "Good evening"
        default: return "Hello"
        }
    }
}

extension TrainingDay {
    /// The group's short name, as a sentence uses it: "Push", "Pull", "Legs".
    var groupName: String {
        switch self {
        case .push: return "Push"
        case .pull: return "Pull"
        case .legs: return "Legs"
        }
    }
}
