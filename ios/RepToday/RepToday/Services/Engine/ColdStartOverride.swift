import Foundation

/// Pipeline Step 0 of the deterministic engine (US-E04): the cold-start override that runs *before*
/// Steps 1-6 while a brand-new user is still finding their footing, so their first sessions are kept
/// gentle and vivid and a mis-reported fitness level never produces a badly over-hard day.
///
/// Step 0 is deliberately a thin override, not a second engine. It touches exactly two of the inputs
/// the rest of the pipeline already consumes, and leaves everything else to Steps 1-6:
///
/// - **Capped Starting Difficulty** (`cappedPool`) - the eligible pool is restricted to movements at
///   or below the policy's `coldStartContract.cappedMaxDifficulty`, so someone who over-rated their
///   fitness level still gets a winnable first day. The "served at the gentle end of the band"
///   promise then falls out of Step 5, which already starts a no-history user at the gentlest tier.
/// - **First-Week Contrast** (`overridePlan`) - when the contract sets `forceContrastSpread`, the
///   day's lead pillar is forced onto a deterministic rotation keyed by `coldStart.sessionsLogged`,
///   overriding the single-theme bias `why`/`sitsLong` alone would produce (a desk worker's
///   all-mobility week) so the first week visibly spans strength, mobility, and primal.
///
/// Step 0 is gated on two conditions and is otherwise a no-op: the user is still in the cold-start
/// window (`user.coldStart.active`) *and* the live policy carries a `coldStartContract`. Once the
/// engine retires cold-start (US-G04 clears the contract and flips `active` off), both overrides
/// return their input untouched and the engine behaves exactly as US-E03. Like every other step it
/// is a pure function of its inputs (no hidden clock; the "day" is read from `sessionsLogged`), so it
/// stays deterministic and unit-testable.
enum ColdStartOverride {

    /// The canonical First-Week Contrast rotation order. Cycling through all three first-class
    /// pillars is what guarantees the vivid day-to-day spread (US-G02) instead of a single-theme
    /// week; the rotation is restricted per shape to the pillars a session can actually train.
    static let rotation: [Pillar] = [.strength, .mobility, .primal]

    // MARK: - Gate

    /// Whether Step 0 applies at all: the user is still in the cold-start window and the live policy
    /// carries a cold-start contract. When this is false both overrides below are no-ops.
    static func isActive(user: User, sessionPolicy: SessionPolicy) -> Bool {
        user.coldStart.active && sessionPolicy.coldStartContract != nil
    }

    // MARK: - Capped Starting Difficulty

    /// The eligible pool restricted to the cold-start difficulty ceiling: only movements at or below
    /// `coldStartContract.cappedMaxDifficulty` survive, so a mis-reported fitness level never yields a
    /// badly over-hard first day. A no-op when Step 0 is inactive.
    ///
    /// If the cap would empty the pool entirely (no movement that gentle exists for the needed work)
    /// the uncapped pool is returned instead - the safety rail must never break generation by
    /// starving the assembler of every option.
    static func cappedPool(
        _ pool: [Exercise],
        user: User,
        sessionPolicy: SessionPolicy
    ) -> [Exercise] {
        guard user.coldStart.active, let contract = sessionPolicy.coldStartContract else {
            return pool
        }
        let capped = pool.filter { $0.difficulty <= contract.cappedMaxDifficulty }
        return capped.isEmpty ? pool : capped
    }

    // MARK: - First-Week Contrast

    /// The pillar plan with First-Week Contrast applied: the lead pillar is forced onto the
    /// `sessionsLogged` rotation so consecutive cold-start days never repeat a pillar, overriding the
    /// single-theme bias `why`/`sitsLong` alone would produce. A no-op when Step 0 is inactive or the
    /// contract does not force the spread.
    ///
    /// - A single-focus session's one pillar is set directly to the rotated pillar (the rotation
    ///   spans all three pillars, so a desk worker's mobility lean no longer collapses the week).
    /// - A blend's shares are re-pointed so the rotated pillar owns the largest block (its block leads
    ///   and gets the most time), rotating only over the pillars the shape actually trains
    ///   (strength/mobility for a short or full blend; all three for an extended blend).
    static func overridePlan(
        _ plan: PillarPlan,
        template: SessionShapeTemplate,
        user: User,
        sessionPolicy: SessionPolicy
    ) -> PillarPlan {
        guard
            user.coldStart.active,
            let contract = sessionPolicy.coldStartContract,
            contract.forceContrastSpread
        else { return plan }

        switch plan {
        case .single:
            return .single(contrastPillar(user: user, available: Pillar.allCases))
        case .blend(let weights):
            let available: [Pillar] = template == .blendExtended
                ? [.strength, .mobility, .primal]
                : [.strength, .mobility]
            let lead = contrastPillar(user: user, available: available)
            return .blend(weights.favoring(lead))
        }
    }

    // MARK: - Rotation

    /// The forced lead pillar for the current cold-start day: the onboarding-derived starting pillar
    /// rotated forward by `coldStart.sessionsLogged`, restricted to the pillars a session's shape can
    /// train. Rotating over at least two pillars guarantees consecutive days never repeat.
    static func contrastPillar(user: User, available: [Pillar]) -> Pillar {
        let ordered = rotation.filter { available.contains($0) }
        guard !ordered.isEmpty else { return available.first ?? .strength }
        let start = ordered.firstIndex(of: startingPillar(for: user)) ?? 0
        let day = max(0, user.coldStart.sessionsLogged)
        return ordered[(start + day) % ordered.count]
    }

    /// The day-zero starting pillar derived from onboarding inputs: the user's stated
    /// `why.openingBias` when present (the single allowed programming lever of `why`), otherwise
    /// mobility for a desk worker (`sitsLong`, for same-day relief), otherwise strength. The rotation
    /// then walks forward from here, so onboarding sets where the first week *opens* but never lets it
    /// stall on one theme.
    static func startingPillar(for user: User) -> Pillar {
        if let bias = user.why.openingBias { return bias }
        return user.profile.sitsLong ? .mobility : .strength
    }

}
