import Dispatch
import Combine

/// Subclass of `Store` that also outputs `routes`, mainly used for UIKit's navigation handling
/// without using `State` as a single source of truth.
@MainActor
open class RouteStore<Action, State, Route>: Store<Action, State>
{
    private let _routes = PassthroughSubject<Route, Never>()
    private var cancellables: [AnyCancellable] = []

    public init<Environment>(
        state: State,
        reducer: Reducer<Action, State, SendRouteEnvironment<Environment, Route>>,
        environment: Environment,
        routeType: Route.Type = Route.self // for quick type-inference
    )
    {
        super.init(
            state: state,
            reducer: reducer,
            environment: .init(environment: environment, sendRoute: self._routes.send)
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
public struct SendRouteEnvironment<Environment, Route>
{
    public var environment: Environment
    public var sendRoute: (Route) -> Void

    public init(environment: Environment, sendRoute: @escaping (Route) -> Void)
    {
        self.environment = environment
        self.sendRoute = sendRoute
    }
}
