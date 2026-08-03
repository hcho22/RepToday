import UIKit

/// The one place that decides where a test suite's evidence is written - a rendered screen, or the
/// text artifact a non-UI seam leaves behind instead (`AnalyticsServiceTests` writes the funnel's
/// wire payload and transcript through the same door).
///
/// Every evidence suite produces its artifacts on every run - they and the assertions beside them are
/// the gate - but where the bytes land is opt-in:
///
/// - by default, a per-run temporary directory, so a plain `test` never leaves the worktree dirty
///   with re-encoded PNGs and never depends on the machine the evidence was first captured on;
/// - `REPTODAY_WRITE_EVIDENCE=1` points the same writes at the repo's own `artifacts/reports/`,
///   which is how the committed artifacts the PRD and `docs/test-coverage.md` cite are produced -
///   deliberately, by these tests, rather than copied there by hand;
/// - `REPTODAY_EVIDENCE_DIR=<root>` puts the same writes under a root of the caller's choosing.
///
/// **The rule for `REPTODAY_EVIDENCE_DIR`: it names a *root*, never a final directory.** The story
/// folder is appended to it exactly as it is appended to `artifacts/reports/`, so one redirected run
/// lays its output out in the same shape as the committed baselines and stays self-organising by
/// story instead of pouring every suite's output into one flat directory. All three modes therefore
/// differ only in the root; the `<root>/<story>/<file>` shape is invariant.
///
/// The repo root is walked up from `#filePath`, since a test bundle controls neither the working
/// directory nor any repo-relative path:
/// `<repo>/ios/RepToday/RepTodayTests/EvidenceOutput.swift` -> `<repo>/artifacts/reports`.
///
/// New evidence suites resolve through `EvidenceOutput.directory(for:)` and write through
/// `EvidenceOutput.write(_:named:for:)` rather than copying either. `OnboardingBasicsEvidenceTests`
/// has landed but still carries its own copy - and reads `REPTODAY_EVIDENCE_DIR` as the final
/// directory rather than as a root - so it is the one suite yet to adopt this.
enum EvidenceOutput {

    /// Each story keeps its evidence in its own folder, so a render belonging to one story's work
    /// never lands among the ones another story's acceptance notes point a reviewer at.
    enum Story {
        static let perSideSwap = "per-side-swap"
        static let sessionTimer = "us-o03"
        static let progressAnalytics = "us-m02"
        static let analyticsSeam = "us-t02"
    }

    /// The directory `story`'s evidence is written to for this run.
    static func directory(for story: String) -> String {
        (root as NSString).appendingPathComponent(story)
    }

    /// Writes `image` into `story`'s evidence directory, and is the only place a rendered surface
    /// becomes a file.
    ///
    /// The check that the surface actually drew belongs on the write rather than beside each caller's
    /// capture: restated per suite it ended up *after* the write, so a run that already knew the render
    /// was bad still replaced the committed baseline with a near-blank image and only then recorded a
    /// failure - a staged diff indistinguishable from a legitimate regeneration. Guarding here makes the
    /// file unreachable unless every precondition held, for every suite including the next one.
    @discardableResult
    static func write(_ image: UIImage, named fileName: String, for story: String) throws -> String {
        guard drew(image) else {
            throw CaptureFailure.didNotDraw(fileName: fileName)
        }
        guard let data = image.pngData() else {
            throw CaptureFailure.notEncodable(fileName: fileName)
        }

        let destination = directory(for: story)
        try FileManager.default.createDirectory(atPath: destination, withIntermediateDirectories: true)
        let path = (destination as NSString).appendingPathComponent(fileName)
        try data.write(to: URL(fileURLWithPath: path))

        print("SNAPSHOT_WRITTEN \(path) bytes=\(data.count) "
              + "size=\(Int(image.size.width))x\(Int(image.size.height))")
        return path
    }

    /// Writes a text artifact - a transcript of what VoiceOver speaks, or the JSON body a seam would
    /// put on the wire - into `story`'s evidence directory, resolving the destination and creating it
    /// through the same path the image write uses, so a suite never re-implements the
    /// resolve-and-create step this owns.
    ///
    /// There is no did-it-draw guard to apply here: text carries its own evidence of having been
    /// produced, where a capture of a surface that never drew does not.
    @discardableResult
    static func write(_ text: String, named fileName: String, for story: String) throws -> String {
        let destination = directory(for: story)
        try FileManager.default.createDirectory(atPath: destination, withIntermediateDirectories: true)
        let path = (destination as NSString).appendingPathComponent(fileName)
        try text.write(toFile: path, atomically: true, encoding: .utf8)

        print("TRANSCRIPT_WRITTEN \(path)")
        return path
    }

    /// Whether `image` holds a drawn screen rather than the uniform fill a capture of a surface that
    /// never drew comes back as.
    ///
    /// Asked of the pixels rather than of the encoded byte count, because a byte floor does not mean
    /// what it appears to: PNG size scales with canvas area, so a *blank* 393x1942 capture at scale 3
    /// encodes to ~64KB - eight times over the 8000-byte floor this used to be, which therefore passed
    /// the undrawn capture straight through to the committed baseline it was meant to protect. Any
    /// production screen varies somewhere; a surface that never drew is one colour everywhere, at every
    /// size. The image is sampled through a small scratch bitmap so the cost does not scale with it.
    private static func drew(_ image: UIImage) -> Bool {
        guard let cgImage = image.cgImage else { return false }

        let width = 32, height = 64, bytesPerPixel = 4
        var pixels = [UInt8](repeating: 0, count: width * height * bytesPerPixel)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * bytesPerPixel, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return false }

        let first = Array(pixels.prefix(bytesPerPixel))
        return stride(from: bytesPerPixel, to: pixels.count, by: bytesPerPixel).contains { index in
            Array(pixels[index ..< index + bytesPerPixel]) != first
        }
    }

    /// Raised instead of writing bytes that would replace a committed baseline with a known-bad image.
    enum CaptureFailure: Error, CustomStringConvertible {
        case notEncodable(fileName: String)
        case didNotDraw(fileName: String)

        var description: String {
            switch self {
            case let .notEncodable(fileName):
                return "\(fileName) could not be encoded as a PNG, so nothing was written."
            case let .didNotDraw(fileName):
                return "\(fileName) came back a single flat colour, which is a surface that never drew "
                    + "rather than a screen. Nothing was written, so no committed baseline is replaced "
                    + "by a blank capture."
            }
        }
    }

    private static let root: String = {
        let environment = ProcessInfo.processInfo.environment
        if let override = environment["REPTODAY_EVIDENCE_DIR"], !override.isEmpty {
            return override
        }
        if environment["REPTODAY_WRITE_EVIDENCE"] == "1" {
            return URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent() // RepTodayTests
                .deletingLastPathComponent() // RepToday
                .deletingLastPathComponent() // ios
                .deletingLastPathComponent() // the repo root
                .appendingPathComponent("artifacts")
                .appendingPathComponent("reports")
                .path
        }
        return FileManager.default.temporaryDirectory
            .appendingPathComponent("RepTodayEvidence")
            .appendingPathComponent(UUID().uuidString)
            .path
    }()
}
