#if os(iOS) || os(tvOS)

import UIKit
import Combine
import SwiftUI

/// SwiftUI `View` & `Store` wrapper view controller that holds `UIHostingController`.
@MainActor
open class HostingViewController<Action, State, V: SwiftUI.View>: UIViewController
    where Action: Sendable, State: Sendable
{
    private let rootView: AnyView

    public init(
        store: Store<Action, State>,
        makeView: @escaping @MainActor (Store<Action, State>.Proxy) -> V
    )
    {
        self.rootView = AnyView(StoreView(store: store, makeView: makeView))
        super.init(nibName: nil, bundle: nil)
    }

    /// Initializer for `Store.ObservableProxy`.
    ///
    /// - Important:
    ///   Calling this initializer should be the same time as `ObservableProxy.state` (publisher) emits value.
    ///   Otherwise, `makeView`'s result will be `EmptyView` until first new state is arrived.
    ///
    /// - Important:
    ///   `Store.Proxy` passed to `makeView` as argument ignores setter-state-binding which doesn't support direct-state changes,
    ///   so developer must use `storeProxy.stateBinding` to convert them into new actions.
    public init(
        store: Store<Action, State>.ObservableProxy,
        makeView: @escaping @MainActor (Store<Action, State>.Proxy) -> V
    )
    {
        self.rootView = AnyView(ObservableProxyView(store: store, makeView: makeView))
        super.init(nibName: nil, bundle: nil)
    }

    public required init?(coder: NSCoder)
    {
        fatalError("init(coder:) has not been implemented")
    }

    public override func viewDidLoad()
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
private struct StoreView<Action, State, V: View>: View
    where Action: Sendable, State: Sendable
{
    @ObservedObject
    var store: Store<Action, State>

    private let makeView: @MainActor (Store<Action, State>.Proxy) -> V

    init(
        store: Store<Action, State>,
        makeView: @escaping @MainActor (Store<Action, State>.Proxy) -> V
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
private struct ObservableProxyView<Action, State, V: View>: View
    where Action: Sendable, State: Sendable
{
    @ObservedObject
    var store: Store<Action, State>.ObservableProxy

    let makeView: @MainActor (Store<Action, State>.Proxy) -> V

    init(
        store: Store<Action, State>.ObservableProxy,
        makeView: @escaping @MainActor (Store<Action, State>.Proxy) -> V
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
