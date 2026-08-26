import Foundation
import Observation

/// The top-level app routes controlled by `AppState`.
enum AppTab: String, CaseIterable, Identifiable {
    case home
    case progress
    case profile

    var id: String { rawValue }
}

/// Small, persisted app state for routing, anonymous install identity, and telemetry consent.
///
/// `isOnboarded` chooses between onboarding and the main tabs. `selectedTab` restores the
/// user's last main-tab context. This uses the Observation framework (`@Observable`).
///
/// `analyticsEnabled` (US-T06) is the user's opt-out flag: on by default, turned off from the
/// Settings screen, and the value the telemetry transport's gate reads on every emission.
///
/// It is also the home of the anonymous per-install identity the funnel is cohorted by
/// (US-T05): `installId`, `firstLaunchAt`, and `lastActiveAt`. `installId` is a random UUIDv4
/// minted on first launch and kept only in `UserDefaults` - it is deliberately **not** derived
/// from the IDFA, `identifierForVendor`, the Sign in with Apple identifier, or an email, and it is
/// deliberately **not** stored in the Keychain: a Keychain item survives a plain uninstall with
/// no restore involved and would resurrect an identity the user believed they deleted.
/// `UserDefaults` is much weaker than that, which is the point - but it is not nothing:
/// `Library/Preferences` is included in iCloud and iTunes backups and in device-to-device
/// transfer, so the guarantee is that the id dies with the app *absent a backup restore*, and
/// one id can end up live on two devices after a migration. A plain reinstall is a new install
/// with a new id.
///
/// The clock, the calendar, and the id generator are injected (`now`, `calendar`,
/// `newInstallId`), so cohorting behaviour is pinnable in tests without reading the wall clock
/// or the device's locale inline.
@Observable
final class AppState {
    var isOnboarded: Bool {
        didSet {
            userDefaults.set(isOnboarded, forKey: Keys.isOnboarded)
        }
    }

    var selectedTab: AppTab {
        didSet {
            userDefaults.set(selectedTab.rawValue, forKey: Keys.selectedTab)
        }
    }

    /// One-shot, **never-persisted** UI flag set by the account-deletion flow (US-AD05) when the
    /// deleted account used Sign in with Apple, so `RootView` can surface the "also stop using your
    /// Apple ID in Settings" guidance *after* the teardown has routed back to onboarding - a point
    /// where the Settings screen that triggered it has already been torn down, so the alert has to be
    /// hosted somewhere that survives the transition. Deliberately not written to `UserDefaults` (no
    /// `didSet`): it is transient guidance, reset to `false` the moment it is dismissed, and it starts
    /// `false` on every launch. It gates emission of nothing and cohorts nothing.
    var showAppleSignOutGuidance: Bool = false

    /// The opt-out consent flag (US-T06): `true` means anonymous usage data may be emitted.
    ///
    /// Telemetry is on by default and turned off from Settings, so this is the *user's* copy of the
    /// gate `LiveAnalyticsService` reads on every emission. Writing it persists immediately, and the
    /// transport re-reads `UserDefaults` per event, so a toggle takes effect with no app restart.
    ///
    /// Nothing here clears `installId`: this flag gates emission only. Adding a "reset telemetry
    /// identity" control would put an install into the re-minted-identity state US-T07 has to decide
    /// about first, and that story's criteria forbid pre-empting it.
    var analyticsEnabled: Bool {
        didSet {
            userDefaults.set(analyticsEnabled, forKey: AppState.analyticsEnabledKey)
        }
    }

    /// One-shot flag for the continuous-circuit first-run explainer (US-CC13): `true` once the user
    /// has seen the one-time introduction to the self-driving player. Persisted so the explainer is
    /// shown at most once ever, surviving relaunch (and - like the rest of `AppState` - a backup
    /// restore). Defaults to unseen: unlike the opt-out flag, absent means "not yet seen", which is
    /// exactly what `bool(forKey:)` answers for a never-written key, so no `object(forKey:)` guard is
    /// needed. It gates presentation only - it cohorts nothing and emits nothing.
    var hasSeenContinuousCircuitExplainer: Bool {
        didSet {
            userDefaults.set(hasSeenContinuousCircuitExplainer, forKey: Keys.hasSeenContinuousCircuitExplainer)
        }
    }

