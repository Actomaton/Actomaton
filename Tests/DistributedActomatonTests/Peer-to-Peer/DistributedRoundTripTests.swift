import Distributed
import DistributedActomaton
import DistributedActomatonTesting
import XCTest

/// Tests that exercise **real remote-proxy calls** over ``InMemoryActorSystem``, including the
/// full serialization round-trip (JSON-encoded invocation envelopes between two "nodes").
final class DistributedRoundTripTests: XCTestCase
{
    func test_remoteSend_runsReducerOnHostNode() async throws
    {
        let transport = InMemoryTransport()
        let hostSystem = InMemoryActorSystem(nodeID: "host", transport: transport)
        let clientSystem = InMemoryActorSystem(nodeID: "client", transport: transport)

        let host = Counter(
            state: 0,
            reducer: Reducer { action, state, _ in
                state += action
                return .empty
            },
            actorSystem: hostSystem
        )

        let proxy = try Counter.resolve(id: host.id, using: clientSystem)

        // `whenLocal` returns `nil` on remote proxies, proving we are NOT calling locally.
        let isLocal = await proxy.whenLocal { _ in true }
        XCTAssertNil(isLocal, "resolve from another node should synthesize a remote proxy")

        try await proxy.send(40)
        try await proxy.send(2)

        // The reducer runs synchronously inside the awaited remote `send`,
        // so the host state is already updated when the calls return.
        let state = try await proxy.state
        XCTAssertEqual(state, 42)
    }

    // MARK: - Echo (Emission = String) round-trips

    func test_remoteStateGetter_decodesCodableSnapshot() async throws
    {
        // `host` is unused by name: the actor system retains it for the test's duration, so the
        // remote proxy stays resolvable without an explicit lifetime extension.
        let (_, proxy) = try makeEchoPair()

        try await proxy.send("a")
        try await proxy.send("b")

        let state = try await proxy.state
        XCTAssertEqual(state, EchoState(history: ["a", "b"]))
    }

    func test_effectErrors_visibleLocallyInBand() async throws
    {
        let (host, _) = try makeEchoPair()

        // Effect failures are surfaced in-band through the **local** `SendResults` only — they
        // never cross the wire (a remote caller's `send` is fire-and-forget `Void`).
        let errorCount = await host.whenLocal { local in
            await local.sendLocal("fail").errors.count
        }
        XCTAssertEqual(errorCount, 1)
    }

    // MARK: - Action-broadcast ("reverse letter") round-trip

    /// The supported way for a remote peer to receive results: the host's reducer sends a
    /// **follow-up action** back to the subscriber, whose own node commits it locally. No
    /// `SendResults` crosses the wire; observation stays local to each node.
    func test_actionBroadcast_hostSendsFollowUpActionBackToClient() async throws
    {
        let transport = InMemoryTransport()
        let hostSystem = InMemoryActorSystem(nodeID: "host", transport: transport)
        let clientSystem = InMemoryActorSystem(nodeID: "client", transport: transport)

        let host = ChatActomaton(
            state: ChatState(),
            reducer: chatReducer,
            environment: ChatEnv(system: hostSystem),
            actorSystem: hostSystem
        )
        let client = ChatActomaton(
            state: ChatState(),
            reducer: chatReducer,
            environment: ChatEnv(system: clientSystem),
            actorSystem: clientSystem
        )

        // Client subscribes over the wire, enclosing its own `ActorID` as the return address.
        let hostProxy = try ChatActomaton.resolve(id: host.id, using: clientSystem)
        try await hostProxy.send(.subscribe(peerID: client.id))

        // Host posts locally; `.completion()` awaits the whole effect chain — including the
        // reducer-driven `peer.send(.received(...))` back to the client — so no polling is needed.
        await host.whenLocal { local in
            await local.sendLocal(.post("hello")).completion()
        }

        // The follow-up `.received` committed on the client node: observation is purely local.
        let clientState = try await client.state
        XCTAssertEqual(clientState.received, ["hello"])
    }

    // MARK: - Feedback-loop stream reconstructed via reverse letters

