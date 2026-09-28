import Foundation
import LocalAuthentication
import Darwin

// Parsing finishes before constructing readers, UI, a coordinator or any prerequisites.
func routeRuntimeMigration(args: [String], preflight: () -> Int32,
    operation: (RuntimeMigrationOperation, String, String, Bool, Bool) -> Int32) -> Int32 {
    if args == ["--keychain-preflight"] { return preflight() }
    guard (3...5).contains(args.count),
          let selected = RuntimeMigrationOperation(rawValue: args[0]),
          args[1].hasPrefix("/"), args[2].hasPrefix("/"),
          args.count == 3 || ((selected == .stage || selected == .release) && Set(args.dropFirst(3)).count == args.count - 3 &&
            args.dropFirst(3).allSatisfy { ["--auth-guard-diagnostics", "--final-auth-diagnostics"].contains($0) }) else { return 64 }
    return operation(selected, args[1], args[2], args.contains("--auth-guard-diagnostics"), args.contains("--final-auth-diagnostics"))
}

struct RuntimePreflightCancelled: Error {}

// Each read still gets a fresh LAContext. Cancellation invalidates only this invocation's
// pending context, including a cancellation racing with the start of a Security query.
final class RuntimePreflightAccess: @unchecked Sendable {
    private let lock = NSLock()
    private var context: LAContext?
    private var cancelled = false
    func begin(_ context: LAContext) throws {
        lock.lock(); defer { lock.unlock() }
        guard !cancelled else { context.invalidate(); throw RuntimePreflightCancelled() }
        self.context = context
    }
    func end() { lock.lock(); context = nil; lock.unlock() }
    func cancel() {
        lock.lock(); cancelled = true; let pending = context; context = nil; lock.unlock()
        pending?.invalidate()
    }
}

enum RuntimePreflightEvent: String {
    case start, pending, completed, success, failure, timedOut = "timed_out", cancelled
}

// No error descriptions, Data, account names or caller-supplied labels reach this sink.
// Monotonic clocks and shortened budgets can be injected only by compiled synthetic tests.
final class RuntimePreflightProgress: @unchecked Sendable {
    static let readLimit: TimeInterval = 115
    static let overallLimit: TimeInterval = 585
    private let lock = NSLock()
    private let now: () -> TimeInterval
    private let emit: (String) -> Void
    private let readLimit: TimeInterval, overallLimit: TimeInterval, started: TimeInterval
    private var readStarted: TimeInterval?
    private var pending: RuntimeMigrationCredential?
    private var lastProgress: TimeInterval
    private var status: Int32?

    init(now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         readLimit: TimeInterval = readLimit, overallLimit: TimeInterval = overallLimit,
         emit: @escaping (String) -> Void) {
        self.now = now; self.emit = emit; self.readLimit = readLimit; self.overallLimit = overallLimit
        started = now(); lastProgress = started
    }
    var exitStatus: Int32? { lock.lock(); defer { lock.unlock() }; return status }
    private func record(_ event: RuntimePreflightEvent, at time: TimeInterval, osstatus: Int32? = nil) {
        let elapsed = Int(max(0, time - started) * 1000)
        let readElapsed = Int(max(0, time - (readStarted ?? time)) * 1000)
        emit("preflight category=\(pending?.rawValue ?? "all") event=\(event.rawValue) elapsed_ms=\(elapsed) read_elapsed_ms=\(readElapsed) osstatus=\(osstatus.map(String.init) ?? "unavailable")")
    }
    private func expired(at time: TimeInterval) -> Bool {
        time - started >= overallLimit || readStarted.map { time - $0 >= readLimit } == true
    }
    private func timeout(at time: TimeInterval) {
        record(.timedOut, at: time); status = 124
    }
    func begin(_ item: RuntimeMigrationCredential) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard status == nil else { return false }
        let time = now()
        guard !expired(at: time) else { timeout(at: time); return false }
        pending = item; readStarted = time; lastProgress = time
        record(.start, at: time); return true
    }
    func completed() -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard status == nil else { return false }
        let time = now()
        guard !expired(at: time) else { timeout(at: time); return false }
        record(.completed, at: time, osstatus: 0); pending = nil; readStarted = nil
        return true
    }
    func fail(_ error: Error) {
        lock.lock(); defer { lock.unlock() }
        guard status == nil else { return }
        let time = now()
        if expired(at: time) { timeout(at: time); return }
        let cancelled = error is RuntimePreflightCancelled
        record(cancelled ? .cancelled : .failure, at: time, osstatus: (error as? CoachCredentialReadStatus)?.status)
        status = cancelled ? 130 : 78
    }
    func poll() -> Int32? {
        lock.lock(); defer { lock.unlock() }
        guard status == nil else { return status }
        let time = now()
        if expired(at: time) { timeout(at: time) }
        else if pending != nil && time - lastProgress >= 5 {
            record(.pending, at: time); lastProgress = time
        }
        return status
    }
    func succeed() -> Int32 {
        lock.lock(); defer { lock.unlock() }
        if let status { return status }
        let time = now()
        if expired(at: time) { timeout(at: time); return 124 }
        record(.success, at: time, osstatus: 0); status = 0; return 0
    }
}