    /// Whether the continuous-circuit explainer should be presented on this arrival at the player -
    /// the read side of the one-shot flag, so a call site never has to remember to negate it.
    var shouldShowContinuousCircuitExplainer: Bool { !hasSeenContinuousCircuitExplainer }

    /// Records that the explainer has been shown, flipping the one-shot flag so it is never presented
    /// again. Idempotent: calling it twice is a persisted no-op the second time.
    func markContinuousCircuitExplainerSeen() {
        hasSeenContinuousCircuitExplainer = true
    }

    /// The highest `Phase` the user has been *congratulated for reaching* (US-SP06, the graduation
    /// moment). Persisted, and compared against the phase the `PhaseEvaluator` currently reports as
    /// *earned* so the one-time reveal fires exactly at the crossing into `.strength` and never again.
    ///
    /// It is deliberately a **last-celebrated** phase rather than a last-*seen* one: it is only ever
    /// advanced (ratcheted) when the reveal is actually shown, never rewritten to whatever the current
    /// earned phase happens to be on a given open. So a user whose earned phase later dips back to
    /// `.discipline` (the score is a rolling average, and it can fall) is never re-congratulated when it
    /// climbs again - the milestone is stewardship of a habit, celebrated once, never a reward that can
    /// be lost and re-won. Defaults to `.discipline` (the phase every user starts in), which is exactly
    /// what an unwritten key resolves to below, so a fresh install has celebrated nothing.
    ///
    /// This never touches the engine: the reveal keys off the *computed* earned phase, not off the
    /// persisted `user.phase` (which the engine reads and which no production path advances to
    /// `.strength` today). It gates presentation only - it cohorts nothing and emits nothing.
    var lastCelebratedPhase: Phase {
        didSet {
            userDefaults.set(lastCelebratedPhase.rawValue, forKey: Keys.lastCelebratedPhase)
        }
    }

    /// Whether the Strength-Phase graduation reveal has already been shown - the read side of the
    /// one-shot flag (US-SP06), so a call site never re-derives the comparison. Mirrors
    /// `hasSeenContinuousCircuitExplainer`.
    var hasCelebratedStrengthGraduation: Bool { lastCelebratedPhase == .strength }

    /// Records that the Strength-Phase graduation reveal has been shown, ratcheting the celebrated
    /// phase to `.strength` so it is never presented again. Idempotent: calling it twice is a persisted
    /// no-op the second time.
    func markStrengthGraduationCelebrated() {
        lastCelebratedPhase = .strength
    }

    /// The anonymous per-install identifier: a random UUIDv4, minted on first launch and preserved
    /// by every relaunch that still finds it on disk. A missing or empty stored id is re-minted -
    /// the id is the half of the identity that gets replaced, while a recorded origin is the half
    /// that survives. Never an identity, never a device id.
    let installId: String

    /// When this install was first opened, or `nil` when that moment is genuinely unrecoverable.
    /// Written once and never moved again, so it is the stable origin the install cohort is
    /// measured from.
    ///
    /// It is `nil` for an install that already existed before this build shipped and has no origin
    /// recorded on disk: such a launch mints an id but has no honest first-launch date, and the
    /// upgrade date is not one. A plausible-looking date would eventually be read without its
    /// caveat and would cohort the install into the week it upgraded, so the unknown is modelled
    /// as an unknown and every consumer has to decide what to do with it. A recorded origin is
    /// never discarded, though - re-minting the id does not throw the origin away with it.
    let firstLaunchAt: Date?

    /// The most recent **cold** launch. `init` is the only thing that writes it, and `AppState` is
    /// constructed once per process, so a resume from the background does not move it - and iOS
    /// resumes a suspended app far more often than it cold-launches one, so this can lag real usage
    /// by days. It is a settable `var` matching `isOnboarded`/`selectedTab`, which means a
    /// foreground update *could* move it, but nothing wires one today and no story owns doing so;
    /// nothing reads the value either. Read it as "last cold launch" until that changes.
    var lastActiveAt: Date {
        didSet {
            userDefaults.set(lastActiveAt, forKey: Keys.lastActiveAt)
        }
    }

