import Distributed
import Foundation
import Synchronization

// NOTE: All types in this file are top-level (non-nested) so that the runtime's `_typeByName`
// can reliably resolve the mangled generic-substitution names recorded by remote calls —
// nested or function-local types carry private discriminators that some toolchains refuse to
// resolve (especially on Linux). Apply the same discipline to the `Action` / `State` /
// `Emission` fixture types you use with this system in your own tests.

/// Test-only actor ID: the hosting node plus a per-node serial number.
public struct InMemoryActorID: Hashable, Codable, Sendable
{
    public let nodeID: String
    public let number: Int

    public init(nodeID: String, number: Int)
    {
        self.nodeID = nodeID
        self.number = number
    }
}

/// Serialized remote-call request routed between ``InMemoryActorSystem`` nodes.
struct InMemoryInvocationEnvelope: Codable
{
    let targetID: InMemoryActorID
    let method: String
    let genericSubs: [String]
    let arguments: [Data]
}

/// Serialized remote-call response.
struct InMemoryReplyEnvelope: Codable
{
    let payload: Data?
    let errorDescription: String?
}

public enum InMemoryActorSystemError: Error
{
    case actorNotFound(InMemoryActorID)
    case nodeNotFound(String)
    case remote(String)
    case missingReturnPayload
    case unsupported(String)
    case decodingFailure(String)
}

/// In-process "wire" connecting multiple ``InMemoryActorSystem`` nodes.
///
/// Create one transport per test, then attach two or more systems to it:
///
/// ```swift
/// let transport = InMemoryTransport()
/// let hostSystem = InMemoryActorSystem(nodeID: "host", transport: transport)
/// let clientSystem = InMemoryActorSystem(nodeID: "client", transport: transport)
/// ```
public final class InMemoryTransport: Sendable
{
    private let systems = Mutex<[String: InMemoryActorSystem]>([:])

    public init() {}

    func register(_ system: InMemoryActorSystem)
    {
        systems.withLock { $0[system.nodeID] = system }
    }

    func system(for nodeID: String) -> InMemoryActorSystem?
    {
        systems.withLock { $0[nodeID] }
    }
}

/// Minimal `DistributedActorSystem` that performs a **real serialization round-trip**
/// (encode invocation → JSON `Data` → decode → `executeDistributedTarget`) between two
/// in-process "nodes", so that remote-proxy calls are actually exercised in tests —
/// unlike `LocalTestingDistributedActorSystem`, which never serializes anything.
///
/// Typical usage with `DistributedActomaton`:
///
/// ```swift
/// let transport = InMemoryTransport()
/// let hostSystem = InMemoryActorSystem(nodeID: "host", transport: transport)
/// let clientSystem = InMemoryActorSystem(nodeID: "client", transport: transport)
///
/// let host = MyActomaton(state: ..., reducer: ..., actorSystem: hostSystem)
///
/// // Resolving from ANOTHER node's system yields a true remote proxy.
/// let proxy = try MyActomaton.resolve(id: host.id, using: clientSystem)
/// try await proxy.send(action)  // JSON round-trips through the in-process wire
/// ```
public final class InMemoryActorSystem: DistributedActorSystem, Sendable
{
    public typealias ActorID = InMemoryActorID
    public typealias SerializationRequirement = any Codable
    public typealias InvocationEncoder = InMemoryInvocationEncoder
    public typealias InvocationDecoder = InMemoryInvocationDecoder
    public typealias ResultHandler = InMemoryResultHandler

    public let nodeID: String

    private let transport: InMemoryTransport

    private let state = Mutex<MutableState>(MutableState())

    public init(nodeID: String, transport: InMemoryTransport)
    {
        self.nodeID = nodeID
        self.transport = transport
        transport.register(self)
    }

    // MARK: - Actor lifecycle

    public func assignID<Act>(_ actorType: Act.Type) -> ActorID
        where Act: DistributedActor, Act.ID == ActorID
    {
        state.withLock {
            $0.nextNumber += 1
            return InMemoryActorID(nodeID: nodeID, number: $0.nextNumber)
        }
    }

    public func actorReady<Act>(_ actor: Act)
        where Act: DistributedActor, Act.ID == ActorID
    {
        state.withLock { $0.localActors[actor.id] = actor }
    }

    public func resignID(_ id: ActorID)
    {
        state.withLock { $0.localActors[id] = nil }
    }

    public func resolve<Act>(id: ActorID, as actorType: Act.Type) throws -> Act?
        where Act: DistributedActor, Act.ID == ActorID
    {
        // Remote node: returning `nil` makes the compiler synthesize a remote proxy.
        guard id.nodeID == nodeID else { return nil }

        guard let actor = state.withLock({ $0.localActors[id] }) else {
            throw InMemoryActorSystemError.actorNotFound(id)
        }
        guard let typed = actor as? Act else {
            throw InMemoryActorSystemError.actorNotFound(id)
        }
        return typed
    }

    public func makeInvocationEncoder() -> InvocationEncoder
    {
        InMemoryInvocationEncoder()
    }

    // MARK: - Remote calls (caller side)

    public func remoteCall<Act, Err, Res>(
        on actor: Act,
        target: RemoteCallTarget,
        invocation: inout InvocationEncoder,
        throwing: Err.Type,
        returning: Res.Type
    ) async throws -> Res
        where Act: DistributedActor, Act.ID == ActorID, Err: Error, Res: Codable
    {
        let reply = try await deliver(invocation: invocation, to: actor.id, target: target)
        if let message = reply.errorDescription {
            throw InMemoryActorSystemError.remote(message)
        }
        guard let payload = reply.payload else {
            throw InMemoryActorSystemError.missingReturnPayload
        }
        return try JSONDecoder().decode(Res.self, from: payload)
    }

