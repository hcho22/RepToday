import SwiftUI

/// The custom icon set (24 pt grid, 2 pt stroke, round caps), shipped as template vector images in
/// `Assets.xcassets/Icons` so each one tints with the text or meaning color around it. The product UI
/// draws these instead of SF Symbols.
enum AppIcon: String, CaseIterable {
    case today, coach, progress, profile, close, pause, play, check, plus, minus
    case chevr, chevl, swap, skip, moretime, lock, bell, shield, clock, refresh
    case undo, send, spark, trash, signout, external, health, sound, focus, settings
    case mail, calendar, chart, map, arrowup, run, bike, hike, swim, rowing, climb, other

    /// The icon as a resizable template image.
    var image: Image {
        Image("Icons/\(rawValue)").renderingMode(.template).resizable()
    }

    /// What VoiceOver calls a non-decorative icon: its shape in words, as it does an SF Symbol's.
    var spokenName: String {
        switch self {
        case .profile: return "Person"
        case .settings: return "Gear"
        case .chevr: return "Forward"
        case .chevl: return "Back"
        default: return rawValue.capitalized
        }
    }

    /// The icon at its natural 24 pt, for places that size images themselves (a tab item).
    var fixedImage: Image {
        Image("Icons/\(rawValue)").renderingMode(.template)
    }
}

extension OutsideActivityType {
    /// The custom icon for the kind of workout.
    var icon: AppIcon {
        switch self {
        case .run: return .run
        case .bike: return .bike
        case .hike: return .hike
        case .swim: return .swim
        case .row: return .rowing
        case .climb: return .climb
        case .other: return .other
        }
    }
}

/// The day marks: flat single-color shapes, filled for today and done, outlined for upcoming. A
/// `push` dome, `pull` arch, `legs` steps, `rest` crescent, `sun` circle (you; Core in lists), `climb`
/// (the Strength Phase) and `bubble` (the Coach and Premium).
enum DayMark: String, CaseIterable {
    case push, pull, legs, rest, sun, climb, bubble

    init(_ day: TrainingDay?) {
        switch day {
        case .push: self = .push
        case .pull: self = .pull
        case .legs: self = .legs
        case nil: self = .sun
        }
    }

    /// The mark as a resizable template image, filled or outlined.
    func image(filled: Bool) -> Image {
        Image("Marks/\(rawValue)-\(filled ? "fill" : "line")").renderingMode(.template).resizable()
    }
}

/// An icon drawn at `size` points in the current foreground style. Decorative by default - hidden from
/// VoiceOver, since the control it sits in carries the words; a non-decorative icon is its own image
/// element, as an SF Symbol image would be.
struct IconView: View {
    let icon: AppIcon
    var size: CGFloat = 24
    var isDecorative = true

    var body: some View {
        let image = icon.image
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
        if isDecorative {
            image.accessibilityHidden(true)
        } else {
            image
                .accessibilityElement()
                .accessibilityLabel(icon.spokenName)
                .accessibilityAddTraits(.isImage)
        }
    }
}

/// An icon that grows with Dynamic Type relative to `style`, for an icon sitting beside text.
struct ScaledIcon: View {
    let icon: AppIcon
    let isDecorative: Bool
    @ScaledMetric private var size: CGFloat

    init(icon: AppIcon, size: CGFloat = 24, relativeTo style: Font.TextStyle = .body, isDecorative: Bool = true) {
        self.icon = icon
        self.isDecorative = isDecorative
        _size = ScaledMetric(wrappedValue: size, relativeTo: style)
    }

    var body: some View {
        IconView(icon: icon, size: size, isDecorative: isDecorative)
    }
}

/// A day mark drawn at `size` points in `color`, hidden from VoiceOver.
struct DayMarkView: View {
    let mark: DayMark
    var filled = true
    var color: Color
    var size: CGFloat = 28

    var body: some View {
        mark.image(filled: filled)
            .aspectRatio(contentMode: .fit)
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
