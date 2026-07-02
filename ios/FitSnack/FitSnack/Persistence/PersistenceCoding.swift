import Foundation

/// Shared coding support for the CoreData layer (US-A04).
///
/// The domain structs are plain `Codable` value types; the CoreData entities store their
/// complex/nested fields (profile, subscription, consistency, the v6 why/duration/coldStart,
/// and logged exercises) as JSON-encoded `Data`. A single encoder/decoder pair is reused so
/// the encode and decode sides always agree on strategy - the round-trip is only lossless
/// when both match.

// MARK: - PersistenceCoder

enum PersistenceCoder {
    /// Default strategies on both sides keep dates (e.g. `Subscription.expiresAt`) exact
    /// across a JSON round-trip; never change one without the other.
    static let encoder = JSONEncoder()
    static let decoder = JSONDecoder()
}

// MARK: - PersistenceError

/// Raised when a stored CoreData record cannot be reconstructed into its domain struct.
///
/// CloudKit (US-J02) requires every attribute to be optional or have a default, so the
/// managed-object properties are optional even where the domain model is not. Conversion
/// back to a domain struct therefore fails loudly - naming the offending field or value -
/// rather than silently substituting defaults and corrupting the user's history.
enum PersistenceError: Error, Equatable, CustomStringConvertible {
    /// A logically-required attribute was `nil` in the stored record.
    case missingField(String)
    /// A stored raw value did not map to any case of its enum.
    case invalidEnum(field: String, value: String)

    var description: String {
        switch self {
        case .missingField(let field):
            return "Missing required field '\(field)' in stored record"
        case .invalidEnum(let field, let value):
            return "Stored value '\(value)' for '\(field)' is not a valid enum case"
        }
    }
}
