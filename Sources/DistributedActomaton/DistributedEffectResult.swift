/// A `Codable` stand-in for one element of ``SendResults/allResults``, so that
/// ``DistributedActomaton/sendCollectAll(_:id:tracksFeedbacks:)`` (and
/// ``DistributedActomaton/sendCollectFirst(_:id:tracksFeedbacks:)``) can convey an effect chain's
/// per-effect outcomes — successes *and* failures, in arrival order — across the wire.
///
/// `SendResults.allResults` is `[Result<Emission, any Error>]`, which cannot cross a distributed
/// boundary: `Result` has no `Codable` conformance, and an `any Error` is not `Codable` (its
/// concrete type need not even exist on the caller's node). This envelope preserves the in-band
/// success/failure distinction while staying serializable, capturing each failure as text rather
/// than as a reconstructable error value.
public enum DistributedEffectResult<Emission>: Sendable
    where Emission: Codable & Sendable
{
    /// A value emitted by an effect.
    case success(Emission)

    /// A non-cancellation error thrown by a single effect, captured as
    /// `String(describing:)`. The original error type is intentionally not carried — concrete
    /// error types need not exist on the caller's node.
    case failure(description: String)

    /// Bridges one in-band ``SendResults`` element into its serializable form, stringifying any
    /// error.
    init(_ result: Result<Emission, any Error>)
    {
        switch result {
        case let .success(emission):
            self = .success(emission)
        case let .failure(error):
            self = .failure(description: String(describing: error))
        }
    }
}

extension DistributedEffectResult: Codable {}

extension DistributedEffectResult: Equatable where Emission: Equatable {}
