import Foundation
import Observation

enum CoachSyntheticQAConfiguration {
    static func isEnabled(bundle: Bundle = .main) -> Bool {
        guard bundle.object(forInfoDictionaryKey: "RepTodayCoachSyntheticQA") as? String == "1",
              let origin = CoachProxyClient.endpoint(fromOrigin: bundle.object(forInfoDictionaryKey: CoachProxyClient.endpointInfoPlistKey))
        else { return false }
        return CoachProxyClient.productionConfigurationAllowed(
            origin: origin,
            mode: bundle.object(forInfoDictionaryKey: CoachProxyClient.authenticationModeInfoPlistKey),
            secret: CoachProxyClient.secret(fromValue: bundle.object(forInfoDictionaryKey: CoachProxyClient.secretInfoPlistKey))
        )
    }
}

/// Content-free, installation-scoped budget. Persist BEFORE attempting a turn, including before
/// Apple authentication. Failed, interrupted or unreviewed attempts can never be offered again.
/// Account deletion does not reset this budget; there is deliberately no app reset/retry control.
@MainActor
@Observable
final class CoachSyntheticQABudget {
    enum Stage: String {
        case ready, whyAttempted, readyForPistol, pistolAttempted, complete, stopped
    }
    private static let key = "CoachSyntheticQA.twoRequestBudgetV1"
    private let defaults: UserDefaults
    private(set) var stage: Stage

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let stored = defaults.object(forKey: Self.key) {
            stage = (stored as? String).flatMap(Stage.init(rawValue:)) ?? .stopped
        } else {
            stage = .ready
        }
    }

    var next: CoachSyntheticFixtures.Selection? {
        switch stage {
        case .ready: return .whySquats
        case .readyForPistol: return .pistolForm
        default: return nil
        }
    }

    var summary: String {
        switch stage {
        case .ready: return "Two attempts available; why squats first."
        case .whyAttempted: return "Why-squats attempt used; local review required here."
        case .readyForPistol: return "Why-squats reviewed; one pistol-form attempt available."
        case .pistolAttempted: return "Both attempts used; local review required here."
        case .complete: return "Both attempts used and locally reviewed."
        case .stopped: return "QA stopped; no requests available."
        }
    }

    func refresh() {
        guard let stored = defaults.object(forKey: Self.key) else { return }
        stage = (stored as? String).flatMap(Stage.init(rawValue:)) ?? .stopped
    }

    func begin(_ selection: CoachSyntheticFixtures.Selection) -> Bool {
        // Read the persisted state as well: a second screen/model must not reopen a spent budget.
        refresh()
        guard next == selection else { return false }
        save(selection == .whySquats ? .whyAttempted : .pistolAttempted)
        return true
    }

    func reviewed(_ selection: CoachSyntheticFixtures.Selection, passed: Bool) {
        refresh()
        guard stage == (selection == .whySquats ? .whyAttempted : .pistolAttempted) else { return }
        save(passed ? (selection == .whySquats ? .readyForPistol : .complete) : .stopped)
    }

    func stop() { save(.stopped) }

    private func save(_ value: Stage) {
        stage = value
        defaults.set(value.rawValue, forKey: Self.key)
    }
}

/// Only the configured client and existing entitlement/consent readers are dependencies. No
/// workout/user/policy writer or real-history reader is available to this synthetic execution path.
@MainActor
@Observable
final class CoachSyntheticQAViewModel {
    private let client: CoachProxyClient?
    private let subscription: any SubscriptionServiceProtocol
    private let consent: () -> Bool
    let budget: CoachSyntheticQABudget
    private(set) var isPremium = false
    private(set) var isSending = false
    private(set) var reply: String?
    private(set) var returnedSelection: CoachSyntheticFixtures.Selection?
    private(set) var status = "No request sent. Service migration and signed-device readiness are required."
    var readinessConfirmed = false
    private var generation = 0

    init(client: CoachProxyClient?, subscription: any SubscriptionServiceProtocol,
         consent: @escaping () -> Bool, budget: CoachSyntheticQABudget) {
        self.client = client
        self.subscription = subscription
        self.consent = consent
        self.budget = budget
        if budget.stage != .ready {
            status = "Saved QA budget restored. Prior replies are not stored; used attempts cannot be repeated."
        }
    }

    var isAvailable: Bool { client != nil }
    var hasConsent: Bool { consent() }
    var canSend: Bool {
        isAvailable && hasConsent && isPremium && readinessConfirmed && !isSending && budget.next != nil
    }

    func loadEligibility() async {
        budget.refresh()
        isPremium = (try? await subscription.currentSubscription().tier) == .premium
    }

    /// Called only by the named Send button. There is no automatic send or retry, and at most
    /// 30 seconds TOTAL for a turn (local recheck + native authentication + HTTP + response).
    func sendNext() async {
        guard canSend, let selection = budget.next, let client else { return }
        isSending = true
        reply = nil
        returnedSelection = nil
        let expected = generation
        defer { isSending = false }
        // Reserve first, so concurrent entry/relaunch cannot spend the same prompt twice.
        guard budget.begin(selection) else { return }
        status = "Sending synthetic \(selection.title). No retry will be offered."
        do {
            let subscription = self.subscription
            let result = try await boundedCoachOperation(seconds: min(30, client.timeoutSeconds)) {
                guard try await subscription.currentSubscription().tier == .premium else {
                    throw CoachAuthenticationError.unavailable
                }
                // Consent and screen lifetime are rechecked AFTER the asynchronous entitlement read.
                return try await self.deliver(client, selection: selection, generation: expected)
            }
            guard generation == expected, consent(), !Task.isCancelled else { budget.stop(); return }
            returnedSelection = selection
            reply = result
            status = "Non-empty reply returned. Semantic correctness is unverified until local review."
        } catch {
            budget.stop()
            // Never stringify transport/provider/platform errors: they may contain private values.
            status = "QA stopped after a failed or interrupted attempt. No retry; your offline workout is available."
        }
    }

    private func deliver(_ client: CoachProxyClient, selection: CoachSyntheticFixtures.Selection,
                         generation expected: Int) async throws -> String {
        guard generation == expected, consent(), !Task.isCancelled else {
            throw CoachAuthenticationError.unavailable
        }
        return try await client.reply(to: selection.prompt, context: selection.context)
    }

    func reviewReturnedReply(passed: Bool) {
        guard !isSending, reply != nil, let selection = returnedSelection else { return }
        budget.reviewed(selection, passed: passed)
        reply = nil
        returnedSelection = nil
        status = passed ? "Local semantic review marked passed for \(selection.title)." : "Local semantic review failed. QA stopped; no further requests."
    }

    func close() {
        generation += 1
        readinessConfirmed = false
        reply = nil
        returnedSelection = nil
        if isSending || budget.stage == .whyAttempted || budget.stage == .pistolAttempted { budget.stop() }
    }
}
