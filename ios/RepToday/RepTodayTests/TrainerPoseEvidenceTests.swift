import XCTest
import SwiftUI
@testable import RepToday

/// Reviewer evidence for the Trainer pose art PRD (US-TP06 to US-TP11, collected by US-TP13).
///
/// Every test hosts the **production** `ActiveSessionView` (or `SettingsView`) over real catalog
/// movements and the real bundled art, at the default phone size (393x852 pt) and the small phone size
/// (375x667 pt), in dark and light, and:
/// - asserts the US-TP09 pose labels and the compact ring labels on the live accessibility tree, and
///   that no element exists per individual pose image;
/// - asserts the small-phone fit: the compact ring and the round tracker are above the controls, and on
///   the rest overlay the heading, ring, next-up text, poses and both controls stack without
///   overlapping, all on screen;
/// - writes a PNG per state, size and appearance under `artifacts/reports/US-TP13/` when run with
///   `REPTODAY_WRITE_EVIDENCE=1` (a temporary directory otherwise).
@MainActor
final class TrainerPoseEvidenceTests: XCTestCase {

    private let story = "US-TP13"
    private var window: UIWindow?

    private struct Variant {
        let size: CGSize
        let style: UIUserInterfaceStyle
        var suffix: String {
            "\(Int(size.width))x\(Int(size.height))-\(style == .dark ? "dark" : "light")"
        }
        var isSmall: Bool { size.width < 390 }
        /// The small variant is an iPhone SE (3rd generation): a 20 pt status bar, no home indicator.
        var safeArea: UIEdgeInsets? { isSmall ? UIEdgeInsets(top: 20, left: 0, bottom: 0, right: 0) : nil }
    }

    private let variants: [Variant] = [
        Variant(size: CGSize(width: 393, height: 852), style: .dark),
        Variant(size: CGSize(width: 393, height: 852), style: .light),
        Variant(size: CGSize(width: 375, height: 667), style: .dark),
        Variant(size: CGSize(width: 375, height: 667), style: .light),
    ]

    override func tearDown() {
        window = nil
        super.tearDown()
    }

    // MARK: - Fixtures

    private func catalog() throws -> [String: Exercise] {
        let url = try XCTUnwrap(Bundle(for: AppState.self).url(forResource: "Exercises", withExtension: "json"))
        let list = try JSONDecoder().decode([Exercise].self, from: Data(contentsOf: url))
        return Dictionary(uniqueKeysWithValues: list.map { ($0.id, $0) })
    }

    private func prescription(_ id: String, sets: Int = 1, seconds: Int? = nil) throws -> PrescribedExercise {
        let exercise = try XCTUnwrap(try catalog()[id], "no \(id) in the catalog")
        return PrescribedExercise(
            id: UUID(), exercise: exercise, sets: sets,
            reps: exercise.isHold ? nil : exercise.defaultReps,
            durationSeconds: exercise.isHold ? (seconds ?? exercise.defaultDurationSeconds) : nil,
            restSeconds: 30
        )
    }

    private func workout(_ blocks: [(String, ExerciseCategory, [PrescribedExercise])]) -> Workout {
        Workout(
            id: UUID(), createdAt: Date(), shape: .blend, focusPillar: nil, requestedMinutes: 15,
            wasReturn: false,
            blocks: blocks.map { WorkoutBlock(id: UUID(), title: $0.0, category: $0.1, exercises: $0.2) }
        )
    }

    private func user(sex: Sex, trainer: Trainer? = nil) -> User {
        var user = MockPersistence.sampleUser
        user.profile.sex = sex
        user.profile.trainer = trainer
        return user
    }

    // MARK: - Tree helpers

    private func root() -> UIView? { window?.rootViewController?.view }

    private func labels() -> [String] {
        guard let root = root() else { return [] }
        return AccessibilityTree.labels(in: root)
    }

    private func element(_ predicate: (String) -> Bool) -> NSObject? {
        guard let root = root() else { return nil }
        return AccessibilityTree.element(whereLabel: predicate, in: root)
    }

    /// An element's frame in the hosted window's own coordinates.
    private func frame(_ predicate: (String) -> Bool) -> CGRect? {
        guard let frame = element(predicate)?.accessibilityFrame, let origin = window?.frame.origin else { return nil }
        return frame.offsetBy(dx: -origin.x, dy: -origin.y)
    }

