import Foundation

#if canImport(UIKit)
import UIKit
import AudioToolbox
#endif

/// Sensory feedback for the rest timer (US-K02).
///
/// When a rest period ends the player fires a cue so the user can start the next set without
/// watching the clock. The cue is a haptic pulse with an audio alternative, so it is accessible
/// when haptics are disabled or unavailable (e.g. VoiceOver users, or a device with no Taptic
/// Engine). The protocol keeps the view model testable: tests inject a spy that just counts the
/// firing, and the real `SystemRestTimerFeedback` does the UIKit work at the app boundary.
protocol RestTimerFeedback {
    /// Fire the "rest complete" cue - a haptic plus an audio alternative.
    func restDidComplete()
}

/// The real feedback: a success haptic plus a short system sound as the accessible audio
/// alternative. On platforms without UIKit (or in a headless test process) it is a no-op, so the
/// view model can default to it everywhere without a compile guard at the call site.
struct SystemRestTimerFeedback: RestTimerFeedback {
    func restDidComplete() {
        #if canImport(UIKit)
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        // Audio alternative so the cue lands even when haptics are off/unavailable.
        AudioServicesPlaySystemSound(1057)
        #endif
    }
}