    /// The `lastActiveAt` the previous cold launch left behind, or `nil` when there was none.
    ///
    /// Nothing reads this today. It exists because `init` overwrites the persisted value with
    /// this launch's open time, so without a snapshot taken here the previous one is destroyed
    /// at construction and is unrecoverable for the life of the process - the app pays to write
    /// the value on every launch and would then keep nothing readable from it.
    let previousActiveAt: Date?

    /// True only for the launch that first opened this install. This is the one moment the fact
    /// is knowable - once `init` returns, a first launch and a relaunch look alike - so it is
    /// captured here for the `app_install` emission that lands in US-T07. It is true only when
    /// this launch stamped the origin itself: an install that existed before this build shipped,
    /// or one whose origin was already on disk, mints an id without this being true - that is a
    /// new identity, not a new install.
    let isFirstLaunch: Bool

    /// The coarse install cohort: the start of the week `firstLaunchAt` fell in, through the same
    /// `ConsistencyScore.startOfWeek(_:_:)` the Consistency Score uses - the same week *math*,
    /// handed a different calendar (see `cohortCalendar`). Deliberately a week boundary and never
    /// a precise install time, so the cohort carries no timing fingerprint. `nil` exactly when
    /// `firstLaunchAt` is.
    var installWeek: Date? {
        firstLaunchAt.map { ConsistencyScore.startOfWeek($0, calendar) }
    }

    /// The calendar the install cohort is bucketed in: Gregorian, Sunday-start, pinned to
    /// Pacific time. It is pinned rather than read from the device because `install_week` is
    /// grouped **across** users server-side, and a week boundary that follows each device's
    /// `firstWeekday` and time zone would put two installs from the same real week into
    /// different buckets. Pacific rather than UTC because a UTC boundary lands mid-Saturday
    /// afternoon Pacific and would push a Saturday-evening install into the following week.
    ///
    /// The on-device Consistency Score deliberately stays on `Calendar.current`: a user's own
    /// training week is their local week, and unifying the two would break one of them. Change
    /// this constant, not that one - US conventions are a "for now" choice, and this is the one
    /// place it moves.
    static let cohortCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 1
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles") ?? TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    /// The `UserDefaults` key the opt-out flag lives under (US-T06).
    ///
    /// This is the one key here that is not private, because three things have to agree on it by
    /// name: this object, the telemetry transport's gate (`analyticsGate`, read fresh per emission
    /// rather than through an `AppState` instance the container has no handle on), and the XCUITest
    /// launch argument `-AppState.analyticsEnabled NO`. `UserDefaults` reads the argument domain
    /// ahead of the persisted one, so that argument needs no plumbing beyond a shared key - it is
    /// the only mechanism that can reach an app launched out of process.
    static let analyticsEnabledKey = "AppState.analyticsEnabled"

    /// Reads the opt-out flag the way every consumer must read it.
    ///
    /// **Absent is not off.** `bool(forKey:)` answers `false` for a key that was never written, so a
    /// naive read would ship every fresh install opted *out* while looking like it defaults to on.
    /// Absence is therefore checked first and answered with the shipped default (`true`), and only a
    /// value that is actually present is coerced - which is also what lets the launch argument work,
    /// since the argument domain stores `NO` as a *string* that `object(forKey:)` sees and
    /// `bool(forKey:)` reads as false.
    ///
    /// One consequence worth naming: a launch argument outranks the persisted value permanently, so
    /// a run launched with `-AppState.analyticsEnabled NO` stays off even if the Settings toggle is
    /// flipped on during it. That is right for a test harness pinning a state, and unreachable in
    /// production, where nothing passes launch arguments.
    static func isAnalyticsEnabled(in userDefaults: UserDefaults = .standard) -> Bool {
        guard userDefaults.object(forKey: analyticsEnabledKey) != nil else { return true }
        return userDefaults.bool(forKey: analyticsEnabledKey)
    }

