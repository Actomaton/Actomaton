/// Result of an effect-producing `send(_:)` call, exposing:
///
/// 1. An `AsyncSequence` of `Result<Emission, any Error>` values produced by the triggered
///    effect chain (sync `.emit` plus async `Outcome` emissions, including recursive feedbacks
///    when `tracksFeedbacks: true`). Each element is either:
///    - `.success(Emission)`: a value emitted by an effect, or
///    - `.failure(any Error)`: a **non-cancellation** error thrown by a single effect.
///
/// 2. A ``cancel()`` handle that aborts the entire chain.
///
/// ## Why errors are in-band
///
/// Multiple effects triggered by one `send` run concurrently and independently. A throwing
/// `AsyncSequence` (or a fail-fast `TaskGroup`) would tear the whole chain down the moment one
/// effect throws — cancelling unrelated sibling effects and dropping the values they would have
/// emitted. Instead, each effect's failure is surfaced as a `.failure` **element** and that
/// single effect ends, while its siblings keep emitting until the entire chain completes.
///
/// Iteration therefore never throws; it ends cleanly on both normal completion and cancellation.
/// Use ``isCancelled`` to disambiguate the two clean-finish cases. Cancellation is **not** reported
/// as a `.failure` element.
///
public struct SendResult<Emission>: AsyncSequence
{
    public typealias Element = Result<Emission, any Error>
    public typealias AsyncIterator = AsyncStream<Result<Emission, any Error>>.AsyncIterator
    public typealias Failure = Never

    private let stream: AsyncStream<Result<Emission, any Error>>

    /// The supervisor that owns the effect chain's lifecycle.
    /// Cancelling it propagates cancellation downward into the in-flight effect tasks
    /// and finishes the underlying stream.
    private let supervisor: Task<Void, Never>

    init(
        stream: AsyncStream<Result<Emission, any Error>>,
        supervisor: Task<Void, Never>
    )
    {
        self.stream = stream
        self.supervisor = supervisor
    }

    public func makeAsyncIterator() -> AsyncIterator
    {
        stream.makeAsyncIterator()
    }

    /// Cancels the underlying effect-driving task. The async sequence terminates after the
    /// in-flight effects observe cancellation and buffered values are drained.
    public func cancel()
    {
        supervisor.cancel()
    }

    /// Whether the chain was cancelled. After iteration ends, this is the only way to
    /// distinguish normal completion from cancellation (both finish the stream cleanly).
    public var isCancelled: Bool
    {
        supervisor.isCancelled
    }

    // MARK: - Non-throwing accessors (in-band errors)

    /// Drains every element — both `.success` and `.failure` — awaiting completion of the
    /// entire effect chain. Never throws.
    public var allResults: [Result<Emission, any Error>]
    {
        get async {
            var result: [Result<Emission, any Error>] = []
            for await element in self {
                result.append(element)
            }
            return result
        }
    }

    /// Returns the first element (`.success` or `.failure`), or `nil` if the chain completes
    /// without producing any. Never throws.
    ///
    /// After this returns, the rest of the stream is abandoned.
    public var firstResult: Result<Emission, any Error>?
    {
        get async {
            for await element in self {
                return element
            }
            return nil
        }
    }

    /// Drains all `.success` payloads, ignoring any `.failure` elements. Never throws.
    public var emissions: [Emission]
    {
        get async {
            var values: [Emission] = []
            for await element in self {
                if case let .success(value) = element {
                    values.append(value)
                }
            }
            return values
        }
    }

    /// Drains all `.failure` errors, ignoring any `.success` elements. Never throws.
    public var errors: [any Error]
    {
        get async {
            var errors: [any Error] = []
            for await element in self {
                if case let .failure(error) = element {
                    errors.append(error)
                }
            }
            return errors
        }
    }

    /// Awaits completion of the effect chain without collecting anything. Never throws —
    /// effect errors are reported in-band as `.failure` elements, not by throwing.
    public func completion() async
    {
        for await _ in self {}
    }
}

extension SendResult: Sendable where Emission: Sendable {}
