import Foundation

/// The app's external legal links, in one place.
///
/// Three surfaces link to the privacy policy for three reasons: the paywall, because App Store Review
/// Guideline 3.1.2 requires it on an auto-renewable subscription screen (US-N04); the telemetry
/// disclosure in onboarding and Settings, because an opt-out consent model has to say what is
/// collected (US-T06); and the Settings AI Coach disclosure, because Coach content leaves the device
/// for OpenAI (US-AC04). They must point at the same document so the legal destination cannot drift.
///
/// `privacyPolicy` points at Rep Today's hosted policy on the landing site. It is the single edit
/// point for all three surfaces that link to it, rather than a search across the views.
enum LegalLinks {
    /// The hosted privacy policy at `reptoday.app/privacy` (authored from the landing-site privacy
    /// source, deployed with the landing site). The document is an engineering draft grounded in the
    /// app's documented data practices and is pending a legal review before go-live - see the
    /// pre-publication checklist item ("Author the privacy policy").
    static let privacyPolicy = URL(string: "https://reptoday.app/privacy")!

    /// Apple's standard auto-renewable-subscription EULA, the default Terms of Use when the app
    /// ships no custom one.
    static let termsOfUse = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
}
