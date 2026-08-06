import Foundation

/// The app-entry telemetry decision (US-T07): given a launch's identity fields, a clock, and the
/// emit-once dedup store, it returns the events this launch should emit and stamps the return-event
/// dedup flags as it decides to emit them. Pure apart from the two `UserDefaults` writes it is
/// explicitly handed a store for, so the whole window/dedup behaviour is deterministic under an
/// injected clock rather than a wall-clock read (the story's "never a raw `Date()` inline" criterion).
///
/// **It is the funnel decision, not the consent decision.** Whether an event is *sent* is the sink's
/// property - `LiveAnalyticsService.record(_:)` reads the opt-out gate per emission - so
/// `RepTodayApp.init()` hands every event this returns straight to `record(_:)` and never re-checks
/// consent (a second gate could disagree with the first). One consequence follows and is accepted
/// rather than worked around: a return event's dedup flag is stamped here on the *decision*, so an
/// install that reaches a return window while opted out has the send dropped by the gate and the flag
/// set anyway - it will not re-attempt on a later launch even if consent is turned back on. That
/// matches the schema's stated constraint that an opted-out install is simply absent from the plane,
/// and it keeps emit-once meaning "attempted at most once" rather than "retried every launch in the
/// window until it lands".
///
/// **The three events and their exact rules** (`gtm/06-channels/event-metric-schema.md`, US-T07):
/// - `app_install`: exactly once, iff `isFirstLaunch` - the one launch that stamped the origin itself
///   (`AppState.isFirstLaunch`). Both US-T05 edge cases fall out of that single rule: an unknown-origin
///   pre-existing install (`isFirstLaunch == false`, no origin) emits nothing, so the upgrade date
///   never fabricates a cohort; and a re-minted identity beside a surviving origin
///   (`isFirstLaunch == false`, origin intact) also emits no `app_install`, so one physical device is
///   not double-counted under two identifiers. It carries only `install_week`.
/// - `day7_return` / `day30_return`: at most once each, on any open during days 7-13 / 30-36 inclusive
///   after `firstLaunchAt`, deduped by a persisted flag. They carry no properties, and they never fire
///   when `firstLaunchAt == nil` - there is no honest window origin to measure from, which is the
///   other half of why the unknown-origin install emits nothing at all.
enum AppEntryTelemetry {

    /// The dedup keys the return events are emitted-once by. Stored alongside the US-T05 identity in
    /// whatever store the caller hands in (production: `.standard`, the same store `AppState` writes).
    static let day7EmittedKey = "Telemetry.day7Return.emitted"
    static let day30EmittedKey = "Telemetry.day30Return.emitted"

    /// One return event's window: the inclusive day range after `firstLaunchAt` it fires in, and the
    /// `UserDefaults` flag that makes it fire at most once. Days are counted as whole elapsed days, so
    /// `7...13` is the half-open real-time interval `[7 days, 14 days)` after the origin.
    private struct ReturnWindow {
        let name: AnalyticsEventName
        let days: ClosedRange<Int>
        let emittedKey: String
    }

    private static let returnWindows: [ReturnWindow] = [
        ReturnWindow(name: .day7Return, days: 7...13, emittedKey: day7EmittedKey),
        ReturnWindow(name: .day30Return, days: 30...36, emittedKey: day30EmittedKey)
    ]

    /// The events to emit for this launch, in the order `app_install` then any return event. Return
    /// dedup flags are written to `defaults` as part of the decision (see the type's note on consent).
    ///
    /// - Parameters:
    ///   - isFirstLaunch: `AppState.isFirstLaunch` - true only for the launch that stamped the origin.
    ///   - firstLaunchAt: `AppState.firstLaunchAt` - the stable install origin, or `nil` when it is
    ///     genuinely unrecoverable (a pre-existing install with no recorded origin).
    ///   - installWeek: `AppState.installWeek` - the coarse cohort week-start, `nil` exactly when
    ///     `firstLaunchAt` is.
    ///   - now: the injected clock. Production passes one `Date()` read at the entry point; tests pin it.
    ///   - defaults: the emit-once dedup store.
    static func eventsForLaunch(
        isFirstLaunch: Bool,
        firstLaunchAt: Date?,
        installWeek: Date?,
        now: Date,
        defaults: UserDefaults
    ) -> [AnalyticsEvent] {
        var events: [AnalyticsEvent] = []
        let timestampMs = Int(now.timeIntervalSince1970 * 1000)

        // `app_install` keys off `isFirstLaunch` alone. The `installWeek` unwrap is belt-and-braces:
        // a genuine first launch always has one (it stamped the origin this launch), so a missing
        // week here would be an `AppState` invariant break, not a state to emit a blank cohort for.
        if isFirstLaunch, let installWeek {
            events.append(
                AnalyticsEvent(
                    name: .appInstall,
                    timestampMs: timestampMs,
                    properties: ["install_week": .string(installWeekString(installWeek))]
                )
            )
        }

        // The return windows need an origin to measure from; with none, they cannot fire honestly.
        if let firstLaunchAt {
            let elapsedDays = Int(now.timeIntervalSince(firstLaunchAt) / secondsPerDay)
            for window in returnWindows where window.days.contains(elapsedDays) {
                guard !defaults.bool(forKey: window.emittedKey) else { continue }
                events.append(AnalyticsEvent(name: window.name, timestampMs: timestampMs))
                defaults.set(true, forKey: window.emittedKey)
            }
        }

        return events
    }

    private static let secondsPerDay: TimeInterval = 86_400

    /// The wire encoding of `install_week`: a coarse `yyyy-MM-dd` week-start string.
    ///
    /// `AnalyticsValue` has no date case, so US-T05 deferred this to whichever story first put a week
    /// into a property bag. A `yyyy-MM-dd` week-start is the coarse encoding the story chose: it is a
    /// week boundary, never a precise install time (a precise timestamp is a stated failure indicator),
    /// it survives `AnalyticsWireBody`'s scalar flattening as a plain JSON string, it sorts
    /// lexically, and it reads without a decoder ring. `AppState.installWeek` already computes the
    /// week-start `Date` in `AppState.cohortCalendar` (Gregorian, Sunday-start, `America/Los_Angeles`);
    /// this formats that same instant in the same calendar's time zone, so the string names the Sunday
    /// the cohort week began rather than shifting it into an adjacent day under a different zone.
    static func installWeekString(_ weekStart: Date) -> String {
        weekStartFormatter.string(from: weekStart)
    }

    private static let weekStartFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = AppState.cohortCalendar
        formatter.timeZone = AppState.cohortCalendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
