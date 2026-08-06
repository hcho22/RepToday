import XCTest

/// Restoring a key in a `UserDefaults` container the test host actually shares.
///
/// Most tests here drive a throwaway suite and simply abandon it. A few cannot: the telemetry gate is
/// bound to `UserDefaults.standard` because that is the store production's `AppState` writes and the
/// transport reads, so a test that asked both sides about a suite of its own would only prove the two
/// agree about a container nothing ships with. Those tests write the test host's real defaults, which
/// makes putting the previous value back part of the test rather than politeness - a leftover key
/// leaks into every test that runs after it in the same process.
extension XCTestCase {

    /// Snapshots `key` and restores whatever was there - including its absence - when the test ends.
    ///
    /// Registered rather than lexically scoped, so it survives a test that returns early or throws,
    /// and so the restore cannot drift away from the write it undoes as the test body is edited.
    func restoreAfterTest(_ key: String, in defaults: UserDefaults = .standard) {
        let original = defaults.object(forKey: key)
        addTeardownBlock {
            if let original {
                defaults.set(original, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }
    }
}
