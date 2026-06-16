import ActomatonEffect
import Foundation

/// A `Codable` cancellation identifier for a distributed `send`, suitable for crossing the wire.
///
/// ``DistributedActomaton``'s distributed `send` family is fire-and-forget across the network, so a
/// remote caller cannot hold the local `SendResults` handle that ``DistributedActomaton/sendLocal``
/// returns. To still make a previously-issued send cancellable, tag it with a `DistributedSendID`
/// and route an ordinary cancel action back through the remote reducer:
///
/// ```swift
/// let id = DistributedSendID()              // globally-unique (UUID-backed) by default
/// try await actor.send(.startDownload, id: id)
/// // …later, the remote reducer turns `.cancel(id)` into `Effect.cancel(id:)`:
/// try await actor.send(.cancel(id))
/// ```
///
/// ## Why UUID-backed by default
///
/// On the host, every remote caller's `send(id:)` funnels into a single cancellation registry keyed
/// by the identifier's value. A client-local counter (`0, 1, 2…`) would therefore collide across
/// clients — client A's `.cancel(1)` could abort client B's send. The default ``init()`` sidesteps
/// this with a `UUID`, which is globally unique without any cross-client coordination, and also
/// distinguishes the many concurrent sends a single client may have in flight.
///
/// For reproducible or human-readable identifiers (tests, logs, or namespaced schemes such as
/// `"download-\(itemID)"`), use ``init(_:)`` or a string literal instead — but then *you* own
/// uniqueness across clients, e.g. by prefixing a stable client identifier.
///
/// - Note: Cancellation matching is by value of ``rawValue`` *and* concrete type (`_EffectID` uses
///   `AnyHashable`), so a reducer-side `Effect.cancel(id:)` must use a `DistributedSendID` carrying
///   the same `rawValue` — a bare `String` with the same contents will not match.
public struct DistributedSendID: EffectID
{
    /// The underlying identifier value. Equality and hashing — and therefore cancellation
    /// matching — are entirely by this string.
    public let rawValue: String

    /// Creates a globally-unique identifier backed by a fresh `UUID`.
    public init()
    {
        self.rawValue = UUID().uuidString
    }

    /// Creates an identifier from an explicit string. The caller owns cross-client uniqueness.
    public init(_ rawValue: String)
    {
        self.rawValue = rawValue
    }
}

extension DistributedSendID: ExpressibleByStringLiteral
{
    public init(stringLiteral value: String)
    {
        self.init(value)
    }
}

extension DistributedSendID: CustomStringConvertible
{
    public var description: String
    {
        rawValue
    }
}

extension DistributedSendID: Codable
{
    // Encode/decode as a bare string rather than `{ "rawValue": ... }`, keeping the wire form
    // compact and consistent with the `ExpressibleByStringLiteral` surface.
    public init(from decoder: any Decoder) throws
    {
        let container = try decoder.singleValueContainer()
        self.rawValue = try container.decode(String.self)
    }

    public func encode(to encoder: any Encoder) throws
    {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
