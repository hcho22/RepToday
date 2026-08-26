import XCTest
@testable import RepToday

/// Tests US-AC02's build-configured resolution of the coach transport: `CoachProxyClient.configured`
/// mirrors `LiveAnalyticsService.configured` - a usable HTTPS origin yields a client, anything absent
/// or unusable yields `nil` (the coach is inert, never fatal, and the surface shows "unavailable").
/// The shared secret is optional here (an open dev Worker), unlike the required analytics secret.
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

    // MARK: - Unconfigured build is inert

    func testAppBundleHasNoCoachEndpointToday() {
        // The proxy is deploy-ready but not deployed, so both configurations expand to empty and the
        // app is inert by design. This pins that "inert, never fatal" state for the shipped build:
        // `configured()` returns nil rather than trapping.
        XCTAssertNil(CoachProxyClient.configured())
    }
}
