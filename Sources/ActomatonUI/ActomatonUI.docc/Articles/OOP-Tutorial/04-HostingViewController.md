# 4. HostingViewController

``HostingViewController`` を使った ``RouteStore`` と SwiftUI の連携

## Overview

<doc:03-RouteStore> では、 UIKit を使った `ViewController` 画面を仮定して builder とルーティングを設計しましたが、
SwiftUI の `UIHostingController` を使った場合でも同様の方法で作ることができます。

その際には ActomatonUI モジュールが提供する ``HostingViewController`` の利用を検討してみて下さい。

## HostingViewController (for SwiftUI)

``HostingViewController`` はイニシャライザとして ``HostingViewController/init(store:content:)-5otox`` を持ち、
<doc:03-RouteStore> の UIKit の例と同じく `store` を第 1 引数に受け取ることができます。

``HostingViewController`` の使用例は、次の通りです：

```swift
import SwiftUI
import ActomatonUI

// SwiftUI View の例
@MainActor
struct ContentView: View {
    private let store: Store<Action, State, Environment>

    init(store: Store<Action, State, Environment>) {
        self.store = store
    }

    var body: some View {
        WithViewStore(self.store) { viewStore in
            HStack {
                Text("\(viewStore.state.count)")

                Button(action: { store.send(.increment) }) {
                    Image(systemName: "plus.circle")
                }

                Button(action: { store.send(.push) }) {
                    Text("Navigation Push")
                }
            }
        }
    }
}

enum SwiftUIBuilder {
    static func buildNavigation() -> UIViewController {
        // RouteStore (ViewModel) の作成（前ページと同じ）
        let routeStore = RouteStore(
            state: State(),
            reducer: reducer,
            routeType: Route.self
        )

        // HostingViewController を使った ViewController の作成
        let vc = HostingViewController(store: routeStore, content: ContentView.init)

        let navC = UINavigationController(rootViewController: vc)

        // ルーティング処理（前ページと同じ）
        store.subscribeRoutes { [weak navC] route in
            switch route {
            case let .push(count):
                let vc = NextBuilder.build(count: count)
                navC?.pushViewController(vc, animated: true)
            }
        }

        return navC
    }
}
```

ここで、 `HostingViewController` 初期化時の `content` に `ContentView` (SwiftUI View) のイニシャライザを渡します。
同時に渡している `RouteStore` は、 `ContentView` の中では親クラスの `Store` に変換されます。

> Note:
> `ContentView` 内部では、ルーティングに関する知識は必要ないため、 ``RouteStore`` は ``Store`` に
> アップキャストで忘却されています。

## Next Step

<doc:05-ViewStore>
