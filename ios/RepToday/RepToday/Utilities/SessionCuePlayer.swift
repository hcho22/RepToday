import Foundation

#if canImport(UIKit)
import UIKit
import AudioToolbox
import AVFoundation
#endif

/// A distinct, non-verbal state cue for the hands-free follow-along player (US-CC10).
///
/// The player is watched like a video with no spoken callouts, so each state the flow transitions
/// through is marked by its own tone (and its own haptic), so the states are tellable apart by ear -
/// and by touch when the tone is muted or withheld. One case per state:
///
/// - `.go` - a work window has started; begin the reps now.
/// - `.halfway` - the (optional) midpoint of a work window.
/// - `.transition` - a short between-station transition inside a circuit round has begun (US-CC04).
/// - `.roundRest` - the bounded between-round rest has begun (US-CC04).
/// - `.done` - a set or hold leg has completed.
///
/// There is deliberately no case for the US-CC05 "Switch sides" beat: it fires no cue at all, so the
/// only completion cue a per-side bookend hold produces is one `.done` per leg.
enum SessionCue: CaseIterable {
    case go
    case halfway
    case transition
    case roundRest
    case done
}

/// The player's sensory-cue seam (US-CC10). It evolved from the single-cue US-K02 `RestTimerFeedback`
/// (one undifferentiated `restDidComplete()`) into a per-state vocabulary, without changing the shape
/// that keeps the view model testable: a spy that just records the firings is injected in tests, and
/// the real `SystemSessionCuePlayer` does the UIKit/AVFoundation work at the app boundary.
///
/// Every cue is **always** accompanied by a haptic (the project's "haptics with an audio alternative"
/// convention), so a muted user - or one running VoiceOver, where the tone is withheld to avoid
/// talking over speech - still perceives the state change. `suppressAudio` carries that VoiceOver
/// decision to the boundary so it is observable in tests through the same spy seam: when it is set the
/// haptic still fires but the tone does not.
protocol SessionCuePlayer {
    /// Fire the cue for `cue`: a distinct haptic always, plus a distinct audio tone unless
    /// `suppressAudio` is set (VoiceOver running, so the tone would collide with speech).
    func play(_ cue: SessionCue, suppressAudio: Bool)
}

/// Whether VoiceOver is speaking right now, so the player can withhold a tone that would talk over it
/// (US-CC10). Read at fire time. `false` off UIKit (headless tests), where the injected spy stands in.
func isVoiceOverRunningNow() -> Bool {
    #if canImport(UIKit)
    return UIAccessibility.isVoiceOverRunning
    #else
    return false
    #endif
}

/// The real cue player: a distinct system sound per state that **ducks** the user's own audio for the
/// tone's duration (never stops it) plus a distinct haptic. On platforms without UIKit (or in a
/// headless test process) it is a no-op, so the view model can default to it everywhere without a
/// compile guard at the call site.
///
/// **Ducking (the load-bearing part of US-CC10's "lowers, does not stop"):** the shared `AVAudioSession`
/// is configured `.playback` with `.duckOthers`, so playing a tone lowers - rather than interrupts -
/// any music or podcast, and deactivating with `.notifyOthersOnDeactivation` restores it to full
/// volume. `.playback` (not `.ambient`) is deliberate: a follow-along workout cue must be audible over
/// the silent switch while media plays, and the haptic covers a user who has turned media volume down.
/// The session is activated on the first overlapping tone and deactivated only once the last tone
/// finishes (a small in-flight counter), so back-to-back cues - a `.done` immediately followed by a
/// `.transition` - never cut each other's duck short or thrash the session.
///
/// **VoiceOver coordination:** on-device this is only fully real with VoiceOver actually speaking; the
/// view model decides suppression from `UIAccessibility.isVoiceOverRunning` and passes it here as
/// `suppressAudio`, and this type withholds the tone (and its duck) while still firing the haptic.
struct SystemSessionCuePlayer: SessionCuePlayer {
    func play(_ cue: SessionCue, suppressAudio: Bool) {
        #if canImport(UIKit)
        // The haptic always fires - it never collides with VoiceOver speech and it is the accessible
        // alternative for a muted user, so it is what guarantees every state change is perceivable.
        Self.playHaptic(for: cue)
        guard !suppressAudio else { return }
        Self.playDuckedTone(Self.soundID(for: cue))
        #endif
    }

