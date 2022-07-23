#if os(iOS) || os(tvOS)

import UIKit
import Combine
import SwiftUI

/// SwiftUI `View` & ``Store`` wrapper view controller that holds `UIHostingController`.
@MainActor
open class HostingViewController<Action, State, Environment, V: SwiftUI.View>: UIViewController
    where Action: Sendable, State: Sendable, Environment: Sendable
{
    private let rootView: AnyView

    /// Initializer for ``Store`` as argument.
    public init(
        store: Store<Action, State, Environment>,
        makeView: @escaping @MainActor (Store<Action, State, Environment>.Proxy) -> V
    )
    {
        self.rootView = AnyView(StoreView(store: store, makeView: makeView))
        super.init(nibName: nil, bundle: nil)
    }

    /// Initializer for ``RouteStore`` as argument, with forgetting ``SendRouteEnvironment/sendRoute`` capability when `makeView`.
    public init<Route>(
        routeStore: RouteStore<Action, State, Environment, Route>,
        makeView: @escaping @MainActor (Store<Action, State, Environment>.Proxy) -> V
    )
    {
        self.rootView = AnyView(StoreView(store: routeStore, makeView: { store in
            makeView(store.map(environment: \.environment))
        }))
        super.init(nibName: nil, bundle: nil)
    }

    /// Helper initializer for ``Store`` (or ``RouteStore``) as argument, with fogetting `Environment` as `Void` when `makeView`.
    public static func make(
        store: Store<Action, State, Environment>,
        makeView: @escaping @MainActor (Store<Action, State, Void>.Proxy) -> V
    ) -> HostingViewController<Action, State, Environment, V>
    {
        HostingViewController(store: store, makeView: { store in
            makeView(store.map(environment: { _ in () }))
        })
    }

    /// Initializer for `Store.ObservableProxy` as argument.
    ///
    /// - Important:
    ///   Calling this initializer should be the same time as `ObservableProxy.state` (publisher) emits value.
    ///   Otherwise, `makeView`'s result will be `EmptyView` until first new state is arrived.
    ///
    /// - Important:
    ///   `Store.Proxy` passed to `makeView` as argument ignores setter-state-binding which doesn't support direct-state changes,
    ///   so developer must use `storeProxy.stateBinding` to convert them into new actions.
    public init(
        store: Store<Action, State, Environment>.ObservableProxy,
        makeView: @escaping @MainActor (Store<Action, State, Environment>.Proxy) -> V
    )
    {
        self.rootView = AnyView(ObservableProxyView(store: store, makeView: makeView))
        super.init(nibName: nil, bundle: nil)
    }

    /// Helper initializer for ``Store/ObservableProxy-swift.class`` as argument, with fogetting `Environment` as `Void` when `makeView`.
    public static func make(
        store: Store<Action, State, Environment>.ObservableProxy,
        makeView: @escaping @MainActor (Store<Action, State, Void>.Proxy) -> V
    ) -> HostingViewController<Action, State, Environment, V>
    {
        HostingViewController(store: store, makeView: { store in
            makeView(store.map(environment: { _ in () }))
        })
    }

    public required init?(coder: NSCoder)
    {
        fatalError("init(coder:) has not been implemented")
    }

    open override func viewDidLoad()
    {
        super.viewDidLoad()

        let hostVC = UIHostingController(rootView: rootView)
        hostVC.view.translatesAutoresizingMaskIntoConstraints = false

        self.addChild(hostVC)
        self.view.addSubview(hostVC.view)
        hostVC.didMove(toParent: self)

        NSLayoutConstraint.activate([
            self.view.leadingAnchor.constraint(equalTo: hostVC.view.leadingAnchor),
            self.view.trailingAnchor.constraint(equalTo: hostVC.view.trailingAnchor),
            self.view.topAnchor.constraint(equalTo: hostVC.view.topAnchor),
            self.view.bottomAnchor.constraint(equalTo: hostVC.view.bottomAnchor)
        ])
    }
}

// MARK: - Private

/// View to hold `Store` as `@ObservedObject`.
private struct StoreView<Action, State, Environment, V: View>: View
    where Action: Sendable, State: Sendable, Environment: Sendable
{
    @ObservedObject
    var store: Store<Action, State, Environment>

    private let makeView: @MainActor (Store<Action, State, Environment>.Proxy) -> V

    init(
        store: Store<Action, State, Environment>,
        makeView: @escaping @MainActor (Store<Action, State, Environment>.Proxy) -> V
    )
    {
        self.store = store
        self.makeView = makeView
    }

    var body: some View
    {
        self.makeView(self.store.proxy)
    }
}

/// View to hold `Store.ObservableProxy` as `@ObservedObject`.
private struct ObservableProxyView<Action, State, Environment, V: View>: View
    where Action: Sendable, State: Sendable, Environment: Sendable
{
    @ObservedObject
    var store: Store<Action, State, Environment>.ObservableProxy

    let makeView: @MainActor (Store<Action, State, Environment>.Proxy) -> V

    init(
        store: Store<Action, State, Environment>.ObservableProxy,
        makeView: @escaping @MainActor (Store<Action, State, Environment>.Proxy) -> V
    )
    {
        self.store = store
        self.makeView = makeView
    }

    var body: some View
    {
        if let storeProxy = self.store.unsafeProxy.traverse(\.self) {
            self.makeView(storeProxy)
        }
        else {
            let _ = print("[ActomatonStore] `HostingViewController` failed to make view due to missing initial state arrival from `Store.ObservableProxy.state`.")
        }
    }
}

#endif