    /// The opt-out gate as `LiveAnalyticsService` holds it: a closure re-read on every emission, so
    /// turning telemetry off in Settings takes effect on the next event rather than the next launch.
    ///
    /// It captures a `UserDefaults`, never an `AppState`: `ServiceContainer.live(...)` is built from
    /// an install id and not from the state object, and a captured object would also make the gate
    /// outlive whatever built it. Which store it reads is *handed in* rather than assumed, so the
    /// reader here and the writer in `analyticsEnabled`'s `didSet` are bound to the same instance by
    /// construction instead of by both happening to name `.standard`. `RepTodayApp.init()` passes the
    /// store its own `AppState` was built on, exactly as it passes `installId` down rather than
    /// letting a second path re-derive it.
    static func analyticsGate(in userDefaults: UserDefaults = .standard) -> @Sendable () -> Bool {
        let store = SendableUserDefaults(wrapped: userDefaults)
        return { isAnalyticsEnabled(in: store.wrapped) }
    }

    /// This instance's gate: the same reader, bound to the very store this `AppState` persists the
    /// flag to. This is what production hands the container, so the toggle the user sees and the
    /// gate the transport asks cannot read different stores.
    var analyticsGate: @Sendable () -> Bool { AppState.analyticsGate(in: userDefaults) }

    /// The store the app-entry telemetry dedup state lives in: the very store this `AppState`
    /// reads its identity (`firstLaunchAt`, `installWeek`) from. `RepTodayApp.init()` hands this to
    /// `AppEntryTelemetry.eventsForLaunch(...)` instead of naming `.standard` again, so the day-7 /
    /// day-30 emit-once flags and the origin they window off cannot be stranded in different stores.
    /// Production resolves to `.standard` because that is the store production's `AppState` is built
    /// on; if that ever moves (an app-group suite, say), the dedup flags move with the identity by
    /// construction rather than being left behind.
    var telemetryDefaults: UserDefaults { userDefaults }

    @ObservationIgnored private let userDefaults: UserDefaults
    @ObservationIgnored private let calendar: Calendar

