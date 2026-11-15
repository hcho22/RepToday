import XCTest

/// Fails the default `RepToday` test run if an SF Symbol comes back on the Progress, Strength Phase,
/// Coach or Paywall screens. The visual direction's rule is "no SF Symbols and no emoji in the product
/// UI": these screens draw the custom icon set (`AppIcon`) and the day marks (`DayMark`) instead, and
/// this guard turns that from a review-time promise into a build-time fact, the same source-scan pattern
/// as `NoManualModeGuardTests`.
final class ProgressCoachPaywallSymbolGuardTests: XCTestCase {

    func testTheseScreensDrawNoSFSymbols() throws {
        // Built by concatenation so this guard's own source never contains the literals it hunts for.
        let needles = ["system" + "Name:", "system" + "Image:"]

        let views = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // RepTodayTests
            .deletingLastPathComponent() // RepToday
            .appendingPathComponent("RepToday/Views")
        let folders = ["Progress", "Coach", "Paywall"].map { views.appendingPathComponent($0) }

        var scanned = 0
        for folder in folders {
            let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "swift" }
            XCTAssertFalse(files.isEmpty, "found no sources in \(folder.path); update this guard if the layout moved")
            for file in files {
                scanned += 1
                let text = try String(contentsOf: file, encoding: .utf8)
                for needle in needles {
                    XCTAssertFalse(
                        text.contains(needle),
                        "\(file.lastPathComponent) draws an SF Symbol (`\(needle)`). Use the custom icon set "
                            + "(`AppIcon`, `IconView`, `ScaledIcon`) or a day mark (`DayMarkView`) instead."
                    )
                }
            }
        }
        XCTAssertGreaterThanOrEqual(scanned, 8, "expected every Progress, Coach and Paywall source to be scanned")
    }
}
