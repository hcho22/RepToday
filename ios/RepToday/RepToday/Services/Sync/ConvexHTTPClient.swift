import Foundation

/// A minimal client for a Convex deployment's function API (M3, ADR-0016): one authenticated HTTPS
/// POST per call to `/api/query`, `/api/mutation` or `/api/action`, with no Convex SDK - the same
/// plain-`URLSession` approach the telemetry transport takes (`convex/README.md`).
///
/// Sync never needs a live subscription, only request and response, so the HTTP API is all it uses.
/// Every call carries the signed-in account's Clerk session token as a bearer token; the deployment
/// verifies it and scopes every read and write to that account (`convex/ownership.ts`).
struct ConvexHTTPClient: Sendable {
    enum FunctionKind: String, Sendable {
        case query, mutation, action
    }

    /// The deployment's `.convex.cloud` origin.
    let deploymentURL: URL
    let session: URLSession
    /// The current Clerk session token, or `nil` when no account is signed in.
    let token: @Sendable () async throws -> String?

    init(deploymentURL: URL, session: URLSession = .shared, token: @escaping @Sendable () async throws -> String?) {
        self.deploymentURL = deploymentURL
        self.session = session
        self.token = token
    }

    /// Calls `path` (`"module:function"`) with `args` and decodes its return value.
    func call<Args: Encodable & Sendable, Value: Decodable>(
        _ kind: FunctionKind,
        _ path: String,
        args: Args,
        as valueType: Value.Type = Value.self
    ) async throws -> Value {
        guard let bearer = try await token(), !bearer.isEmpty else {
            throw SyncRemoteError.notSignedIn
        }
        var request = URLRequest(url: deploymentURL.appendingPathComponent("api").appendingPathComponent(kind.rawValue))
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(RequestBody(path: path, args: args, format: "json"))

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            switch error.code {
            case .cancelled:
                throw CancellationError()
            default:
                throw SyncRemoteError.unreachable
            }
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0

        // A function result - success or a thrown error - arrives as the JSON envelope; anything else
        // is a transport-level answer read from the status alone.
        if let envelope = try? JSONDecoder().decode(ResponseEnvelope<Value>.self, from: data) {
            switch envelope.status {
            case "success":
                guard let value = envelope.value else { throw SyncRemoteError.invalidResponse }
                return value
            case "error":
                throw Self.error(code: envelope.errorData?.code, message: envelope.errorMessage ?? "", status: status)
            default:
                throw SyncRemoteError.invalidResponse
            }
        }
        switch status {
        case 401, 403:
            throw SyncRemoteError.unauthenticated
        case 408, 429, 500...599:
            throw SyncRemoteError.unreachable
        default:
            throw SyncRemoteError.invalidResponse
        }
    }

    private static func error(code: String?, message: String, status: Int) -> SyncRemoteError {
        switch code {
        case "unauthenticated":
            return .unauthenticated
        case "account_deleting":
            return .accountDeleting
        case .some(let code):
            return .rejected(code: code, message: message)
        case nil:
            // Convex reports a token it could not verify as an error with no application code.
            return status == 401 || status == 403 ? .unauthenticated : .rejected(code: nil, message: message)
        }
    }

    private struct RequestBody<Args: Encodable>: Encodable {
        let path: String
        let args: Args
        let format: String
    }

    private struct ResponseEnvelope<Value: Decodable>: Decodable {
        let status: String
        let value: Value?
        let errorMessage: String?
        let errorData: ErrorData?

        struct ErrorData: Decodable {
            let code: String?
        }

        private enum CodingKeys: String, CodingKey {
            case status, value, errorMessage, errorData
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            status = try container.decode(String.self, forKey: .status)
            value = status == "success" ? try container.decodeIfPresent(Value.self, forKey: .value) : nil
            errorMessage = try container.decodeIfPresent(String.self, forKey: .errorMessage)
            // `errorData` is whatever a `ConvexError` carried; only an object with a `code` is read.
            errorData = try? container.decodeIfPresent(ErrorData.self, forKey: .errorData)
        }
    }
}

/// An empty argument object, for functions that take none.
struct ConvexNoArguments: Encodable, Sendable {}
