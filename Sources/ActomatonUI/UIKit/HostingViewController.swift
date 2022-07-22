#if os(iOS) || os(tvOS)

import UIKit
import Combine
import SwiftUI

/// SwiftUI `View` & ``Store`` wrapper view controller that holds `UIHostingController`.
@MainActor
open class HostingViewController<Action, State, Environment, Content: SwiftUI.View>: UIViewController
    where Action: Sendable, State: Sendable, Environment: Sendable
{
    private let store: Any // `Store` or `RouteStore`.
    private let rootView: AnyView

    /// Initializer for ``Store`` as argument.
    public init(
        store: Store<Action, State, Environment>,
        @ViewBuilder content: @escaping @MainActor (Store<Action, State, Environment>) -> Content
    )
    {
        self.store = store
        self.rootView = AnyView(content(store))
        super.init(nibName: nil, bundle: nil)
    }

    /// Initializer for ``RouteStore`` as argument, with forgetting ``SendRouteEnvironment/sendRoute`` capability when making `content`.
    public init<Route>(
        store routeStore: RouteStore<Action, State, Environment, Route>,
        @ViewBuilder content: @escaping @MainActor (Store<Action, State, Environment>) -> Content
    )
    {
        self.store = routeStore

        let substore = routeStore.noSendRoute
        self.rootView = AnyView(content(substore))

        super.init(nibName: nil, bundle: nil)
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

#endif
