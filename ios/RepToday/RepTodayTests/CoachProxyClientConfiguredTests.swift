import XCTest
@testable import RepToday

/// Tests US-AC02's build-configured resolution of the coach transport: `CoachProxyClient.configured`
/// mirrors `LiveAnalyticsService.configured` - a usable HTTPS origin yields a client, anything absent
/// or unusable yields `nil` (the coach is inert, never fatal, and the surface shows "unavailable").
/// The approved production hostname always requires exact origin/mode and no embedded gate.
final class CoachProxyClientConfiguredTests: XCTestCase {

    // MARK: - Endpoint resolution

    func testUsableHTTPSOriginResolves() {
        let url = CoachProxyClient.endpoint(fromOrigin: "https://worker.example.com/coach")
        XCTAssertEqual(url?.absoluteString, "https://worker.example.com/coach")
    }

    func testOriginIsTrimmedBeforeParsing() {
        let url = CoachProxyClient.endpoint(fromOrigin: "  https://worker.example.com/coach  ")
        XCTAssertEqual(url?.absoluteString, "https://worker.example.com/coach")
    }

    func testEmptyOriginIsUnconfigured() {
        XCTAssertNil(CoachProxyClient.endpoint(fromOrigin: ""))
        XCTAssertNil(CoachProxyClient.endpoint(fromOrigin: "   "))
    }

    func testMissingOrNonStringOriginIsUnconfigured() {
        XCTAssertNil(CoachProxyClient.endpoint(fromOrigin: nil))
        XCTAssertNil(CoachProxyClient.endpoint(fromOrigin: 42))
    }

    func testNonHTTPSOriginIsRejected() {
        // A plaintext origin is a configuration mistake, not a deployment choice - stay inert.
        XCTAssertNil(CoachProxyClient.endpoint(fromOrigin: "http://worker.example.com/coach"))
    }

    func testSchemelessOriginIsRejected() {
        XCTAssertNil(CoachProxyClient.endpoint(fromOrigin: "worker.example.com/coach"))
    }

    // MARK: - Secret resolution (optional)

    func testSecretResolvesWhenPresent() {
        XCTAssertEqual(CoachProxyClient.secret(fromValue: "s3cret"), "s3cret")
        XCTAssertEqual(CoachProxyClient.secret(fromValue: "  s3cret  "), "s3cret")
    }

    func testEmptyOrMissingSecretIsNilNotAnError() {
        // nil is a *valid* state (an open dev Worker): no bearer, but still configured.
        XCTAssertNil(CoachProxyClient.secret(fromValue: ""))
        XCTAssertNil(CoachProxyClient.secret(fromValue: "   "))
        XCTAssertNil(CoachProxyClient.secret(fromValue: nil))
        XCTAssertNil(CoachProxyClient.secret(fromValue: 42))
    }

    // MARK: - Configuration-specific client inclusion

