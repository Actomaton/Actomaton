import Dispatch
import Combine

/// Subclass of `Store` that also outputs `routes`, mainly used for UIKit's navigation handling
/// without using `State` as a single source of truth.
@MainActor
open class RouteStore<Action, State, Environment, Route>: Store<Action, State, SendRouteEnvironment<Environment, Route>>
    where Action: Sendable, State: Sendable, Environment: Sendable
{
    private let _routes: PassthroughSubject<Route, Never>
    private var cancellables: [AnyCancellable] = []

    public init(
        state: State,
        reducer: Reducer<Action, State, SendRouteEnvironment<Environment, Route>>,
        environment: Environment,
        routeType: Route.Type = Route.self // for quick type-inference
    )
    {
        let routes = PassthroughSubject<Route, Never>()
        self._routes = routes

        super.init(
            state: state,
            reducer: reducer,
            environment: .init(environment: environment, sendRoute: { routes.send($0) })
        )
    }

    /// `Route` publisher.
    public var routes: AnyPublisher<Route, Never>
    {
        self._routes
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
    }

    /// Subscribes `routes` until `Store`'s lifetime.
    public func subscribeRoutes(_ routeHandler: @escaping (Route) -> Void)
    {
        self.routes
            .sink(receiveValue: routeHandler)
            .store(in: &self.cancellables)
    }
}

// MARK: - SendRouteEnvironment

