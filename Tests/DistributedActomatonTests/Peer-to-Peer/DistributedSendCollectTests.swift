import Distributed
import DistributedActomaton
import DistributedActomatonTesting
import XCTest

/// Tests for the collecting distributed face — ``DistributedActomaton/sendCollectAll(_:id:tracksFeedbacks:)``
/// and ``DistributedActomaton/sendCollectFirst(_:id:tracksFeedbacks:)`` — which await the effect chain
/// and return its outcomes as `Codable` ``DistributedEffectResult`` values.
final class DistributedSendCollectTests: XCTestCase
{
    // MARK: - sendCollectAll

    func test_sendCollectAll_returnsAllOutcomes_inArrivalOrder() async throws
    {
        let actomaton = makeLocal()

        // `.values` emits a synchronous `v0` then an asynchronous `v1`, so arrival order is fixed.
        let results = try await actomaton.sendCollectAll(.values)
        XCTAssertEqual(results, [.success("v0"), .success("v1")])
    }

    func test_sendCollectAll_includesInBandFailure_afterSuccess() async throws
    {
        let actomaton = makeLocal()

        // `.failing` emits `before`, then a sibling effect throws — surfaced in-band, not by throwing.
        let results = try await actomaton.sendCollectAll(.failing)

        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results.first, .success("before"))
        try assertFailure(results.last, descriptionContains: "CollectError")
    }

    func test_sendCollectAll_emptyWhenNoOutcomes() async throws
    {
        let actomaton = makeLocal()

        let results = try await actomaton.sendCollectAll(.silent)
        XCTAssertEqual(results, [])
    }

    func test_sendCollectAll_tracksFeedbacks_collectsDescendantEmissions() async throws
    {
        let actomaton = makeLocal()

        // `.ping` emits `ping` and feeds `.pong`, whose effect emits `pong`.
        let untracked = try await actomaton.sendCollectAll(.ping)
        XCTAssertEqual(untracked, [.success("ping")], "feedback descendant must NOT be collected by default")

        let tracked = try await actomaton.sendCollectAll(.ping, tracksFeedbacks: true)
        XCTAssertEqual(tracked, [.success("ping"), .success("pong")], "tracksFeedbacks must collect the descendant")
    }

    // MARK: - sendCollectFirst

    func test_sendCollectFirst_returnsFirstOutcome() async throws
    {
        let actomaton = makeLocal()

        let first = try await actomaton.sendCollectFirst(.values)
        XCTAssertEqual(first, .success("v0"))
    }

    func test_sendCollectFirst_nilWhenNoOutcomes() async throws
    {
        let actomaton = makeLocal()

        let first = try await actomaton.sendCollectFirst(.silent)
        XCTAssertNil(first)
    }

    // MARK: - Over-the-wire serialization

    /// Proves `[DistributedEffectResult]` actually crosses the wire (JSON round-trip), unlike the
    /// non-`Codable` `SendResults.allResults` it bridges from. Both a success and a stringified
    /// failure survive the trip.
    func test_sendCollectAll_overTheWire_serializesOutcomes() async throws
    {
        let transport = InMemoryTransport()
        let hostSystem = InMemoryActorSystem(nodeID: "host", transport: transport)
        let clientSystem = InMemoryActorSystem(nodeID: "client", transport: transport)

        let host = CollectActomaton(
            state: CollectState(),
            reducer: collectReducer,
            actorSystem: hostSystem
        )
        let proxy = try CollectActomaton.resolve(id: host.id, using: clientSystem)

        // `whenLocal` returns `nil` on a remote proxy, proving the call really serializes.
        let isLocal = await proxy.whenLocal { _ in true }
        XCTAssertNil(isLocal, "resolve from another node should synthesize a remote proxy")

        let results = try await proxy.sendCollectAll(.failing)

        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results.first, .success("before"))
        try assertFailure(results.last, descriptionContains: "CollectError")
    }

    // MARK: - Helpers

    private func makeLocal() -> LocalCollectActomaton
    {
        LocalCollectActomaton(
            state: CollectState(),
            reducer: collectReducer,
            actorSystem: LocalTestingDistributedActorSystem()
        )
    }

    private func assertFailure(
        _ result: DistributedEffectResult<String>?,
        descriptionContains needle: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        guard case let .failure(description) = result else {
            return XCTFail("expected a .failure element, got \(String(describing: result))", file: file, line: line)
        }
        XCTAssertTrue(description.contains(needle), "description = \(description)", file: file, line: line)
    }
}

extension DistributedSendCollectTests
{
    fileprivate typealias LocalCollectActomaton =
        DistributedActomaton<CollectAction, CollectState, String, LocalTestingDistributedActorSystem>
}

private typealias CollectActomaton =
    DistributedActomaton<CollectAction, CollectState, String, InMemoryActorSystem>

// MARK: - Fixtures

// Top-level (non-nested) so `_typeByName` can resolve them as generic substitutions on the wire.
struct CollectState: Codable, Equatable, Sendable {}

enum CollectAction: Codable, Sendable
{
    case values  // sync `v0` + async `v1`
    case failing // sync `before` + a sibling effect that throws
    case silent  // no outcomes
    case ping    // emits `ping`, then feeds `.pong`
    case pong    // emits `pong`
}

private struct CollectError: Error {}

private let collectReducer = Reducer<CollectAction, CollectState, Void, String> { action, _, _ in
    switch action {
    case .values:
        return .emit("v0") + Effect { _ in .emission("v1") }

    case .failing:
        return .emit("before") + Effect { _ in throw CollectError() }

    case .silent:
        return .empty

    case .ping:
        // Async emission + feedback: emits `ping` and feeds `.pong` (a tracked descendant).
        return Effect { _ in .both(.pong, "ping") }

    case .pong:
        return Effect { _ in .emission("pong") }
    }
}
