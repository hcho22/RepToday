import Foundation

/// The app's external legal links, in one place.
///
/// Three surfaces link to the privacy policy, for two unrelated reasons - the paywall, because App
/// Store Review Guideline 3.1.2 requires it on an auto-renewable subscription screen (US-N04), and
/// the telemetry disclosure in onboarding and in Settings, because an opt-out consent model has to
/// say what is collected (US-T06). They must point at the same document: two placeholder URLs would
/// drift, and the one that drifted would be the one nobody looked at.
///
/// **`privacyPolicy` is a placeholder** and is deliberately obvious about it. Replacing it with Rep
/// Today's real policy is a precondition for App Store submission, and doing so is a single edit
/// here rather than a search across the views that link to it.
enum LegalLinks {
    /// PLACEHOLDER. Authoring and hosting the real policy is a blocking item on
    /// `gtm/08-redteam/pre-publication-checklist.md` ("Author the privacy policy", under Legal /
    /// naming), which is where the requirement and its current status live - not here.
    static let privacyPolicy = URL(string: "https://example.com/reptoday-privacy-policy-PLACEHOLDER")!

    /// Apple's standard auto-renewable-subscription EULA, the default Terms of Use when the app
    /// ships no custom one.
    static let termsOfUse = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
}