    #if canImport(UIKit)
    /// A distinct system sound per state so the five states are tellable apart by ear. The exact IDs
    /// are audibly-distinct built-ins (no bundled asset, so no `docs/asset-attribution.md` row is
    /// owed); final tone selection is device-verifiable QA, but distinctness is structural here.
    private static func soundID(for cue: SessionCue) -> SystemSoundID {
        switch cue {
        case .go:         return 1113 // begin-recording: a rising "start now"
        case .halfway:    return 1105 // a soft, unobtrusive midpoint tock
        case .transition: return 1057 // "Tink": the short between-station beat
        case .roundRest:  return 1075 // a lower, longer tone for the longer round break
        case .done:       return 1114 // end-recording: a settling "that's the set"
        }
    }

    /// A distinct haptic per state, so a user relying on touch (muted, or VoiceOver with the tone
    /// withheld) can still tell the states apart. `.done` is a success notification; the pacing cues
    /// use impact weights that rise with the significance of the boundary.
    private static func playHaptic(for cue: SessionCue) {
        switch cue {
        case .done:
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .go:
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        case .roundRest:
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        case .transition:
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .halfway:
            UISelectionFeedbackGenerator().selectionChanged()
        }
    }

    // MARK: - Ducking lifecycle

    /// Serialises the in-flight tone count and the session activate/deactivate so overlapping cues
    /// cannot race the shared `AVAudioSession`.
    private static let duckQueue = DispatchQueue(label: "com.reptoday.session-cue.duck")
    private static var inFlightTones = 0
    private static var liveToneTokens: Set<Int> = []
    private static var nextToneToken = 0
    private static var didConfigureCategory = false

    /// A ceiling on how long a single tone may keep the session ducked. The built-in cues are short
    /// (well under a second), so this only ever fires as a safety net when a completion callback is
    /// missed - long enough never to cut a real tone short, short enough that a dropped callback cannot
    /// leave the user's audio ducked for more than a beat.
    private static let toneSafetyTimeout: DispatchTimeInterval = .seconds(5)

    /// Duck the user's audio, play the tone, then restore the audio once the tone finishes. Ducking
    /// begins on the first overlapping tone and ends only when the last one completes, so a rapid
    /// `.done` -> `.transition` pair ducks once across both rather than restoring between them.
    ///
    /// Each tone is retired exactly once - whichever of its completion callback or its safety deadline
    /// arrives first - so a missed `AudioServicesPlaySystemSoundWithCompletion` callback can never
    /// strand `inFlightTones` above zero and leave the user's audio permanently ducked.
    private static func playDuckedTone(_ id: SystemSoundID) {
        duckQueue.async {
            configureCategoryIfNeeded()
            if inFlightTones == 0 {
                try? AVAudioSession.sharedInstance().setActive(true)
            }
            let token = nextToneToken
            nextToneToken += 1
            liveToneTokens.insert(token)
            inFlightTones += 1
            AudioServicesPlaySystemSoundWithCompletion(id) {
                duckQueue.async { retireTone(token) }
            }
            // Safety net: if the completion callback is ever dropped, retire the tone anyway so the
            // duck is always released. A no-op if the callback already retired this token.
            duckQueue.asyncAfter(deadline: .now() + toneSafetyTimeout) {
                retireTone(token)
            }
        }
    }

    /// Retire a single in-flight tone, restoring the user's audio to full volume once the last one is
    /// gone. Idempotent per token (guarded by `liveToneTokens`), so the completion callback and the
    /// safety deadline racing for the same tone decrement `inFlightTones` at most once between them.
    private static func retireTone(_ token: Int) {
        guard liveToneTokens.remove(token) != nil else { return }
        inFlightTones = max(0, inFlightTones - 1)
        if inFlightTones == 0 {
            // Restore the user's audio to full volume.
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    private static func configureCategoryIfNeeded() {
        guard !didConfigureCategory else { return }
        // `.playback` + `.duckOthers`: our short tone lowers the user's music/podcast for its duration
        // instead of stopping it, and is audible over the silent switch during a workout.
        try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.duckOthers])
        didConfigureCategory = true
    }
    #endif
}
