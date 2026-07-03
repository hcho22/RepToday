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
/// `blend`). The engine needs a finer distinction internally: a light blend (warm-up + one
/// real block + a small second block), a full blend (warm-up + strength block + mobility
/// block + cooldown), and - for the longest sessions (US-E01) - an extended blend that has
/// room for a dedicated third block. `SessionShapeTemplate` carries those internal buckets
/// while still mapping every one of them back to the stored `SessionShape`. It is an
/// engine-internal value type - never persisted - so it deliberately does not adopt the
/// `Codable`/raw-value persistence contract the domain enums in `Models/Enums.swift` do.

// MARK: - SessionShapeTemplate

enum SessionShapeTemplate: CaseIterable, Equatable {
    /// 5-10 min: one pillar, done well. In a short mobility-led session the opening flow
    /// doubles as warm-up + training.
    case singleFocus
    /// 11-20 min: warm-up + one real block + a small second block.
    case blendLight
    /// 21-40 min: warm-up + strength block + mobility block + cooldown.
    case blendFull
    /// 41-60 min: a full blend with room for a dedicated third (primal) block; the extended
    /// end of the range unlocked in US-E01. Resolves to the same canonical `.blend` shape;
    /// the dedicated primal block itself lands in US-E02.
    case blendExtended

    /// The canonical, persisted session shape this template resolves to on the `Workout`.
    var shape: SessionShape {
        switch self {
        case .singleFocus:
            return .singleFocus
        case .blendLight, .blendFull, .blendExtended:
            return .blend
        }
    }

    /// The supported request range, in minutes; `select` clamps to it so the mapping is total.
    static let supportedRange = 5...60

    /// Selects the session template from the user's requested minutes (pipeline Step 1, extended
    /// to the full 5-60 range in US-E01).
    ///
    /// The request is first clamped into `supportedRange`, then mapped with the provisional
    /// thresholds the PRD (US-E01) specifies, so the documented boundaries (10, 20, 40) land
    /// exactly:
    /// - `5-10` -> `.singleFocus` (the short single-focus band)
    /// - `11-20` -> `.blendLight` (the light blend)
    /// - `21-40` -> `.blendFull` (the full blend)
    /// - `41-60` -> `.blendExtended` (the extended blend)
    ///
    /// The mapping is total and deterministic: the same number of minutes always yields the same
    /// shape, and values outside the supported range clamp to its nearest edge rather than trap.
    static func select(requestedMinutes: Int) -> SessionShapeTemplate {
        let minutes = min(max(requestedMinutes, supportedRange.lowerBound), supportedRange.upperBound)
        switch minutes {
        case ...10:
            return .singleFocus
        case 11...20:
            return .blendLight
        case 21...40:
            return .blendFull
        default:
            return .blendExtended
        }
    }
}
