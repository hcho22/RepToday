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
    /// Today's choices (M4): a rest the user chose, or training on a Rest Day, shows here as on Today.
    private let todayChoices: (any TodayChoicesStoring)?
    private let now: () -> Date
    private let calendar: Calendar

    init(
        userService: any UserServiceProtocol,
        workoutLogService: any WorkoutLogServiceProtocol,
        outsideActivityService: any OutsideActivityServiceProtocol,
        workoutEngine: any WorkoutEngineProtocol,
        todayChoices: (any TodayChoicesStoring)? = nil,
        now: @escaping () -> Date = { Date() },
        calendar: Calendar = .current
    ) {
        self.userService = userService
        self.workoutLogService = workoutLogService
        self.outsideActivityService = outsideActivityService
        self.workoutEngine = workoutEngine
        self.todayChoices = todayChoices
        self.now = now
        self.calendar = calendar
    }

    convenience init(services: ServiceContainer) {
        self.init(
            userService: services.userService,
            workoutLogService: services.workoutLogService,
            outsideActivityService: services.outsideActivityService,
            workoutEngine: services.workoutEngine,
            todayChoices: services.todayChoices
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
        let rotation = try? await workoutEngine.trainingPlan(
            user: user,
            recentLogs: recentLogs,
            history: history,
            activities: activities,
            asOf: asOf
        )
        let choices = todayChoices?.choices(on: TodayChoices.dayKey(for: asOf, calendar: calendar))
        plan = rotation.map { choices?.applied(to: $0) ?? $0 }
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

    /// "Push Day", "Rest Day", "Day Off", or a neutral line before the plan is known.
    var dayTitle: String {
        switch plan {
        case let .train(day)?: return day.displayName
        case let .rest(_, reason)?: return WelcomeCopy.restTitle(for: reason)
        case nil: return WelcomeCopy.fallbackTitle
        }
    }

    /// What the day holds, in the user's words.
    var dayDetail: String {
        switch plan {
        case let .train(day)?: return day.focusLine
        case .rest(_, .cycleComplete)?: return WelcomeCopy.rest
        case let .rest(next, reason)?: return WelcomeCopy.restReason(reason, next: next)
        case nil: return WelcomeCopy.fallbackDetail
        }
    }
}

/// The Welcome Page's copy, one source for the page and the tests that pin it. Identity-framed: no
/// streaks, no guilt.
enum WelcomeCopy {
    static let fallbackTitle = "Today"
    static let fallbackDetail = "Your session is ready when you are."
    static let cycleComplete = "You trained Push, Pull and Legs."
    static let rest = "\(cycleComplete) Rest is part of the program."
    static let letsGo = "Let's go"
    static let stripTitle = "This cycle"

    /// "Rest Day" for the Cycle's Rest Day, "Day Off" for a day off an Outside Activity gave.
    static func restTitle(for reason: RestReason) -> String {
        if case .workedOutside = reason { return "Day Off" }
        return "Rest Day"
    }

    /// Why today holds no Training Day, in one sentence. `next` is the group "Train anyway" starts.
    static func restReason(_ reason: RestReason, next: TrainingDay) -> String {
        switch reason {
        case .cycleComplete: return cycleComplete
        case .early: return earlyRest(covering: next)
        case let .workedOutside(groups, today): return workedOutside(groups, today: today)
        case .chosen: return chosenRest(next: next)
        }
    }

    /// Resting on a Training Day by choice: "You're resting today. Your Push Day is ready when you are."
    static func chosenRest(next: TrainingDay) -> String {
        "You're resting today. Your \(next.displayName) is ready when you are."
    }

    static func earlyRest(covering day: TrainingDay) -> String {
        "Your outside workout covered \(day.groupName), so rest comes early."
    }

    /// "You worked Legs outside today, so it gets a day off." or, for an earlier workout, "Your outside
    /// workout worked Legs, so it gets a day off."
    static func workedOutside(_ groups: [TrainingDay], today: Bool) -> String {
        let names = groups.map(\.groupName)
        let joined = names.count > 1 ? names.dropLast().joined(separator: ", ") + " and " + names[names.count - 1] : names.joined()
        let dayOff = groups.count > 1 ? "they get a day off" : "it gets a day off"
        if today { return "You worked \(joined) outside today, so \(dayOff)." }
        return "Your outside \(groups.count > 1 ? "workouts" : "workout") worked \(joined), so \(dayOff)."
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
