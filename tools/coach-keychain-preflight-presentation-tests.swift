import Foundation
import AppKit
import Darwin

// This executable has only injected nonsecret reads, never a native Security reader.
private final class PresentedPreflightDouble: RuntimeMigrationReader, @unchecked Sendable {
    let scenario: String
    private let released = DispatchSemaphore(value: 0)
    init(_ scenario: String) { self.scenario = scenario }
    func cancelPendingRead() { released.signal() }
    func read(_ item: RuntimeMigrationCredential) throws -> Data {
        let serviced = DispatchSemaphore(value: 0)
        DispatchQueue.main.async {
            precondition(NSApplication.shared.windows.contains { $0.isVisible })
            serviced.signal()
        }
        precondition(serviced.wait(timeout: .now() + 2) == .success)
        if scenario == "cancel" {
            DispatchQueue.main.async { NSApplication.shared.stopModal(withCode: .alertFirstButtonReturn) }
            released.wait(); throw RuntimePreflightCancelled()
        }
        if scenario == "pending" || scenario == "signal" { released.wait(); throw RuntimePreflightCancelled() }
        if scenario == "failure" && item == .keyID { throw CoachCredentialReadStatus(status: -25293) }
        Thread.sleep(forTimeInterval: 0.025)
        return Data("NONSECRET_PRESENTATION_SENTINEL".utf8)
    }
}

@main struct PreflightPresentationTests {
    @MainActor static func main() {
        let scenario = CommandLine.arguments[1]
        let reader = PresentedRuntimeMigrationReader(reader: PresentedPreflightDouble(scenario), preflight: true)
        let progress = RuntimePreflightProgress(readLimit: ["pending", "blocked-main"].contains(scenario) ? 0.7 : 5, overallLimit: 10) {
            FileHandle.standardOutput.write(Data(($0 + "\n").utf8))
        }
        let watchdog = RuntimePreflightWatchdog(progress: progress, cancel: { reader.cancelPendingRead() }, terminate: { _exit($0) })
        if scenario == "blocked-main" {
            precondition(progress.begin(.openAI))
            withExtendedLifetime(watchdog) { Thread.sleep(forTimeInterval: 20) }
            _exit(99)
        }
        let status = withExtendedLifetime(watchdog) { runKeychainPreflight(reader: reader, progress: progress) }
        _exit(status)
    }
}