    public func remoteCallVoid<Act, Err>(
        on actor: Act,
        target: RemoteCallTarget,
        invocation: inout InvocationEncoder,
        throwing: Err.Type
    ) async throws
        where Act: DistributedActor, Act.ID == ActorID, Err: Error
    {
        let reply = try await deliver(invocation: invocation, to: actor.id, target: target)
        if let message = reply.errorDescription {
            throw InMemoryActorSystemError.remote(message)
        }
    }

    private func deliver(
        invocation: InvocationEncoder,
        to targetID: InMemoryActorID,
        target: RemoteCallTarget
    ) async throws -> InMemoryReplyEnvelope
    {
        let envelope = InMemoryInvocationEnvelope(
            targetID: targetID,
            method: target.identifier,
            genericSubs: invocation.genericSubs,
            arguments: invocation.arguments
        )

        // Encode the whole envelope to `Data`, as a real wire would.
        let wireData = try JSONEncoder().encode(envelope)

        guard let remoteSystem = transport.system(for: targetID.nodeID) else {
            throw InMemoryActorSystemError.nodeNotFound(targetID.nodeID)
        }
        return try await remoteSystem.receive(wireData: wireData)
    }

    // MARK: - Remote calls (callee side)

    private func receive(wireData: Data) async throws -> InMemoryReplyEnvelope
    {
        let envelope = try JSONDecoder().decode(InMemoryInvocationEnvelope.self, from: wireData)

        guard let actor = state.withLock({ $0.localActors[envelope.targetID] }) else {
            return InMemoryReplyEnvelope(
                payload: nil,
                errorDescription: "actor not found: \(envelope.targetID)"
            )
        }

        var decoder = InMemoryInvocationDecoder(envelope: envelope)
        let handler = InMemoryResultHandler()

        do {
            try await executeDistributedTarget(
                on: actor,
                target: RemoteCallTarget(envelope.method),
                invocationDecoder: &decoder,
                handler: handler
            )
        }
        catch {
            return InMemoryReplyEnvelope(payload: nil, errorDescription: "\(error)")
        }

        return handler.takeReply()
            ?? InMemoryReplyEnvelope(payload: nil, errorDescription: "no reply recorded")
    }
}

extension InMemoryActorSystem
{
    private struct MutableState
    {
        var nextNumber: Int = 0
        var localActors: [InMemoryActorID: any DistributedActor] = [:]
    }
}

// MARK: - InMemoryInvocationEncoder

public struct InMemoryInvocationEncoder: DistributedTargetInvocationEncoder
{
    public typealias SerializationRequirement = any Codable

    private(set) var genericSubs: [String] = []
    private(set) var arguments: [Data] = []

    public mutating func recordGenericSubstitution<T>(_ type: T.Type) throws
    {
        guard let mangled = _mangledTypeName(type) else {
            throw InMemoryActorSystemError.unsupported("cannot mangle type \(type)")
        }
        genericSubs.append(mangled)
    }

    public mutating func recordArgument<Value: Codable>(_ argument: RemoteCallArgument<Value>) throws
    {
        arguments.append(try JSONEncoder().encode(argument.value))
    }

    public mutating func recordReturnType<R: Codable>(_ type: R.Type) throws {}

    public mutating func recordErrorType<E: Error>(_ type: E.Type) throws {}

    public mutating func doneRecording() throws {}
}

// MARK: - InMemoryInvocationDecoder

public struct InMemoryInvocationDecoder: DistributedTargetInvocationDecoder
{
    public typealias SerializationRequirement = any Codable

    private let envelope: InMemoryInvocationEnvelope
    private var argumentIndex: Int = 0

    init(envelope: InMemoryInvocationEnvelope)
    {
        self.envelope = envelope
    }

    public mutating func decodeGenericSubstitutions() throws -> [Any.Type]
    {
        try envelope.genericSubs.map { mangled in
            guard let type = _typeByName(mangled) else {
                throw InMemoryActorSystemError.decodingFailure("cannot resolve type \(mangled)")
            }
            return type
        }
    }

    public mutating func decodeNextArgument<Argument: Codable>() throws -> Argument
    {
        guard argumentIndex < envelope.arguments.count else {
            throw InMemoryActorSystemError.decodingFailure("no argument at index \(argumentIndex)")
        }
        defer { argumentIndex += 1 }
        return try JSONDecoder().decode(Argument.self, from: envelope.arguments[argumentIndex])
    }

    public mutating func decodeReturnType() throws -> Any.Type? {
        nil
    }

    public mutating func decodeErrorType() throws -> Any.Type? {
        nil
    }
}

// MARK: - InMemoryResultHandler

public final class InMemoryResultHandler: DistributedTargetInvocationResultHandler, Sendable
{
    public typealias SerializationRequirement = any Codable

    private let reply = Mutex<InMemoryReplyEnvelope?>(nil)

    init() {}

    func takeReply() -> InMemoryReplyEnvelope?
    {
        reply.withLock { $0 }
    }

    public func onReturn<Success: Codable>(value: Success) async throws
    {
        let payload = try JSONEncoder().encode(value)
        reply.withLock { $0 = InMemoryReplyEnvelope(payload: payload, errorDescription: nil) }
    }

    public func onReturnVoid() async throws
    {
        reply.withLock { $0 = InMemoryReplyEnvelope(payload: nil, errorDescription: nil) }
    }

    public func onThrow<Err: Error>(error: Err) async throws
    {
        reply.withLock { $0 = InMemoryReplyEnvelope(payload: nil, errorDescription: "\(error)") }
    }
}
