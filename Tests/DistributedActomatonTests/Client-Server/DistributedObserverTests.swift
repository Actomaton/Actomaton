import Distributed
import DistributedActomaton
import DistributedActomatonTesting
import Synchronization
import XCTest

/// A server `DistributedActomaton` pushes its `Emission` and `State` to a client-side
/// `DistributedActomatonObserver` (a local sink, defined below). The server resolves the observer by
/// its **concrete** generic type — parameterized only by the server's `Emission`/`State`, so no
/// `@Resolvable` — and the observer's closures run on the client node.
final class DistributedObserverTests: XCTestCase
{
    func test_observer_serverPushesEmissionsAndStateToClientObserver() async throws
    {
        let transport = InMemoryTransport()
        let serverSystem = InMemoryActorSystem(nodeID: "server", transport: transport)
        let clientSystem = InMemoryActorSystem(nodeID: "client", transport: transport)

        // Client-side collectors. Callbacks fire on the observer's (client node's) executor.
        let received = Mutex<[ObserverEmission]>([])
        let states = Mutex<[ObserverState]>([])

        let observer = DistributedActomatonObserver<ObserverEmission, ObserverState>(
            actorSystem: clientSystem,
            onEmission: { emission in
                received.withLock { $0.append(emission) }
            },
            onStateChanged: { state in
                states.withLock { $0.append(state) }
            }
        )

        let emissions = [ObserverEmission(title: "a"), ObserverEmission(title: "b")]
        let server = Server(
            state: ObserverState(),
            reducer: serverReducer,
            environment: ServerEnv(system: serverSystem, emissions: emissions),
            actorSystem: serverSystem
        )

        // Trigger the server locally; `.completion` awaits the effect — including every awaited
        // `observer.receive(...)` / `observer.stateChanged(...)` round-trip to the client.
        await server.whenLocal { local in
            await local.sendLocal(.push(observerID: observer.id)).completion
        }

        XCTAssertEqual(received.withLock { $0 }, emissions, "emissions pushed over the wire to the observer")
        XCTAssertEqual(states.withLock { $0 }, [ObserverState(count: 1)], "state snapshot pushed too")
    }
}

// MARK: - Fixtures

// Top-level (non-nested) so `_typeByName` can resolve them as generic substitutions on the wire.
struct ObserverEmission: Codable, Equatable, Sendable
{
    var title: String
}

struct ObserverState: Codable, Equatable, Sendable
{
    var count: Int = 0
}

// Server-side: triggered locally, pushes to the observer in its effect.
private enum ServerAction: Codable, Sendable
{
    case push(observerID: InMemoryActorID)
}

private struct ServerEnv: Sendable
{
    let system: InMemoryActorSystem
    let emissions: [ObserverEmission]
}

private typealias Server = DistributedActomaton<ServerAction, ObserverState, Never, InMemoryActorSystem>
private typealias Observer = DistributedActomatonObserver<ObserverEmission, ObserverState>

private let serverReducer = Reducer<ServerAction, ObserverState, ServerEnv, Never> { action, state, env in
    switch action {
    case let .push(observerID):
        state.count += 1
        let emissions = env.emissions
        let snapshot = state
        return Effect { _ in
            // Resolve the observer by its CONCRETE generic type (server knows Emission/State).
            let observer = try Observer.resolve(id: observerID, using: env.system)
            for emission in emissions {
                try await observer.receive(emission: emission) // server → client emission push
            }
            try await observer.stateChanged(snapshot) // server → client state snapshot push
            return nil
        }
    }
}

// MARK: - Observer sink (local test fixture)

/// Concrete generic observer sink: parameterized only by the server's `Emission`/`State`, so the
/// server resolves it by its concrete type (no `@Resolvable`). The closures run on the observer's
/// node and never cross the wire. Useful when the client side is not itself a `DistributedActomaton`.
private distributed actor DistributedActomatonObserver<Emission, State>
    where Emission: Codable & Sendable, State: Codable & Sendable
{
    typealias ActorSystem = InMemoryActorSystem

    let onEmission: @Sendable (Emission) -> Void
    let onStateChanged: @Sendable (State) -> Void

    init(
        actorSystem: ActorSystem,
        onEmission: @escaping @Sendable (Emission) -> Void = { _ in },
        onStateChanged: @escaping @Sendable (State) -> Void = { _ in }
    )
    {
        self.actorSystem = actorSystem
        self.onEmission = onEmission
        self.onStateChanged = onStateChanged
    }

    distributed func receive(emission: Emission)
    {
        onEmission(emission)
    }

    distributed func stateChanged(_ state: State)
    {
        onStateChanged(state)
    }
}