    /// A client action triggers a host-side **feedback loop** that produces a stream of values
    /// (multiple effects + emissions). Since a `SendResults` cannot cross the wire, the host
    /// forwards each value to the client as a follow-up `.received` action — reconstructing, on
    /// the client, the exact sequence a local `SendResults.emissions` would have yielded.
    func test_feedbackLoopStream_reconstructedOnClientViaReverseLetters() async throws
    {
        // Baseline: the emission sequence a *local* `SendResults` yields for the same loop, with
        // no forwarding (`replyTo: nil`). `tracksFeedbacks` keeps the stream open across feedback.
        let baselineSystem = InMemoryActorSystem(nodeID: "baseline", transport: InMemoryTransport())
        let baselineHost = StreamActomaton(
            state: StreamState(),
            reducer: streamReducer,
            environment: StreamEnv(system: baselineSystem, onFinished: {}),
            actorSystem: baselineSystem
        )
        let baselineEmissions = await baselineHost.whenLocal { local in
            await local.sendLocal(.start(from: 3, replyTo: nil), tracksFeedbacks: true).emissions
        }
        let baseline = try XCTUnwrap(baselineEmissions)
        XCTAssertEqual(baseline, [3, 2, 1])

        // Cross-wire: the client reconstructs the same sequence from reverse-letter `.received`s.
        let transport = InMemoryTransport()
        let hostSystem = InMemoryActorSystem(nodeID: "host", transport: transport)
        let clientSystem = InMemoryActorSystem(nodeID: "client", transport: transport)

        let (finishedStream, finishedContinuation) = AsyncStream.makeStream(of: Void.self)

        let host = StreamActomaton(
            state: StreamState(),
            reducer: streamReducer,
            environment: StreamEnv(system: hostSystem, onFinished: {}),
            actorSystem: hostSystem
        )
        let client = StreamActomaton(
            state: StreamState(),
            reducer: streamReducer,
            environment: StreamEnv(system: clientSystem, onFinished: { finishedContinuation.yield(()) }),
            actorSystem: clientSystem
        )

        let hostProxy = try StreamActomaton.resolve(id: host.id, using: clientSystem)
        try await hostProxy.send(.start(from: 3, replyTo: client.id))

        // The terminal `.finished` letter resolves this await — deterministic, no polling.
        for await _ in finishedStream {
            break
        }

        let clientState = try await client.state
        XCTAssertEqual(clientState.received, baseline, "reverse letters must reconstruct the local SendResults stream")
        XCTAssertTrue(clientState.finished)
    }

    // MARK: - Remote cancellation via DistributedSendID

    /// A remote caller cancels an in-flight host effect by **tagging the send with a
    /// `DistributedSendID`**, then sending a `.cancel(id)` action whose reducer returns
    /// `Effect.cancel(id:)`. The identifier crosses the wire twice — out-of-band on `send(_:id:)`
    /// and in-band in the `.cancel` payload — and matches by its string `rawValue`.
    func test_remoteCancellation_viaDistributedSendID() async throws
    {
        let transport = InMemoryTransport()
        let hostSystem = InMemoryActorSystem(nodeID: "host", transport: transport)
        let clientSystem = InMemoryActorSystem(nodeID: "client", transport: transport)

        let (startedStream, startedContinuation) = AsyncStream.makeStream(of: Void.self)
        let (cancelledStream, cancelledContinuation) = AsyncStream.makeStream(of: Void.self)

        let host = CancelActomaton(
            state: CancelState(),
            reducer: cancelReducer,
            environment: CancelEnv(
                onStarted: { startedContinuation.yield(()) },
                onCancelled: { cancelledContinuation.yield(()) }
            ),
            actorSystem: hostSystem
        )

        let proxy = try CancelActomaton.resolve(id: host.id, using: clientSystem)

        // Out-of-band: tag the send (and its whole effect chain) with the id.
        let jobID = DistributedSendID("job-1")
        try await proxy.send(.start, id: jobID)

        // Wait until the long effect is running, so the cancel lands on a live task.
        for await _ in startedStream {
            break
        }

        // In-band: the id rides in the action payload; the reducer turns it into `Effect.cancel(id:)`.
        try await proxy.send(.cancel(jobID))

        // The effect observes cancellation, resolving this await. If the id did not match across
        // the wire, nothing would cancel and this would hang (test timeout = failure).
        for await _ in cancelledStream {
            break
        }
    }

    private func makeEchoPair() throws -> (host: Echo, proxy: Echo)
    {
        let transport = InMemoryTransport()
        let hostSystem = InMemoryActorSystem(nodeID: "host", transport: transport)
        let clientSystem = InMemoryActorSystem(nodeID: "client", transport: transport)

        let host = Echo(
            state: EchoState(),
            reducer: echoReducer,
            actorSystem: hostSystem
        )
        let proxy = try Echo.resolve(id: host.id, using: clientSystem)
        return (host, proxy)
    }
}

extension DistributedRoundTripTests
{
    fileprivate typealias Counter = DistributedActomaton<Int, Int, Never, InMemoryActorSystem>

    fileprivate typealias Echo = DistributedActomaton<String, EchoState, String, InMemoryActorSystem>
}

// MARK: - Echo fixtures

// Top-level (non-nested) so `_typeByName` can resolve it as a generic substitution.
struct EchoState: Codable, Equatable, Sendable
{
    var history: [String] = []
}

private struct EchoError: Error {}

private let echoReducer = Reducer<String, EchoState, Void, String> { action, state, _ in
    state.history.append(action)

    if action == "fail" {
        return .emit("before-failure") + Effect { _ in throw EchoError() }
    }
    else if action == "slow" {
        return .emit("fast:\(action)") + Effect { _ in
            try await Task.sleep(for: .seconds(60))
            return .emission("never:\(action)")
        }
    }
    else {
        return .emit("sync:\(action)") + Effect { _ in .emission("async:\(action)") }
    }
}

