import Dispatch
import Combine

/// `Store` wrapper that also outputs `routes`, mainly used for UIKit's navigation handling.
@MainActor
public final class RouteStore<Action, State, Environment, Route>
    : Store<Action, State, SendRouteEnvironment<Environment, Route>>
    where Action: Sendable, State: Sendable, Environment: Sendable
{
    private let core: StoreCore<Action, State, SendRouteEnvironment<Environment, Route>>
    private let _routes: PassthroughSubject<Route, Never>

    /// Initializer with `environment`.
    public init(
        state: State,
        reducer: Reducer<Action, State, SendRouteEnvironment<Environment, Route>>,
        environment: Environment,
        configuration: StoreConfiguration = .init(),
        routeType: Route.Type = Route.self // for quick type-inference
    )
    {
        let routes = PassthroughSubject<Route, Never>()
        self._routes = routes

        let sendRouteEnvironment = SendRouteEnvironment(
            environment: environment,
            sendRoute: { routes.send($0) }
        )

        let core = StoreCore<Action, State, SendRouteEnvironment<Environment, Route>>(
            state: state,
            reducer: reducer,
            environment: sendRouteEnvironment,
            configuration: configuration
        )
        self.core = core

        super.init(
            state: core.state,
            environment: sendRouteEnvironment,
            send: { core.send($0, priority: $1, tracksFeedbacks: $2) }
        )
    }

    /// Initializer without `environment`.
    public convenience init(
        state: State,
        reducer: Reducer<Action, State, SendRouteEnvironment<Void, Route>>,
        routeType: Route.Type = Route.self // for quick type-inference
    ) where Environment == Void
    {
        self.init(
            state: state,
            reducer: reducer,
            environment: ()
        )
    }

    /// `Route` publisher.
    public var routes: AnyPublisher<Route, Never>
    {
        self._routes
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
    }

    /// Subscribes `routes` until `RouteStore`'s lifetime.
    public func subscribeRoutes(_ routeHandler: @escaping (Route) -> Void)
    {
        self.routes
            .sink(receiveValue: routeHandler)
            .store(in: &self.core.cancellables)
    }
}

// MARK: - noSendRoute

extension RouteStore
{
    /// Maps `environment` from `SendRouteEnvironment<Environment, Route>` to `Environment`,
    /// erasing `SendRouteEnvironment` and `Route`.
    ///
    /// ```swift
    /// class MyViewController: UIViewController {
    ///     let store: Store<Action, State, Environment>
    ///     ...
    /// }
    ///
    /// let routeStore = RouteStore(...)
    ///
    /// // NOTE:
    /// // `vc` doesn't need to know about `RouteStore` and its route handling,
    /// // so erase with `noSendRoute`.
    /// let vc = MyViewController(store: routeStore.noSendRoute)
    ///
    /// vc.subscribeRoutes { route in ... }
    /// ```
    public var noSendRoute: Store<Action, State, Environment>
    {
        self.map(environment: \.environment)
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
    /// See ``sendRouteAsyncStream(_:)-7ezhz`` doc-comment for more information.
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
