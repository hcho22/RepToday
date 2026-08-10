import Foundation

/// The app's external legal links, in one place.
///
/// Three surfaces link to the privacy policy, for two unrelated reasons - the paywall, because App
/// Store Review Guideline 3.1.2 requires it on an auto-renewable subscription screen (US-N04), and
/// the telemetry disclosure in onboarding and in Settings, because an opt-out consent model has to
/// say what is collected (US-T06). They must point at the same document: two placeholder URLs would
/// drift, and the one that drifted would be the one nobody looked at.
///
/// `privacyPolicy` points at Rep Today's hosted policy on the landing site. It is the single edit
/// point for all three surfaces that link to it, rather than a search across the views.
enum LegalLinks {
    /// The hosted privacy policy at `reptoday.app/privacy` (source: `gtm/03-site/privacy.html`,
    /// deployed with the landing site). The document is an engineering draft grounded in the app's
    /// documented data practices and is pending a legal review before go-live - see the blocking
    /// item on `gtm/08-redteam/pre-publication-checklist.md` ("Author the privacy policy").
    static let privacyPolicy = URL(string: "https://reptoday.app/privacy")!

    /// Apple's standard auto-renewable-subscription EULA, the default Terms of Use when the app
    /// ships no custom one.
    static let termsOfUse = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
}
