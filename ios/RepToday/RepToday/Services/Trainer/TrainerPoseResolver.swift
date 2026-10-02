import UIKit

/// One of the two poses a Trainer is drawn in for a movement.
enum TrainerPose: String, CaseIterable {
    case start
    case end
}

/// What art exists for one movement and one Trainer (US-TP04): exactly one of a full start/end pair,
/// a single pose, or nothing. Each case carries the asset-catalog names the view loads.
enum TrainerPoseArt: Equatable {
    case pair(start: String, end: String)
    case single(TrainerPose, String)
    case none

    /// The one image to show where a single picture of the Trainer is wanted (the US-TP10 choice):
    /// the start pose, else the only pose there is, else nothing.
    var previewAssetName: String? {
        switch self {
        case .pair(let start, _): return start
        case .single(_, let name): return name
        case .none: return nil
        }
    }
}

/// Answers "which poses exist for this movement and Trainer" (US-TP04) - the one place every surface
/// (the exercise card, the rest overlay, the US-TP10 choice) asks, so they all show art the same way.
///
/// It looks the asset catalog up by the US-TP02 naming convention, `Trainer/<trainer>/<exercise id>-<pose>`
/// (keyed by **exercise id**, never display name, so the two "Cossack Squat" movements cannot collide),
/// through an injectable lookup so tests run without the real bundle. Because the answer is read off
/// the catalog, a missing pose dropped in later under that name lights up with no Swift change.
struct TrainerPoseResolver {
    /// Whether an image set with this name exists.
    let imageExists: (String) -> Bool

    init(imageExists: @escaping (String) -> Bool) {
        self.imageExists = imageExists
    }

    /// The production resolver, reading the app bundle's asset catalog.
    static let bundled = TrainerPoseResolver { name in
        UIImage(named: name, in: .main, with: nil) != nil
    }

    /// The asset-catalog name of one pose: `Trainer/female/hinge_glute_bridge-start`.
    static func assetName(exerciseId: String, trainer: Trainer, pose: TrainerPose) -> String {
        "Trainer/\(trainer.rawValue)/\(exerciseId)-\(pose.rawValue)"
    }

    /// The art for `exerciseId` drawn by `trainer`. Each Trainer resolves independently.
    func art(exerciseId: String, trainer: Trainer) -> TrainerPoseArt {
        let start = Self.assetName(exerciseId: exerciseId, trainer: trainer, pose: .start)
        let end = Self.assetName(exerciseId: exerciseId, trainer: trainer, pose: .end)
        switch (imageExists(start), imageExists(end)) {
        case (true, true): return .pair(start: start, end: end)
        case (true, false): return .single(.start, start)
        case (false, true): return .single(.end, end)
        case (false, false): return .none
        }
    }
}

/// The spoken copy for the pose art (US-TP09) - one source for the exercise card and the rest overlay.
enum TrainerPoseCopy {
    /// One label per pose group: the pair, the single pose, or (no art) today's glyph label.
    static func accessibilityLabel(exerciseName: String, art: TrainerPoseArt) -> String {
        switch art {
        case .pair:
            return "\(exerciseName), trainer showing start and end positions"
        case .single(let pose, _):
            return "\(exerciseName), trainer showing \(pose.rawValue) position"
        case .none:
            return "\(exerciseName) demonstration"
        }
    }
}
