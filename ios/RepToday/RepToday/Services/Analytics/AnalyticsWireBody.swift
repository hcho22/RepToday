import Foundation

/// The on-the-wire form of one `AnalyticsEvent` (US-T04).
///
/// This is deliberately a **second** encoding of the event rather than the model's own `Codable`
/// output. `AnalyticsValue` encodes itself in a tagged, self-describing form
/// (`{"type":"int","value":38}`) so an `Int` and a `Double` round-trip losslessly in process - a
/// US-T02 requirement that stays. The Convex sink expects the opposite: plain scalars
/// (`"props": {"generation_ms": 38}`), stored exactly as they arrive. The top-level key names
/// differ too - the sink's contract is `{name, installId, clientTs, props}`, where `name` is the
/// event name's snake_case raw value and `clientTs` is the event's `timestampMs`.
///
/// So reusing `JSONEncoder().encode(event)` would send a body the sink rejects or stores wrong,
/// and this type is where the two shapes are kept apart. See `convex/README.md` for the receiving
/// end of the same contract.
///
/// `clientTs` is encoded from a Swift `Int`, which `JSONEncoder` writes as a bare JSON number.
/// That is the pinned numeric convention (US-T03): a JSON number already *is* the float64 a
/// `v.number()` column stores, so the `int64`-vs-`float64` trap the US-T01 spike documented - a
/// Swift `Int` re-tagged by a Convex SDK as `{"$integer": …}` and then refused by the column -
/// never arises. Nothing here may re-tag it.
struct AnalyticsWireBody: Encodable, Equatable {
    /// The pre-registered event name's snake_case raw value.
    let name: String
    /// The anonymous per-install identifier (US-T05), resolved by `AppState` and passed in.
    let installId: String
    /// The event's client timestamp, milliseconds since the Unix epoch, as a bare JSON number.
    let clientTs: Int
    /// The non-identifying property bag, flattened to plain scalars.
    let props: [String: AnalyticsValue]

    init(event: AnalyticsEvent, installId: String) {
        self.name = event.name.rawValue
        self.installId = installId
        self.clientTs = event.timestampMs
        self.props = event.properties
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case installId
        case clientTs
        case props
    }

    /// An arbitrary property name. The bag's keys are the schema's pre-registered property names
    /// (`generation_ms`, `was_return`, …), so they are data rather than a fixed key set.
    private struct PropertyKey: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }

        init(_ stringValue: String) { self.stringValue = stringValue }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(installId, forKey: .installId)
        try container.encode(clientTs, forKey: .clientTs)

        // The flattening. Each `AnalyticsValue` is written as the bare scalar it wraps, so the bag
        // the sink stores holds numbers, strings, and booleans - never the tagged in-process form.
        // `props` is always written, even when empty: the action treats an absent bag as `{}`, but
        // an explicit empty object says the same thing without depending on that default.
        var properties = container.nestedContainer(keyedBy: PropertyKey.self, forKey: .props)
        for (key, value) in props {
            let propertyKey = PropertyKey(key)
            switch value {
            case .int(let scalar):
                try properties.encode(scalar, forKey: propertyKey)
            case .double(let scalar):
                try properties.encode(scalar, forKey: propertyKey)
            case .string(let scalar):
                try properties.encode(scalar, forKey: propertyKey)
            case .bool(let scalar):
                try properties.encode(scalar, forKey: propertyKey)
            }
        }
    }

    /// Encodes one event into the request body the sink's `POST /logEvent` route expects.
    ///
    /// Keys are sorted so a given event always produces byte-identical output, which keeps the
    /// wire form reproducible for tests and for a hand-run validation transcript.
    static func encode(_ event: AnalyticsEvent, installId: String) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(AnalyticsWireBody(event: event, installId: installId))
    }
}
