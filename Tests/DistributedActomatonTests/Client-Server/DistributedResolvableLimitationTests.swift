import Distributed
import DistributedActomaton
import DistributedActomatonTesting
import Foundation
import XCTest

/// Documents a toolchain limitation (verified on Xcode 26.5.0): a **generic (associated-type)**
/// `@Resolvable` distributed-actor protocol *compiles*, but **aborts at runtime** on a remote call
/// with `Expected a metadata pack but got metadata` (signal 6).
///
/// A **concrete-`Action`** `@Resolvable` protocol works fine over the wire — see `ServerEmissionSink`
/// in `DistributedObserverTests.swift`. Only the associated-type form fails, which is why a
/// framework-level generic `DistributedActomatonSink<Action>` is not viable today.
///
/// The crashing call is kept (it still compiles) but the test is skipped by default so a full
/// `swift test` stays green. Set `RUN_RESOLVABLE_CRASH_SPIKE=1` to reproduce the abort (it kills the
/// whole test process).

/// Generic over `Action` (an associated type) — the shape that aborts on remote calls.
@Resolvable
protocol DistributedActomatonProtocol<Action>: DistributedActor
    where ActorSystem: DistributedActorSystem<any Codable>
{
    associatedtype Action: Codable & Sendable
    distributed func send(_ action: Action, id: DistributedSendID?)
}

extension DistributedActomaton: DistributedActomatonProtocol {}

enum ProbeAction: Codable, Sendable
{
    case ping
}

struct ProbeState: Codable, Equatable, Sendable
{
    var pinged = false
}

final class DistributedResolvableLimitationTests: XCTestCase
{
    func test_genericResolvableProtocol_remoteSend_abortsAtRuntime() async throws
    {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["RUN_RESOLVABLE_CRASH_SPIKE"] != nil,
            "associated-type @Resolvable aborts at runtime: 'Expected a metadata pack but got metadata'"
        )

        let transport = InMemoryTransport()
        let serverSystem = InMemoryActorSystem(nodeID: "server", transport: transport)
        let clientSystem = InMemoryActorSystem(nodeID: "client", transport: transport)

        let host = DistributedActomaton<ProbeAction, ProbeState, Never, InMemoryActorSystem>(
            state: ProbeState(),
            reducer: Reducer { _, state, _ in
                state.pinged = true
                return .empty
            },
            actorSystem: serverSystem
        )

        // Resolve via the generic `@Resolvable` stub (Action bound by the existential).
        let proxy: any DistributedActomatonProtocol<ProbeAction> =
            try $DistributedActomatonProtocol.resolve(id: host.id, using: clientSystem)

        try await proxy.send(.ping, id: nil) // ← aborts here: "Expected a metadata pack but got metadata"

        let state = try await host.state
        XCTAssertTrue(state.pinged)
    }
}
