#if DEBUG
import Foundation

/// A Debug-only switch that takes the account backend offline for this launch, so an airplane-mode
/// session can be walked in the Simulator (M3 verification): `-RepTodaySyncOffline YES` makes every
/// sync request fail exactly as it does with no connection, while the rest of the app - including
/// Clerk - keeps its network. The Simulator shares the Mac's connection and has no airplane mode of its
/// own, and turning the Mac's network off would cut every other process on it.
///
/// Compiled out of Release. The real airplane-mode check is on a device.
enum SyncOfflineSimulation {
    static let launchArgument = "RepTodaySyncOffline"

    static var isActive: Bool {
        UserDefaults.standard.bool(forKey: launchArgument)
    }

    /// A session whose every request fails with `notConnectedToInternet`.
    static func offlineSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [NoConnectionProtocol.self]
        return URLSession(configuration: configuration)
    }

    private final class NoConnectionProtocol: URLProtocol {
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
        }
        override func stopLoading() {}
    }
}
#endif
