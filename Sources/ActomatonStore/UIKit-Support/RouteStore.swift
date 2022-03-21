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

    public init(environment: Environment, sendRoute: @Sendable @escaping (Route) -> Void)
    {
        self.environment = environment
        self.sendRoute = sendRoute
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