// MARK: - Chat (action-broadcast) fixtures

// Top-level (non-nested) so `_typeByName` can resolve them as generic substitutions on the wire.
struct ChatState: Codable, Equatable, Sendable
{
    var subscribers: [InMemoryActorID] = []
    var received: [String] = []
}

enum ChatAction: Codable, Sendable
{
    case subscribe(peerID: InMemoryActorID)
    case post(String)
    case received(String)
}

// Local-only (never crosses the wire): carries the actor system so effects can resolve peers.
private struct ChatEnv: Sendable
{
    let system: InMemoryActorSystem
}

private typealias ChatActomaton = DistributedActomaton<ChatAction, ChatState, Never, InMemoryActorSystem>

private let chatReducer = Reducer<ChatAction, ChatState, ChatEnv, Never> { action, state, env in
    switch action {
    case let .subscribe(peerID):
        state.subscribers.append(peerID)
        return .empty

    case let .post(text):
        let subscribers = state.subscribers
        return Effect { _ in
            // The "reverse letter": push a follow-up action back to each subscriber's node.
            for peerID in subscribers {
                let peer = try ChatActomaton.resolve(id: peerID, using: env.system)
                try await peer.send(.received(text))
            }
            return nil
        }

    case let .received(text):
        state.received.append(text)
        return .empty
    }
}

// MARK: - Feedback-loop stream fixtures

// Top-level (non-nested) so `_typeByName` can resolve them as generic substitutions on the wire.
struct StreamState: Codable, Equatable, Sendable
{
    var received: [Int] = []
    var finished = false
}

enum StreamAction: Codable, Sendable
{
    case start(from: Int, replyTo: InMemoryActorID?) // client → host: begin a countdown stream
    case tick(remaining: Int, replyTo: InMemoryActorID?) // host-internal feedback step
    case received(Int) // host → client: one streamed value
    case finished // host → client: terminal marker
}

// Local-only: carries the actor system (to resolve peers) plus the client's completion signal.
private struct StreamEnv: Sendable
{
    let system: InMemoryActorSystem
    let onFinished: @Sendable () -> Void
}

private typealias StreamActomaton = DistributedActomaton<StreamAction, StreamState, Int, InMemoryActorSystem>

private let streamReducer = Reducer<StreamAction, StreamState, StreamEnv, Int> { action, state, env in
    switch action {
    case let .start(from, replyTo):
        // Kick off the loop via synchronous feedback.
        return .next(action: .tick(remaining: from, replyTo: replyTo))

    case let .tick(remaining, replyTo):
        guard remaining > 0 else {
            // Loop finished: close the stream with a terminal letter (only when streaming to a peer).
            guard let replyTo else { return .empty }
            return Effect { _ in
                let peer = try StreamActomaton.resolve(id: replyTo, using: env.system)
                try await peer.send(.finished)
                return nil
            }
        }
        let value = remaining
        return Effect { _ in
            // The reverse letter: forward this value to the subscriber (the wire stand-in for a
            // `SendResults` emission); `.both` re-emits it into the local stream AND feeds the loop.
            if let replyTo {
                let peer = try StreamActomaton.resolve(id: replyTo, using: env.system)
                try await peer.send(.received(value))
            }
            return .both(.tick(remaining: remaining - 1, replyTo: replyTo), value)
        }

    case let .received(value):
        state.received.append(value)
        return .empty

    case .finished:
        state.finished = true
        return Effect.fireAndForget { _ in env.onFinished() }
    }
}

// MARK: - Remote-cancellation fixtures

// Top-level (non-nested) so `_typeByName` can resolve them as generic substitutions on the wire.
struct CancelState: Codable, Equatable, Sendable {}

enum CancelAction: Codable, Sendable
{
    case start
    case cancel(DistributedSendID)
}

// Local-only: the test's "effect started" / "effect cancelled" signals.
private struct CancelEnv: Sendable
{
    let onStarted: @Sendable () -> Void
    let onCancelled: @Sendable () -> Void
}

private typealias CancelActomaton = DistributedActomaton<CancelAction, CancelState, Never, InMemoryActorSystem>

private let cancelReducer = Reducer<CancelAction, CancelState, CancelEnv, Never> { action, _, env in
    switch action {
    case .start:
        // A long effect, registered under the send's id, so `Effect.cancel(id:)` can abort it.
        return Effect { _ in
            env.onStarted()
            do {
                try await Task.sleep(for: .seconds(60))
            }
            catch {
                env.onCancelled() // CancellationError from `Effect.cancel(id:)`
            }
            return nil
        }

    case let .cancel(id):
        return Effect.cancel(id: id)
    }
}