// Its scope ends before emitting completion or starting another read. There is no bundle,
// validation/encoding, pipe or downstream consumer. Reset is best effort, not forensic erasure
// of framework/COW copies. The autorelease pool also drains per item.
private func readAndDiscard(_ item: RuntimeMigrationCredential, reader: any RuntimeMigrationReader) throws {
    try autoreleasepool {
        var bytes = try reader.read(item)
        bytes.resetBytes(in: 0..<bytes.count)
        bytes.removeAll(keepingCapacity: false)
    }
}

func runKeychainPreflight(reader: any RuntimeMigrationReader, progress: RuntimePreflightProgress) -> Int32 {
    for item in RuntimeMigrationCredential.allCases {
        guard progress.begin(item) else { reader.cancelPendingRead(); return progress.exitStatus ?? 78 }
        do { try readAndDiscard(item, reader: reader) }
        catch { progress.fail(error); reader.cancelPendingRead(); return progress.exitStatus ?? 78 }
        guard progress.completed() else { reader.cancelPendingRead(); return progress.exitStatus ?? 78 }
    }
    return progress.succeed()
}

// Independent of the AppKit main queue: a stuck modal/query cannot stop the watchdog.
// Production termination exits the process even if Security has not returned after invalidation.
final class RuntimePreflightWatchdog {
    private let timer: DispatchSourceTimer
    private var signals: [DispatchSourceSignal] = []
    init(progress: RuntimePreflightProgress, cancel: @escaping () -> Void,
         terminate: @escaping (Int32) -> Void, handleSignals: Bool = true) {
        let queue = DispatchQueue(label: "com.reptoday.keychain-preflight.watchdog")
        timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(100))
        timer.setEventHandler {
            if let status = progress.poll(), status != 0 { cancel(); terminate(status) }
        }
        timer.resume()
        if handleSignals {
            for number in [SIGINT, SIGTERM, SIGHUP] {
                signal(number, SIG_IGN)
                let source = DispatchSource.makeSignalSource(signal: number, queue: queue)
                source.setEventHandler {
                    progress.fail(RuntimePreflightCancelled()); cancel(); terminate(progress.exitStatus ?? 130)
                }
                source.resume(); signals.append(source)
            }
        }
    }
    deinit { timer.cancel(); for source in signals { source.cancel() } }
}

@MainActor func runNativeKeychainPreflight() -> Int32 {
    let reader = PresentedRuntimeMigrationReader(
        reader: NativeRuntimeMigrationReader(preflightAccess: RuntimePreflightAccess()), preflight: true)
    let progress = RuntimePreflightProgress { line in
        FileHandle.standardOutput.write(Data((line + "\n").utf8))
    }
    let watchdog = RuntimePreflightWatchdog(progress: progress, cancel: { reader.cancelPendingRead() },
        terminate: { _exit($0) })
    let status = withExtendedLifetime(watchdog) { runKeychainPreflight(reader: reader, progress: progress) }
    // Also ends any pending background read following a Cancel-panel response.
    _exit(status)
}