    private func pump(until predicate: () -> Bool, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if predicate() { return true }
            HostedSurface.pump(for: 0.1)
        }
        return predicate()
    }

    private func host<V: View>(_ view: V, _ variant: Variant) {
        window = nil
        let (_, hosted) = HostedSurface.host(
            view, size: variant.size, settleFor: 1.5, style: variant.style, emulatingSafeArea: variant.safeArea
        )
        window = hosted
    }

    private func activate(_ label: String, file: StaticString = #filePath, line: UInt = #line) {
        guard let root = root(), let control = AccessibilityTree.element(labeled: label, in: root) else {
            return XCTFail("no \"\(label)\" control; tree reads \(labels())", file: file, line: line)
        }
        XCTAssertTrue(control.accessibilityActivate(), "\"\(label)\" did not activate", file: file, line: line)
    }

    private func capture(_ name: String, _ variant: Variant) throws {
        guard let root = root() else { return XCTFail("no hosted surface") }
        HostedSurface.pump(for: 0.6)
        let image = HostedSurface.capture(root, size: variant.size, afterScreenUpdates: true)
        let path = try EvidenceOutput.write(image, named: "\(name)-\(variant.suffix).png", for: story)
        print("US-TP13 EVIDENCE: \(path)")
    }

    /// The pose group is one element named for the exercise, and no element exists per pose image.
    private func assertPoseLabel(_ expected: String, exerciseName: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(
            pump(until: { self.labels().contains(expected) }, timeout: 5),
            "expected \"\(expected)\"; tree reads \(labels())", file: file, line: line
        )
        HostedSurface.pump(for: 0.8) // let any outgoing screen finish leaving before counting stops
        let all = labels()
        XCTAssertFalse(all.contains { $0.contains("Trainer/") || $0.hasSuffix("-start") || $0.hasSuffix("-end") },
                       "an individual pose image is exposed to VoiceOver: \(all)", file: file, line: line)
        let groups = all.filter { $0.hasPrefix("\(exerciseName), trainer showing") }
        XCTAssertLessThanOrEqual(groups.count, 1, "one focus stop per pose group: \(groups)", file: file, line: line)
    }

    /// The player's scroll area in the hosted window's coordinates: what shows without scrolling.
    private func visibleScrollArea() -> CGRect? {
        guard let root = root(), let window else { return nil }
        func scrollView(in view: UIView) -> UIScrollView? {
            if let scroll = view as? UIScrollView { return scroll }
            return view.subviews.lazy.compactMap { scrollView(in: $0) }.first
        }
        return scrollView(in: root).map { $0.convert($0.bounds, to: window) }
    }

    /// On every size, the compact ring beside the name and the round tracker below it (its label and
    /// set dots) sit whole inside the player's scroll area - visible without scrolling, not cut by the
    /// controls below them.
    private func assertRingAboveTheFold(prefix: String, primary: String, file: StaticString = #filePath, line: UInt = #line) {
        guard let ring = frame({ $0.hasPrefix(prefix) }), let control = frame({ $0 == primary }),
              let tracker = frame({ $0.hasPrefix("Round ") || $0.hasPrefix("Set ") }),
              let visible = visibleScrollArea() else {
            return XCTFail("missing ring, \(primary), tracker or the scroll area; tree reads \(labels())", file: file, line: line)
        }
        XCTAssertLessThanOrEqual(ring.maxY, control.minY, "the ring must be visible above the controls", file: file, line: line)
        XCTAssertLessThanOrEqual(ring.maxY, visible.maxY, "the ring is cut by the bottom of the scroll area", file: file, line: line)
        XCTAssertLessThanOrEqual(ring.width, CountdownRingSize.compact + 1, "the ring must be the compact one", file: file, line: line)
        XCTAssertLessThanOrEqual(tracker.maxY, visible.maxY + 0.5,
                                 "the round tracker is cut by the bottom of the scroll area", file: file, line: line)
    }

    /// The rest overlay stacks heading, ring, next-up text, poses and both controls without overlap,
    /// all inside the screen (US-TP08, decision 12).
    private func assertRestFits(heading: String, nextUpPrefix: String, posesLabel: String, _ variant: Variant,
                                file: StaticString = #filePath, line: UInt = #line) {
        let ring = frame { $0.hasPrefix("\(heading), ") }
        let next = frame { $0.hasPrefix(nextUpPrefix) }
        let poses = frame { $0 == posesLabel }
        let extend = frame { $0.hasPrefix("Extend rest by") }
        let skip = frame { $0 == "Skip rest" }
        guard let ring, let next, let poses, let extend, let skip else {
            return XCTFail("rest overlay piece missing; tree reads \(labels())", file: file, line: line)
        }
        XCTAssertLessThanOrEqual(ring.maxY, next.minY + 0.5, "ring overlaps the next-up text", file: file, line: line)
        XCTAssertLessThanOrEqual(next.maxY, poses.minY + 0.5, "next-up text overlaps the poses", file: file, line: line)
        XCTAssertLessThanOrEqual(poses.maxY, skip.minY, "poses overlap the controls", file: file, line: line)
        XCTAssertLessThanOrEqual(skip.maxY, variant.size.height, "Skip rest is off screen", file: file, line: line)
        XCTAssertLessThanOrEqual(extend.maxY, variant.size.height, "+15s is off screen", file: file, line: line)
        XCTAssertGreaterThanOrEqual(poses.height, 100, "the poses shrank past legibility", file: file, line: line)
        print("US-TP13 REST FIT \(variant.suffix): ring \(Int(ring.height))pt, poses card \(Int(poses.height))pt, controls top \(Int(skip.minY))pt")
    }

    // MARK: - Exercise card states (US-TP06/US-TP07/US-TP09)

    /// Rep work window: the female Trainer's pair fills the card; the compact ring sits beside the name.
    func testRepWorkWindowShowsThePairAndTheCompactRing() throws {
        let session = workout([("Strength", .strength, [try prescription("hinge_glute_bridge", sets: 2), try prescription("push_wall", sets: 2)])])
        for variant in variants {
            host(ActiveSessionView(workout: session, user: user(sex: .female)), variant)
            assertPoseLabel("Glute Bridge, trainer showing start and end positions", exerciseName: "Glute Bridge")
            XCTAssertTrue(pump(until: { self.labels().contains { $0.hasPrefix("Work window, ") } }, timeout: 5), "\(labels())")
            assertRingAboveTheFold(prefix: "Work window, ", primary: "Done")
            // A roomy phone keeps about 150 pt per pose; a short one shrinks them to fit, only so far.
            if let poses = frame({ $0 == "Glute Bridge, trainer showing start and end positions" }) {
                XCTAssertGreaterThanOrEqual(poses.height, variant.isSmall ? 100 : 150, "the poses shrank too far")
            }
            try capture("01-rep-work-window-pair", variant)
        }
    }

    /// At the largest accessibility text size the long name wraps beside the compact ring rather than
    /// truncating, and the ring stays the compact one.
    func testLargestDynamicTypeWrapsTheNameBesideTheRing() throws {
        let session = workout([("Strength", .strength, [try prescription("hinge_long_lever_bridge", sets: 2)])])
        // The headline sits below the fold at this size on any phone (the controls grow too), exactly as
        // before; the default-size fold is asserted above. Hosted at full content height so the capture
        // shows the wrapped name beside the ring.
        for variant in variants where variant.isSmall {
            let variant = Variant(size: CGSize(width: variant.size.width, height: 1100), style: variant.style)
            host(
                ActiveSessionView(workout: session, user: user(sex: .female))
                    .environment(\.dynamicTypeSize, .accessibility5),
                variant
            )
            assertPoseLabel(
                "Long-Lever Single-Leg Bridge, trainer showing start and end positions",
                exerciseName: "Long-Lever Single-Leg Bridge"
            )
            XCTAssertTrue(pump(until: { self.labels().contains { $0.hasPrefix("Work window, ") } }, timeout: 5), "\(labels())")
            guard let ring = frame({ $0.hasPrefix("Work window, ") }),
                  let title = frame({ $0.hasPrefix("Long-Lever Single-Leg Bridge, 2 sets") }) else {
                return XCTFail("missing ring or title; tree reads \(labels())")
            }
            XCTAssertLessThanOrEqual(ring.width, CountdownRingSize.compact + 1)
            XCTAssertLessThanOrEqual(title.maxX, ring.minX, "the name must not run under the ring")
            XCTAssertGreaterThan(title.height, 120, "the long name must wrap onto several lines, not truncate")
            try capture("13-largest-dynamic-type-work-window", variant)
        }
    }

    /// A running (auto-started bookend) hold keeps the poses in the card and shows the compact ring.
    func testRunningHoldKeepsThePosesAndShowsTheCompactRing() throws {
        let session = workout([
            ("Warm-up", .warmup, [try prescription("mobility_deep_squat_hold")]),
            ("Strength", .strength, [try prescription("push_wall")]),
        ])
        for variant in variants {
            host(ActiveSessionView(workout: session, user: user(sex: .male)), variant)
            assertPoseLabel("Deep Squat Hold, trainer showing start and end positions", exerciseName: "Deep Squat Hold")
            XCTAssertTrue(pump(until: { self.labels().contains { $0.hasPrefix("Hold, ") } }, timeout: 5), "\(labels())")
            assertRingAboveTheFold(prefix: "Hold, ", primary: "Stop hold")
            try capture("02-running-hold-pair", variant)
        }
    }

    /// An idle training hold (before Start hold): the poses, and no ring until the hold starts.
    func testIdleTrainingHoldShowsThePosesAndNoRing() throws {
        let session = workout([("Strength", .strength, [try prescription("core_forearm_plank", sets: 2)])])
        for variant in variants {
            host(ActiveSessionView(workout: session, user: user(sex: .female)), variant)
            assertPoseLabel("Forearm Plank, trainer showing start and end positions", exerciseName: "Forearm Plank")
            XCTAssertFalse(labels().contains { $0.hasPrefix("Hold, ") || $0.hasPrefix("Work window, ") }, "no ring before Start hold")
            XCTAssertNotNil(element { $0.hasPrefix("Start hold") })
            try capture("03-idle-training-hold", variant)

            // Starting the hold keeps the poses and brings the compact ring in beside the name.
            activate("Start hold")
            XCTAssertTrue(pump(until: { self.labels().contains { $0.hasPrefix("Hold, ") } }, timeout: 5), "\(labels())")
            XCTAssertTrue(labels().contains("Forearm Plank, trainer showing start and end positions"))
        }
    }

    /// A rep-based warm-up stretch: the poses, no ring, the name at full width.
    func testRepBasedStretchShowsThePosesAndNoRing() throws {
        let session = workout([
            ("Warm-up", .warmup, [try prescription("mobility_cat_cow")]),
            ("Strength", .strength, [try prescription("push_wall")]),
        ])
        for variant in variants {
            host(ActiveSessionView(workout: session, user: user(sex: .male)), variant)
            assertPoseLabel("Cat-Cow Flow, trainer showing start and end positions", exerciseName: "Cat-Cow Flow")
            XCTAssertFalse(labels().contains { $0.hasPrefix("Hold, ") || $0.hasPrefix("Work window, ") }, "no ring on a rep stretch")
            try capture("04-rep-based-stretch", variant)
        }
    }

    /// After an in-session swap the card shows the substitute's poses, with no extra surface.
    func testSwapShowsTheSubstitutesPoses() throws {
        let session = workout([("Strength", .strength, [try prescription("push_standard", sets: 2), try prescription("squat_bodyweight", sets: 2)])])
        host(
            ActiveSessionView(
                workout: session,
                workoutEngine: MockWorkoutEngine(exerciseService: try MockExerciseService()),
                user: user(sex: .female)
            ),
            variants[0]
        )
        assertPoseLabel("Standard Push-Up, trainer showing start and end positions", exerciseName: "Standard Push-Up")
        activate("Swap this exercise")
        XCTAssertTrue(
            pump(until: {
                self.labels().contains { $0.hasSuffix(", trainer showing start and end positions") && !$0.hasPrefix("Standard Push-Up") }
            }, timeout: 10), // the swap runs the real engine off the main actor
            "the card must show the substitute's poses after a swap; tree reads \(labels())"
        )
        XCTAssertFalse(labels().contains("Standard Push-Up, trainer showing start and end positions"))
        // The substitute gets a live countdown again (a fast swap once left it frozen at full).
        XCTAssertTrue(pump(until: { self.labels().contains("Pause session") }, timeout: 5),
                      "the work window must restart for the substitute; tree reads \(labels())")
    }

    /// Wall Scapular Pull has only an end pose: one centered pose, named as the end position.
    func testSinglePoseMovementShowsOneCenteredPose() throws {
        let session = workout([("Strength", .strength, [try prescription("pull_wall_scapular_pull", sets: 2)])])
        for variant in variants {
            host(ActiveSessionView(workout: session, user: user(sex: .female)), variant)
            assertPoseLabel("Wall Scapular Pull, trainer showing end position", exerciseName: "Wall Scapular Pull")
            if let pose = frame({ $0 == "Wall Scapular Pull, trainer showing end position" }) {
                XCTAssertEqual(pose.midX, variant.size.width / 2, accuracy: 1, "a single pose is centered")
            }
            XCTAssertTrue(pump(until: { self.labels().contains { $0.hasPrefix("Work window, ") } }, timeout: 5), "\(labels())")
            assertRingAboveTheFold(prefix: "Work window, ", primary: "Done")
            try capture("05-single-pose", variant)
        }
    }

    /// Prone Y-T-W Raises has no usable art: today's glyph with today's label.
    func testNoArtMovementKeepsTheGlyphFallback() throws {
        let session = workout([("Strength", .strength, [try prescription("pull_ytw", sets: 2)])])
        for variant in variants {
            host(ActiveSessionView(workout: session, user: user(sex: .female)), variant)
            XCTAssertTrue(pump(until: { self.labels().contains("Prone Y-T-W Raises demonstration") }, timeout: 5), "\(labels())")
            XCTAssertFalse(labels().contains { $0.hasPrefix("Prone Y-T-W Raises, trainer showing") })
            XCTAssertTrue(pump(until: { self.labels().contains { $0.hasPrefix("Work window, ") } }, timeout: 5), "\(labels())")
            assertRingAboveTheFold(prefix: "Work window, ", primary: "Done")
            try capture("06-no-art-fallback", variant)
        }
    }

    // MARK: - Rest overlay (US-TP08)

    /// The transition beat and the between-round rest show the upcoming movement's poses, and fit.
    func testRestOverlayShowsTheNextMovementsPosesAndFits() throws {
        let session = workout([("Strength", .strength, [try prescription("push_wall", sets: 2), try prescription("squat_bodyweight", sets: 2)])])
        for variant in variants {
            host(ActiveSessionView(workout: session, user: user(sex: .female)), variant)
            XCTAssertTrue(pump(until: { self.labels().contains("Done") }, timeout: 5), "\(labels())")

            // Station 1 done -> the between-station transition beat, previewing station 2.
            activate("Done")
            XCTAssertTrue(pump(until: { self.labels().contains { $0.hasPrefix("Next: Bodyweight Squat") } }, timeout: 5), "\(labels())")
            assertPoseLabel("Bodyweight Squat, trainer showing start and end positions", exerciseName: "Bodyweight Squat")
            assertRestFits(heading: "Rest", nextUpPrefix: "Next: Bodyweight Squat",
                           posesLabel: "Bodyweight Squat, trainer showing start and end positions", variant)
            try capture("07-transition-beat", variant)

            // Station 2 done -> the between-round rest, previewing round 2's first movement.
            activate("Skip rest")
            XCTAssertTrue(pump(until: { self.labels().contains("Done") }, timeout: 5), "\(labels())")
            activate("Done")
            XCTAssertTrue(pump(until: { self.labels().contains { $0.hasPrefix("Next up, Wall Push-Up") } }, timeout: 5), "\(labels())")
            assertPoseLabel("Wall Push-Up, trainer showing start and end positions", exerciseName: "Wall Push-Up")
            assertRestFits(heading: "Rest", nextUpPrefix: "Next up, Wall Push-Up",
                           posesLabel: "Wall Push-Up, trainer showing start and end positions", variant)
            try capture("08-between-round-rest", variant)
        }
    }

    /// The per-side switch-sides beat shows the same stretch's poses (decision 11), and fits.
    func testSwitchSidesBeatShowsTheSameStretch() throws {
        let session = workout([
            ("Warm-up", .warmup, [try prescription("mobility_kneeling_hip_flexor", seconds: 2)]),
            ("Strength", .strength, [try prescription("push_wall")]),
        ])
        for variant in variants {
            host(ActiveSessionView(workout: session, user: user(sex: .male)), variant)
            XCTAssertTrue(pump(until: { self.labels().contains { $0.hasPrefix("Same stretch") } }, timeout: 10), "\(labels())")
            let label = "Kneeling Hip-Flexor Stretch, trainer showing start and end positions"
            assertPoseLabel(label, exerciseName: "Kneeling Hip-Flexor Stretch")
            assertRestFits(heading: "Switch sides", nextUpPrefix: "Same stretch", posesLabel: label, variant)
            try capture("09-switch-sides-beat", variant)
        }
    }

    // MARK: - One-time choice (US-TP10)

    /// An "other" user is asked before any Trainer art shows, with the session held on a pause and the
    /// explainer waiting behind it; choosing shows that Trainer at once, stores it, resumes the session
    /// and lets the explainer follow.
    func testOtherUserChoosesATrainerBeforeAnyArtAndTheExplainerFollows() throws {
        let session = workout([("Strength", .strength, [try prescription("hinge_glute_bridge", sets: 2)])])
        for variant in variants {
            let defaults = try XCTUnwrap(UserDefaults(suiteName: "TrainerPoseEvidence-\(UUID().uuidString)"))
            let appState = AppState(userDefaults: defaults)
            let service = MockUserService(user: user(sex: .other))
            host(
                ActiveSessionView(workout: session, user: user(sex: .other), userService: service)
                    .environment(appState),
                variant
            )
            XCTAssertTrue(pump(until: { self.labels().contains("Choose your Trainer") || self.labels().contains { $0.hasPrefix("Choose your Trainer") } }, timeout: 5), "\(labels())")
            XCTAssertTrue(labels().contains("Male Trainer") && labels().contains("Female Trainer"), "exactly the two options: \(labels())")
            XCTAssertFalse(labels().contains { $0.contains("trainer showing") }, "no Trainer art before the choice")
            // Open Question 3: the session is held on a pause while the choice is up - the work window
            // does not count down behind it.
            let before = labels().first { $0.hasPrefix("Work window, ") }
            HostedSurface.pump(for: 2.2)
            XCTAssertNotNil(before)
            XCTAssertEqual(labels().first { $0.hasPrefix("Work window, ") }, before, "the window must not run behind the choice")
            XCTAssertFalse(labels().contains { $0.hasPrefix("Your session drives itself") }, "never stacked with the explainer")
            if let option = element({ $0 == "Female Trainer" }) {
                XCTAssertEqual(option.accessibilityHint, TrainerChoiceCopy.optionHint)
                XCTAssertGreaterThanOrEqual(option.accessibilityFrame.height, Theme.Spacing.workoutTouchTarget)
            }
            try capture("10-trainer-choice", variant)

            activate("Female Trainer")
            XCTAssertTrue(
                pump(until: { self.labels().contains("Glute Bridge, trainer showing start and end positions") }, timeout: 5),
                "the chosen Trainer's art shows at once: \(labels())"
            )
            XCTAssertTrue(pump(until: { self.labels().contains { $0.hasPrefix("Your session drives itself") } }, timeout: 5),
                          "the explainer follows the choice: \(labels())")
            XCTAssertFalse(labels().contains("Choose your Trainer"))
            let storedExpectation = expectation(description: "stored")
            Task {
                let stored = try? await service.currentUser()
                XCTAssertEqual(stored?.profile.trainer, .female)
                storedExpectation.fulfill()
            }
            wait(for: [storedExpectation], timeout: 5)
        }
    }

    /// A male- or female-answered user is never asked.
    func testMaleOrFemaleUserIsNeverAsked() throws {
        let session = workout([("Strength", .strength, [try prescription("push_wall", sets: 2)])])
        for sex in [Sex.male, .female] {
            host(ActiveSessionView(workout: session, user: user(sex: sex), userService: MockUserService(user: user(sex: sex))), variants[0])
            XCTAssertTrue(pump(until: { self.labels().contains("Wall Push-Up, trainer showing start and end positions") }, timeout: 5), "\(labels())")
            HostedSurface.pump(for: 0.5)
            XCTAssertFalse(labels().contains { $0.hasPrefix("Choose your Trainer") }, "\(sex) must never see the choice")
        }
    }

    // MARK: - Settings row (US-TP11)

    func testSettingsTrainerRowShowsTheEffectiveTrainerOrNotChosenYet() throws {
        let cases: [(String, User, String)] = [
            ("11-settings-trainer-row", user(sex: .male), "Male Trainer"),
            ("12-settings-trainer-not-chosen", user(sex: .other), "Not chosen yet"),
        ]
        for (name, stored, value) in cases {
            // Settings is a scrolling list whose Trainer section sits near the end, so each width is
            // hosted at the list's full height to show the row in context.
            for variant in variants {
                let variant = Variant(size: CGSize(width: variant.size.width, height: 1400), style: variant.style)
                let model = TrainerSettingsViewModel(userService: MockUserService(user: stored))
                host(
                    NavigationStack { SettingsView(trainerSettings: model) }
                        .environment(\.services, ServiceContainer.mock())
                        .environment(AppState.preview(isOnboarded: true, selectedTab: .profile)),
                    variant
                )
                XCTAssertTrue(pump(until: { self.element({ $0 == "Trainer" })?.accessibilityValue == value }, timeout: 5),
                              "the Trainer row reads \(String(describing: element({ $0 == "Trainer" })?.accessibilityValue))")
                // The section sits above Account, so the destructive action stays last.
                if let trainer = frame({ $0 == "Trainer" }), let delete = frame({ $0 == SettingsView.deleteAccountTitle }) {
                    XCTAssertLessThan(trainer.maxY, delete.minY)
                }
                try capture(name, variant)
            }
        }
    }

    /// Settings left open on the Profile tab while the player's one-time choice stores a Trainer: back on
    /// the tab, the row shows the stored Trainer rather than the "Not chosen yet" it first read.
    func testSettingsTrainerRowRereadsWhenTheTabReturns() throws {
        let service = MockUserService(user: user(sex: .other))
        let tabs = SettingsTabHarness.Selection()
        host(
            SettingsTabHarness(selection: tabs, settings: TrainerSettingsViewModel(userService: service))
                .environment(\.services, ServiceContainer.mock())
                .environment(AppState.preview(isOnboarded: true, selectedTab: .profile)),
            Variant(size: CGSize(width: 393, height: 1400), style: .dark)
        )
        let trainerValue = { self.element({ $0 == "Trainer" })?.accessibilityValue }
        XCTAssertTrue(pump(until: { trainerValue() == "Not chosen yet" }, timeout: 5), "row reads \(String(describing: trainerValue()))")

        tabs.tab = .today
        HostedSurface.pump(for: 0.5)
        // A synchronous test, so the screen's own `.task` runs while the run loop is pumped.
        let written = WriteFlag()
        Task {
            _ = try await service.saveTrainerChoice(.female)
            written.landed = true
        }
        XCTAssertTrue(pump(until: { written.landed }, timeout: 5), "the player-side write never landed")

        tabs.tab = .profile
        XCTAssertTrue(pump(until: { trainerValue() == "Female Trainer" }, timeout: 5),
                      "the row still reads \(String(describing: trainerValue())) after the Trainer was chosen elsewhere")
    }
}

/// Set once a write made from a test's `Task` has landed.
@MainActor
private final class WriteFlag {
    var landed = false
}

/// Settings pushed on a Profile tab beside a Today tab, with the selected tab driven from the test - the
/// shape a user leaves Settings open in while they go and train.
private struct SettingsTabHarness: View {
    enum Tab { case today, profile }

    @Observable
    final class Selection {
        var tab: Tab = .profile
    }

    @Bindable var selection: Selection
    let settings: TrainerSettingsViewModel

    var body: some View {
        TabView(selection: $selection.tab) {
            Text("Today").tag(Tab.today).tabItem { Text("Today") }
            NavigationStack { SettingsView(trainerSettings: settings) }
                .tag(Tab.profile)
                .tabItem { Text("Profile") }
        }
    }
}

/// The compact ring's diameter - `CountdownRing.compactDiameter` (private to the player), restated so the
/// fit assertion can tell the compact ring from the full-size one.
private enum CountdownRingSize {
    static let compact: CGFloat = 80
}
