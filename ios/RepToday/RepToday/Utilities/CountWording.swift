import Foundation

/// English count agreement for copy that pairs a number with a noun ("1 session", "3 sessions").
///
/// The app ships English-only copy with no string catalog, so a count's noun is chosen here rather
/// than through plural variants: exactly one takes the singular, and every other count - zero
/// included - takes the plural ("0 sessions"). One helper keeps on-screen text and its VoiceOver
/// label agreeing, since both read the same count.
enum CountWording {

    /// `singular` when `count` is exactly 1, else `plural`.
    static func noun(for count: Int, singular: String, plural: String) -> String {
        count == 1 ? singular : plural
    }

    /// The count followed by its agreeing noun: "1 minute moved", "45 minutes moved".
    static func phrase(_ count: Int, singular: String, plural: String) -> String {
        "\(count) \(noun(for: count, singular: singular, plural: plural))"
    }
}
