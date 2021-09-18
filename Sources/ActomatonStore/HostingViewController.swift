import UIKit
import Combine
import SwiftUI

/// SwiftUI `View` & `Store` wrapper view controller that holds `UIHostingController`.
@MainActor
open class HostingViewController<Action, State, V: SwiftUI.View>: UIViewController
{
    private let store: Store<Action, State>
    private let makeView: @MainActor (Store<Action, State>.Proxy) -> V

    public init(
        store: Store<Action, State>,
        makeView: @escaping @MainActor (Store<Action, State>.Proxy) -> V
    )
    {
        self.store = store
        self.makeView = makeView
        super.init(nibName: nil, bundle: nil)
    }

    public required init?(coder: NSCoder)
    {
        fatalError("init(coder:) has not been implemented")
    }

    public override func viewDidLoad()
    {
        super.viewDidLoad()

        let rootView = StoreView(store: self.store, makeView: self.makeView)
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
