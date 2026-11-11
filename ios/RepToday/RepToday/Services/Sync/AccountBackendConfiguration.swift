import Foundation

/// Where this build's account backend lives (M3, ADR-0016): the Convex deployment's `.convex.cloud`
/// origin, from `Info.plist`'s `RepTodayConvexURL`, expanded from the per-configuration
/// `REPTODAY_CONVEX_URL` build setting in `project.yml`.
///
/// Debug points at the development deployment; Release is set only when the production backend is
/// released. A missing, empty or mistyped value leaves the build with no account backend: data stays
/// on the device and nothing syncs, which is never wrong-destination and never a crash.
enum AccountBackendConfiguration {
    static let convexURLInfoKey = "RepTodayConvexURL"

    /// The deployment origin, or `nil` when the build carries no usable one.
    static func convexURL(bundle: Bundle = .main) -> URL? {
        guard let raw = bundle.object(forInfoDictionaryKey: convexURLInfoKey) as? String else { return nil }
        return usableConvexURL(raw)
    }

    /// An `https` origin on `convex.cloud` with no path, query or credentials.
    static func usableConvexURL(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmed),
              components.scheme == "https",
              let host = components.host?.lowercased(),
              host.hasSuffix(".convex.cloud"),
              host.count > ".convex.cloud".count,
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil,
              components.path.isEmpty || components.path == "/" else {
            return nil
        }
        return URL(string: "https://\(host)")
    }
}