/// Wrapper of original `environment` with attaching `sendRoute`.
public struct SendRouteEnvironment<Environment, Route>: Sendable
    where Environment: Sendable
{
    public var environment: Environment
    public var sendRoute: @Sendable (Route) -> Void

    public init(environment: Environment, sendRoute: @escaping @Sendable (Route) -> Void)
    {
        self.environment = environment
        self.sendRoute = sendRoute
    }

    // MARK: sendRouteAsync

    /// Sends `Route` with a callback that consumes `Value`.
    ///
    /// For example:
    ///
    /// ```swift
    /// enum Route: Sendable {
    ///     /// `Arg` is for setting up next screen, `Value` is generated from next screen.
    ///     case showNextScreen(Arg, completion: (Value) -> Void)
    /// }
    ///
    /// ...
    ///
    /// // Inside `RouteStore`'s Reducer:
    /// Effect {
    ///     /// Send `Route` and get `Value` from next screen.
    ///     let value = await environment.sendRouteAsync { completion in
    ///         return Route.showNextScreen(someArg, completion)
    ///     }
    ///     return Action.didFinishNextScreen(value)
    /// }
    /// ```
    ///
    /// - Parameter makeRoute:
    ///   `Route` builder that takes `Value`-consumer (callback) as argument
    ///   so that sender calls `sendRoute` and can also receive `Value` asynchronously via callback.
    ///
    /// - Returns: `Value` from routed destination asynchronously.
    public func sendRouteAsync<Value>(
        _ makeRoute: ((Value) -> Void) -> Route
    ) async -> Value
    {
        await withCheckedContinuation { continuation in
            let route = makeRoute(continuation.resume(returning:))
            self.sendRoute(route)
        }
    }

    /// Sends `Route` with a callback that consumes `Result<Value, Error>`.
    ///
    /// For example:
    ///
    /// ```swift
    /// enum Route: Sendable {
    ///     /// `Arg` is for setting up next screen, `Result<Value, Error>` is generated from next screen.
    ///     case showNextScreen(Arg, completion: (Result<Value, Error>) -> Void)
    /// }
    ///
    /// ...
    ///
    /// // Inside `RouteStore`'s Reducer:
    /// Effect {
    ///     do {
    ///         /// Send `Route` and get `Value` from next screen.
    ///         let value = try await environment.sendRouteAsync { completion in
    ///             return Route.showNextScreen(someArg, completion)
    ///         }
    ///         return Action.didFinishNextScreen(value)
    ///     } catch {
    ///         return Action.didFailNextScreen(error)
    ///     }
    /// }
    /// ```
    ///
    /// - Parameter makeRoute:
    ///   `Route` builder that takes `Value`-consumer (callback) as argument
    ///   so that sender calls `sendRoute` and can also receive `Value` asynchronously via callback.
    ///
    /// - Returns: `Value` from routed destination asynchronously.
    public func sendRouteAsync<Value, Error>(
        _ makeRoute: ((Result<Value, Error>) -> Void) -> Route
    ) async throws -> Value
        where Error: Swift.Error
    {
        try await withCheckedThrowingContinuation { continuation in
            let route = makeRoute(continuation.resume(with:))
            self.sendRoute(route)
        }
    }

    // MARK: sendRouteAsyncStream

    /// Sends `Route` with `AsyncStream<Value>.Continuation` that can consume multiple `Value`s.
    ///
    /// For example:
    ///
    /// ```swift
    /// enum Route: Sendable {
    ///     /// `Arg` is for setting up next screen, `Event` is generated from next screen.
    ///     case showNextScreen(Arg, AsyncStream<Event>.Continuation)
    ///
    ///     enum Event {
    ///         case onNext(Int)
    ///         case onCompleted
    ///     }
    /// }
    ///
    /// ...
    ///
    /// // Inside `RouteStore`'s Reducer:
    /// Effect(sequence: {
    ///     /// Send `Route` and get `AsyncStream` from next screen.
    ///     let stream = environment.sendRouteAsyncStream { continuation in
    ///         return Route.showNextScreen(someArg, continuation)
    ///     }
    ///
    ///     return stream.map { event in
    ///         switch event {
    ///         case let .onNext(value):
    ///             return Action._didReceiveValue(value)
    ///         case let .onCompleted:
    ///             return Action._didFinishReceivingValues
    ///         }
    ///     }
    /// })
    ///
    /// ...
    ///
    /// store.subscribeRoutes { [weak vc] route in
    ///     switch route {
    ///     case let .showNextScreen(arg, continuation):
    ///         let nextVC = NextViewController(arg: arg)
    ///         nextVC.onData = { data in
    ///             continuation.yield(.onNext(data))
    ///         }
    ///         nextVC.onFinished = { [weak vc] in
    ///             vc?.dismiss(animated: true) {
    ///                 continuation.yield(.onCompleted)
    ///                 continuation.finish()
    ///             }
    ///         }
    ///         vc.present(nextVC, animated: true)
    ///     }
    /// }
    /// ```
    ///
    /// - Parameter makeRoute:
    ///   `Route` builder that takes `Value`-consumer (continuation as observer) as argument
    ///   so that sender calls `sendRoute` and can also receive `Value`s asynchronously via stream.
    ///
    /// - Returns: `AsyncStream<Value>` from routed destination.
    public func sendRouteAsyncStream<Value>(
        _ makeRoute: @escaping (AsyncStream<Value>.Continuation) -> Route
    ) -> AsyncStream<Value>
    {
        AsyncStream<Value> { continuation in
            let route = makeRoute(continuation)
            self.sendRoute(route)
        }
    }

    /// Sends `Route` with `AsyncThrowingStream<Value, Error>.Continuation` that can consume multiple `Value`s.
    ///
    /// See ``sendRouteAsyncStream(_:)-8alh0`` doc-comment for more information.
    ///
    /// - Parameter makeRoute:
    ///   `Route` builder that takes `Value`-consumer (continuation as observer) as argument
    ///   so that sender calls `sendRoute` and can also receive `Value` asynchronously via stream.
    ///
    /// - Returns: `AsyncThrowingStream<Value, Error>` from routed destination.
    public func sendRouteAsyncStream<Value>(
        _ makeRoute: @escaping (AsyncThrowingStream<Value, Swift.Error>.Continuation) -> Route
    ) -> AsyncThrowingStream<Value, Swift.Error>
    {
        // NOTE:
        // Need to use `Swift.Error` and can't make it as generic error type
        // due to `AsyncThrowingStream.init` having equality constraint.
        AsyncThrowingStream<Value, Swift.Error> { continuation in
            let route = makeRoute(continuation)
            self.sendRoute(route)
        }
    }
}

// MARK: - Reducer.forwardActions

extension Reducer
{
    /// `RouteStore` reducer type that forwards all input `Action`s as output routes without state changes.
    public static func forwardActions<InnerEnvironment>()
        -> Reducer<Action, State, SendRouteEnvironment<InnerEnvironment, Action>>
    where
        Environment == SendRouteEnvironment<InnerEnvironment, Action>,
        Action: Sendable
    {
        .init { action, state, env in
            Effect.fireAndForget {
                env.sendRoute(action)
            }
        }
    }
}
