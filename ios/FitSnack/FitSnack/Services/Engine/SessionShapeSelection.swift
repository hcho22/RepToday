import Foundation

/// Pipeline Step 1 of the deterministic engine (US-C01): choose the structural shape of a
/// session purely from the minutes the user has.
///
/// This is the first and simplest step in the v5 section 2.4 pipeline - a total, pure
/// function of `requestedMinutes` alone (no profile, no history), so the same number of
/// minutes always yields the same shape. Later steps fill that shape with pillars,
/// patterns, and exercises.
///
/// The canonical `SessionShape` stored on a `Workout` has only two cases (`singleFocus` /
/// `blend`). The engine needs a finer distinction internally: a 15-minute blend is *light*
/// (warm-up + one real block + a small second block) while a 20-30 minute blend is *full*
/// (warm-up + strength block + mobility block + cooldown). `SessionShapeTemplate` carries
/// that third bucket while still mapping back to the stored `SessionShape`. It is an
/// engine-internal value type - never persisted - so it deliberately does not adopt the
/// `Codable`/raw-value persistence contract the domain enums in `Models/Enums.swift` do.

// MARK: - SessionShapeTemplate

enum SessionShapeTemplate: CaseIterable, Equatable {
    /// 5-10 min: one pillar, done well. In a short mobility-led session the opening flow
    /// doubles as warm-up + training.
    case singleFocus
    /// 15 min: warm-up + one real block + a small second block.
    case blendLight
    /// 20-30 min: warm-up + strength block + mobility block + cooldown.
    case blendFull

    /// The canonical, persisted session shape this template resolves to on the `Workout`.
    var shape: SessionShape {
        switch self {
        case .singleFocus:
            return .singleFocus
        case .blendLight, .blendFull:
            return .blend
        }
    }

    /// Selects the session template from the user's requested minutes (pipeline Step 1).
    ///
    /// The mapping is total and deterministic, with the documented boundaries (10, 15, 20)
    /// landing exactly where the PRD specifies:
    /// - `<= 10` -> `.singleFocus` (the 5-10 min single-focus band)
    /// - `11...19` -> `.blendLight` (the 15-min light blend)
    /// - `>= 20` -> `.blendFull` (the 20-30 min full blend)
    ///
    /// The supported request range is 5-30 minutes; values outside it still resolve
    /// deterministically (anything at or below 10 is single-focus, anything 20 or above is
    /// a full blend) so the function never traps.
    static func select(requestedMinutes: Int) -> SessionShapeTemplate {
        switch requestedMinutes {
        case ..<11:
            return .singleFocus
        case ..<20:
            return .blendLight
        default:
            return .blendFull
        }
    }
}