    func testActualAppBundleSelectsTheIntendedConfiguration() {
        let client = CoachProxyClient.configured(safetyIdentifierProvider: { testCoachSafetyIdentifier })
        #if COACH_IPHONE_QA
        XCTAssertTrue(CoachSyntheticQAConfiguration.isEnabled())
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "RepTodayBuildConfiguration") as? String, "CoachDeviceQA")
        XCTAssertEqual(client?.endpoint.absoluteString, CoachProxyClient.productionOrigin)
        XCTAssertNil(client?.sharedSecret)
        XCTAssertNotNil(client?.transport as? RuntimeAuthenticatedCoachTransport)
        #elseif DEBUG
        XCTAssertFalse(CoachSyntheticQAConfiguration.isEnabled())
        XCTAssertNil(client)
        #else
        XCTAssertFalse(CoachSyntheticQAConfiguration.isEnabled())
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "RepTodayBuildConfiguration") as? String, "Release")
        XCTAssertEqual(client?.endpoint.absoluteString, CoachProxyClient.productionOrigin)
        XCTAssertNil(client?.sharedSecret)
        XCTAssertNotNil(client?.transport as? RuntimeAuthenticatedCoachTransport)
        #endif
    }
    private func withConfiguration(_ values:[String:Any],check:(Bundle)->Void) throws {
        var repository=URL(fileURLWithPath:#filePath)
        for _ in 0..<4 {repository.deleteLastPathComponent()}
        guard FileManager.default.fileExists(atPath:repository.appendingPathComponent("AGENTS.md").path) else {
            throw NSError(domain:"LocalCoachFixture",code:1)
        }
        let fixture=repository.appendingPathComponent("build/coach-config-fixtures/\(UUID().uuidString).bundle")
        try FileManager.default.createDirectory(at:fixture,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:fixture)}
        var info=values;info["CFBundleIdentifier"]="com.reptoday.localcoachfixture";info["CFBundlePackageType"]="BNDL"
        let data=try PropertyListSerialization.data(fromPropertyList:info,format:.xml,options:0)
        try data.write(to:fixture.appendingPathComponent("Info.plist"))
        let bundle=try XCTUnwrap(Bundle(url:fixture));check(bundle)
    }
    func testProductionHostnameCannotFallThroughToDevelopmentTransport() throws {
        for origin in ["https://coach.reptoday.app/coach?x=1","https://coach.reptoday.app/coach/",
                       "https://coach.reptoday.app/variety-language","https://user@coach.reptoday.app/coach"] {
            try withConfiguration([CoachProxyClient.endpointInfoPlistKey:origin,
                CoachProxyClient.authenticationModeInfoPlistKey:CoachProxyClient.productionAuthenticationMode]) {bundle in
                XCTAssertNil(CoachProxyClient.configured(safetyIdentifierProvider:{testCoachSafetyIdentifier},bundle:bundle))
            }
        }
        for extra in [[:],[CoachProxyClient.authenticationModeInfoPlistKey:"bearer"],
                      [CoachProxyClient.authenticationModeInfoPlistKey:CoachProxyClient.productionAuthenticationMode,
                       CoachProxyClient.secretInfoPlistKey:"NONSECRET_EMBEDDED_GATE_FIXTURE"]] {
            var info=extra;info[CoachProxyClient.endpointInfoPlistKey]=CoachProxyClient.productionOrigin
            try withConfiguration(info) {bundle in
                XCTAssertNil(CoachProxyClient.configured(safetyIdentifierProvider:{testCoachSafetyIdentifier},bundle:bundle))
            }
        }
    }
    #if os(iOS)
    @MainActor
    func testMissingOrInvalidLocalConfigurationSelectsBuildDisabledNotSendFailure() throws {
        let valid = [CoachProxyClient.endpointInfoPlistKey: CoachProxyClient.productionOrigin,
                     CoachProxyClient.authenticationModeInfoPlistKey: CoachProxyClient.productionAuthenticationMode]
        var missing = valid
        missing.removeValue(forKey: CoachProxyClient.endpointInfoPlistKey)
        var invalidConfigurations = [missing]
        for (key, value) in [
            (CoachProxyClient.endpointInfoPlistKey, ""),
            (CoachProxyClient.endpointInfoPlistKey, "https://coach.reptoday.app/wrong-path"),
            (CoachProxyClient.authenticationModeInfoPlistKey, "bearer"),
            (CoachProxyClient.secretInfoPlistKey, "NONSECRET_EMBEDDED_GATE_FIXTURE")
        ] {
            var invalid = valid
            invalid[key] = value
            invalidConfigurations.append(invalid)
        }
        for configuration in invalidConfigurations {
            try withConfiguration(configuration) { bundle in
                let client = CoachProxyClient.configured(
                    safetyIdentifierProvider: { testCoachSafetyIdentifier }, bundle: bundle)
                XCTAssertNil(client)
                let model = CoachViewModel(
                    client: client, userService: MockUserService(user: MockPersistence.sampleUser),
                    workoutLogService: MockWorkoutLogService(), exerciseService: try! MockExerciseService())
                XCTAssertEqual(model.localAvailability, .notEnabledInBuild)
                XCTAssertFalse(model.needsDataSharingConsent)
                XCTAssertFalse(model.canRetry)
                XCTAssertNil(model.errorMessage)
            }
        }
    }

    #endif

    func testSyntheticQASelectionRequiresEnabledFlagExactProductionModeAndEmptySecret() throws {
        let valid: [String: Any] = ["RepTodayCoachSyntheticQA": "1",
            CoachProxyClient.endpointInfoPlistKey: CoachProxyClient.productionOrigin,
            CoachProxyClient.authenticationModeInfoPlistKey: CoachProxyClient.productionAuthenticationMode,
            CoachProxyClient.secretInfoPlistKey: ""]
        try withConfiguration(valid) { XCTAssertTrue(CoachSyntheticQAConfiguration.isEnabled(bundle: $0)) }
        for (key, value) in [("RepTodayCoachSyntheticQA", "0"),
            (CoachProxyClient.endpointInfoPlistKey, "https://fixture.invalid/coach"),
            (CoachProxyClient.endpointInfoPlistKey, ""),
            (CoachProxyClient.authenticationModeInfoPlistKey, "bearer"),
            (CoachProxyClient.secretInfoPlistKey, "NONSECRET_FIXTURE")] {
            var invalid = valid
            invalid[key] = value
            try withConfiguration(invalid) { XCTAssertFalse(CoachSyntheticQAConfiguration.isEnabled(bundle: $0)) }
        }
    }
    func testExactProductionConfigurationConstructsRealRuntimeTransportOnlyOnIOS() throws {
        try withConfiguration([CoachProxyClient.endpointInfoPlistKey:CoachProxyClient.productionOrigin,
            CoachProxyClient.authenticationModeInfoPlistKey:CoachProxyClient.productionAuthenticationMode]) {bundle in
            let client=CoachProxyClient.configured(safetyIdentifierProvider:{testCoachSafetyIdentifier},bundle:bundle)
            #if os(iOS)
            XCTAssertNotNil(client?.transport as? RuntimeAuthenticatedCoachTransport);XCTAssertNil(client?.sharedSecret)
            #else
            XCTAssertNil(client)
            #endif
        }
    }
}
