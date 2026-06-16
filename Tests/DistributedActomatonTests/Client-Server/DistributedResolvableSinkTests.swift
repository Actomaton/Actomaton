import Distributed
import DistributedActomaton
import DistributedActomatonTesting
import XCTest

/// Asymmetric push **with the receiver's `State` type-erased**. The client receiver is a full
/// ``DistributedActomaton`` whose `Action` *is* the server's emission type (`ServerEmission`), but the
/// server resolves it through a concrete-`Action` `@Resolvable` protocol (`any ServerEmissionSink`).
/// So the server's source references only `ServerEmission` — never the receiver's `ClientState`,
/// removing the coupling a concrete-type resolve would carry.
///
/// The protocol method is **concrete** (not an associated type), so unlike a generic
/// `Sink<Action>` it resolves and calls over the wire without aborting — see
/// `DistributedResolvableLimitationTests` for the associated-type form that crashes.
final class DistributedResolvableSinkTests: XCTestCase
{
    func test_typeErasedSink_serverPushesToClientActomatonWithoutNamingClientState() async throws
    {
        let transport = InMemoryTransport()
        let serverSystem = InMemoryActorSystem(nodeID: "server", transport: transport)
        let clientSystem = InMemoryActorSystem(nodeID: "client", transport: transport)

        let emissions = [ServerEmission(title: "a"), ServerEmission(title: "b")]

        // The receiver is a full DistributedActomaton; its `Action` is `ServerEmission`.
        let client = Client(
            state: ClientState(),
            reducer: clientReducer,
            actorSystem: clientSystem
        )

        let server = Server(
            state: ServerState(),
            reducer: serverReducer,
            environment: ServerEnv(system: serverSystem, emissions: emissions),
            actorSystem: serverSystem
        )

        await server.whenLocal { local in
            await local.sendLocal(.push(receiverID: client.id)).completion()
        }

        let clientState = try await client.state
        XCTAssertEqual(
            clientState.received,
            emissions,
            "type-erased sink delivered; server never named ClientState"
        )
    }
}

// MARK: - @Resolvable sink (concrete `Action`)

/// Concrete-`Action` `@Resolvable` protocol: its method is `send(_: ServerEmission, …)` — not an
/// associated type — so it works over the wire. The server resolves `any ServerEmissionSink`, naming
/// only `ServerEmission`, never the receiver's `State`.
@Resolvable
protocol ServerEmissionSink: DistributedActor where ActorSystem: DistributedActorSystem<any Codable>
{
    distributed func send(_ emission: ServerEmission, id: DistributedSendID?)
}

// Any `DistributedActomaton` whose `Action` is `ServerEmission` is a `ServerEmissionSink`. The
// conditional conformance constrains only `Action`, so `State`/`Emission` stay unconstrained — the
// receiver keeps its own (possibly private) `State` while the server addresses it type-erased.
extension DistributedActomaton: ServerEmissionSink where Action == ServerEmission {}

// MARK: - Server fixtures

// Top-level (non-nested) so `_typeByName` can resolve it as a generic substitution on the wire.
struct ServerEmission: Codable, Equatable, Sendable
{
    var title: String
}

private struct ServerState: Codable, Equatable, Sendable {}

private enum ServerAction: Codable, Sendable
{
    case push(receiverID: InMemoryActorID)
}

private struct ServerEnv: Sendable
{
    let system: InMemoryActorSystem
    let emissions: [ServerEmission]
}

private typealias Server = DistributedActomaton<ServerAction, ServerState, Never, InMemoryActorSystem>

private let serverReducer = Reducer<ServerAction, ServerState, ServerEnv, Never> { action, _, env in
    switch action {
    case let .push(receiverID):
        let emissions = env.emissions
        return Effect { _ in
            // Resolve `any ServerEmissionSink`: server names ONLY `ServerEmission`, never `ClientState`.
            let sink: any ServerEmissionSink =
                try $ServerEmissionSink.resolve(id: receiverID, using: env.system)
            for emission in emissions {
                try await sink.send(emission, id: nil)
            }
            return nil
        }
    }
}

// MARK: - Client (receiver) fixtures

// Top-level (non-nested) so `_typeByName` can resolve it as a generic substitution on the wire.
struct ClientState: Codable, Equatable, Sendable
{
    var received: [ServerEmission] = []
}

private typealias Client = DistributedActomaton<ServerEmission, ClientState, Never, InMemoryActorSystem>

private let clientReducer = Reducer<ServerEmission, ClientState, Void, Never> { emission, state, _ in
    state.received.append(emission)
    return .empty
}