    /// - Parameter userDefaults: The store this state reads and writes, and - through
    ///   `analyticsGate` - the store the telemetry gate reads. Production leaves it at `.standard`,
    ///   which is load-bearing for the out-of-process opt-out proof: `NSArgumentDomain` sits at the
    ///   head of `UserDefaults.standard`'s search list, which is what lets the XCUITest launch
    ///   argument `-AppState.analyticsEnabled NO` close the gate in an app the test process never
    ///   built. Moving this off `.standard` (an app-group suite for a widget or extension, say) is
    ///   therefore not a free change: verify the argument domain is still reachable through the new
    ///   store first, or that override silently stops working.
    init(
        userDefaults: UserDefaults = .standard,
        now: () -> Date = Date.init,
        calendar: Calendar = AppState.cohortCalendar,
        newInstallId: () -> String = { UUID().uuidString }
    ) {
        self.userDefaults = userDefaults
        self.calendar = calendar
        let wasOnboarded = userDefaults.bool(forKey: Keys.isOnboarded)
        isOnboarded = wasOnboarded

        let savedTab = userDefaults.string(forKey: Keys.selectedTab)
        selectedTab = savedTab.flatMap(AppTab.init(rawValue:)) ?? .home

        // Telemetry is opt-*out*, so an install that has never answered is on. See
        // `isAnalyticsEnabled(in:)` for why that cannot be a plain `bool(forKey:)`.
        analyticsEnabled = AppState.isAnalyticsEnabled(in: userDefaults)

        // Unseen by default: a never-written key reads `false`, which is the honest "not yet seen".
        hasSeenContinuousCircuitExplainer = userDefaults.bool(forKey: Keys.hasSeenContinuousCircuitExplainer)

        // Nothing celebrated by default: an absent key resolves to `.discipline`, the phase every user
        // starts in, so a fresh install has congratulated nothing and the reveal can still fire once
        // the earned phase first crosses into `.strength` (US-SP06).
        lastCelebratedPhase = userDefaults.string(forKey: Keys.lastCelebratedPhase)
            .flatMap(Phase.init(rawValue:)) ?? .discipline

        let openedAt = now()
        previousActiveAt = userDefaults.object(forKey: Keys.lastActiveAt) as? Date

        // The id and its origin are resolved together, but they are not all-or-nothing: a missing
        // or empty id is re-minted, while a stored origin is kept whenever there is one. An origin
        // that survived is still the week this install really began, and discarding it would
        // cohort the install against a week it did not install in - which is the thing the rule
        // exists to prevent, not something it should cause. The origin falls back to unknown only
        // when none is usable, and that unknown is recorded as a marker written beside the id, so
        // the three states (a first launch, an install with no usable origin, and a relaunch of
        // either) stay distinguishable across launches.
        let storedId = userDefaults.string(forKey: Keys.installId)
        let storedFirstLaunch = userDefaults.object(forKey: Keys.firstLaunchAt) as? Date
        let storedFirstLaunchUnknown = userDefaults.bool(forKey: Keys.firstLaunchUnknown)
        if let storedId, !storedId.isEmpty, storedFirstLaunch != nil || storedFirstLaunchUnknown {
            installId = storedId
            firstLaunchAt = storedFirstLaunch
            isFirstLaunch = false
        } else {
            // An install that is already onboarded but carries no id existed before this build
            // shipped: it is a new identity on an old install, so with no origin on disk its true
            // first launch is gone and the upgrade date is not a stand-in for it. The residual,
            // accepted rather than chased: someone who installed an earlier build and never
            // finished onboarding still reads as a fresh install here.
            let isPreExistingInstall = wasOnboarded
            installId = newInstallId()
            firstLaunchAt = storedFirstLaunch ?? (isPreExistingInstall ? nil : openedAt)
            isFirstLaunch = storedFirstLaunch == nil && !isPreExistingInstall
            userDefaults.set(installId, forKey: Keys.installId)
            if let firstLaunchAt {
                userDefaults.set(firstLaunchAt, forKey: Keys.firstLaunchAt)
                userDefaults.removeObject(forKey: Keys.firstLaunchUnknown)
            } else {
                userDefaults.removeObject(forKey: Keys.firstLaunchAt)
                userDefaults.set(true, forKey: Keys.firstLaunchUnknown)
            }
        }

        // `didSet` does not fire during `init`, so this launch's open time is written through.
        lastActiveAt = openedAt
        userDefaults.set(openedAt, forKey: Keys.lastActiveAt)
    }

    static func preview(isOnboarded: Bool = false, selectedTab: AppTab = .home) -> AppState {
        let appState = AppState(userDefaults: .preview)
        appState.isOnboarded = isOnboarded
        appState.selectedTab = selectedTab
        return appState
    }

    /// The persisted keys. The opt-out flag's key is deliberately *not* here - it is
    /// `AppState.analyticsEnabledKey`, non-private because the telemetry gate and the XCUITest
    /// launch argument both name it.
    private enum Keys {
        static let isOnboarded = "AppState.isOnboarded"
        static let selectedTab = "AppState.selectedTab"
        static let installId = "AppState.installId"
        static let firstLaunchAt = "AppState.firstLaunchAt"
        static let firstLaunchUnknown = "AppState.firstLaunchUnknown"
        static let lastActiveAt = "AppState.lastActiveAt"
        static let hasSeenContinuousCircuitExplainer = "AppState.hasSeenContinuousCircuitExplainer"
        static let lastCelebratedPhase = "AppState.lastCelebratedPhase"
    }
}

/// Carries a `UserDefaults` into the `@Sendable` telemetry gate.
///
/// The gate is `@Sendable` because the transport reads it from a detached task, and `UserDefaults`
/// is thread-safe by documentation but carries no `Sendable` conformance. The box is what makes that
/// gap an explicit, one-line assertion here rather than a warning at every capture site.
private struct SendableUserDefaults: @unchecked Sendable {
    let wrapped: UserDefaults
}

private extension UserDefaults {
    static let preview: UserDefaults = {
        let defaults = UserDefaults(suiteName: "RepToday.Preview") ?? .standard
        defaults.removePersistentDomain(forName: "RepToday.Preview")
        return defaults
    }()
}
