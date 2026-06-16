import Distributed
import DistributedActomaton
import DistributedActomatonTesting
import XCTest

/// Verifies that a **bound-generic** `Action`/`State` — e.g. `GenericPeerAction<InMemoryActorID>` —
/// resolves as a wire generic-substitution over ``InMemoryActorSystem``. This is the exact shape the
/// *generalized* PeerToPeer demo produces: parametrizing the payload over the actor system's
/// `ActorID` turns the substitution recorded on the wire from a plain nominal type (`ChatAction`)
/// into a bound generic (`ChatAction<InMemoryActorID>`).
///
/// The repeated "top-level, non-nested" discipline keeps `_typeByName` happy for *plain* nominal
/// substitutions; the open question is whether it also holds when the substitution is itself a bound
/// generic — including on Linux, where `_typeByName` resolution is historically the most fragile. If
/// it does not, the callee's `decodeGenericSubstitutions` throws `decodingFailure`, and these remote
/// sends fail instead of mutating host state.
final class DistributedGenericActionTests: XCTestCase
{
    func test_boundGenericAction_resolvesAsWireSubstitution() async throws
    {
        let transport = InMemoryTransport()
        let hostSystem = InMemoryActorSystem(nodeID: "host", transport: transport)
        let clientSystem = InMemoryActorSystem(nodeID: "client", transport: transport)

        let host = GenericPeer(
            state: GenericPeerState(name: "host"),
            reducer: makeGenericPeerReducer(),
            environment: GenericPeerEnv(system: hostSystem),
            actorSystem: hostSystem
        )

        let proxy = try GenericPeer.resolve(id: host.id, using: clientSystem)

        // `whenLocal` returns `nil` on remote proxies, proving the call is NOT local.
        let isLocal = await proxy.whenLocal { _ in true }
        XCTAssertNil(isLocal, "resolve from another node should synthesize a remote proxy")

        let a = InMemoryActorID(nodeID: "host", number: 1)
        let b = InMemoryActorID(nodeID: "host", number: 2)

        // The argument is `GenericPeerAction<InMemoryActorID>.connect`, and the target actor's generic
        // arguments include `GenericPeerAction<InMemoryActorID>` / `GenericPeerState<InMemoryActorID>` —
        // all recorded as bound-generic substitutions the callee must resolve via `_typeByName`.
        try await proxy.send(.connect(peers: [a, b]))

        let state = try await proxy.state
        XCTAssertEqual(state.peerIDs, [a, b], "bound-generic Action/State must round-trip over the wire")
    }

    /// Mirrors the demo's fan-out: the host posts locally and forwards a `.deliver` reverse letter to
    /// each known peer, whose own node commits it locally — exercising the bound-generic `Action` in
    /// the host → peer direction too.
    func test_boundGenericAction_reverseLetterRoundTrip() async throws
    {
        let transport = InMemoryTransport()
        let hostSystem = InMemoryActorSystem(nodeID: "host", transport: transport)
        let clientSystem = InMemoryActorSystem(nodeID: "client", transport: transport)

        let host = GenericPeer(
            state: GenericPeerState(name: "host"),
            reducer: makeGenericPeerReducer(),
            environment: GenericPeerEnv(system: hostSystem),
            actorSystem: hostSystem
        )
        let client = GenericPeer(
            state: GenericPeerState(name: "client"),
            reducer: makeGenericPeerReducer(),
            environment: GenericPeerEnv(system: clientSystem),
            actorSystem: clientSystem
        )

        // Host learns the client's ID over the wire, then posts — fanning a `.deliver` letter back.
        let hostProxy = try GenericPeer.resolve(id: host.id, using: clientSystem)
        try await hostProxy.send(.connect(peers: [client.id]))

        // `.completion()` awaits the whole effect chain, including the reverse letter to the client.
        await host.whenLocal { local in
            await local.sendLocal(.post("hello")).completion()
        }

        let clientState = try await client.state
        XCTAssertEqual(clientState.received, ["hello"], "reverse-letter `.deliver` must reach the peer")
    }
}

// MARK: - Fixtures (top-level + generic, mirroring the generalized PeerToPeer demo)

// Top-level (non-nested) so `_typeByName` can resolve the *bound generic* (e.g.
// `GenericPeerState<InMemoryActorID>`) as a wire substitution.

struct GenericPeerState<ID: Codable & Sendable & Hashable>: Codable, Equatable, Sendable
{
    var name: String
    var peerIDs: [ID] = []
    var received: [String] = []
}

enum GenericPeerAction<ID: Codable & Sendable & Hashable>: Codable, Sendable
{
    case connect(peers: [ID])
    case post(String)
    case deliver(text: String)
}

// Local-only (never crosses the wire): carries the actor system so effects can resolve peers.
private struct GenericPeerEnv<System: DistributedActorSystem<any Codable>>: Sendable
    where System.ActorID: Codable & Sendable & Hashable
{
    let system: System
}

private typealias GenericPeerActomaton<System: DistributedActorSystem<any Codable>> =
    DistributedActomaton<GenericPeerAction<System.ActorID>, GenericPeerState<System.ActorID>, Never, System>
        where System.ActorID: Codable & Sendable & Hashable

private typealias GenericPeer = GenericPeerActomaton<InMemoryActorSystem>

private func makeGenericPeerReducer<System: DistributedActorSystem<any Codable>>()
    -> Reducer<GenericPeerAction<System.ActorID>, GenericPeerState<System.ActorID>, GenericPeerEnv<System>, Never>
    where System.ActorID: Codable & Sendable & Hashable
{
    Reducer { action, state, env in
        switch action {
        case let .connect(peers):
            state.peerIDs = peers
            return .empty

        case let .post(text):
            let peers = state.peerIDs
            return Effect { _ in
                // The "reverse letter": forward a follow-up action to each peer's node.
                for peerID in peers {
                    let peer = try GenericPeerActomaton<System>.resolve(id: peerID, using: env.system)
                    try await peer.send(.deliver(text: text))
                }
                return nil
            }

        case let .deliver(text):
            state.received.append(text)
            return .empty
        }
    }
}
