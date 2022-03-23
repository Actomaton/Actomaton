# 4. HostingViewController

``HostingViewController`` を使った ``RouteStore`` と SwiftUI の連携

## Overview

<doc:03-RouteStore> では、 UIKit を使った `ViewController` 画面を仮定して builder とルーティングを設計しましたが、
SwiftUI の `UIHostingController` を使った場合でも同様の方法で作ることができます。

その際には ActomatonStore モジュールが提供する ``HostingViewController`` の利用を検討してみて下さい。

## HostingViewController (for SwiftUI)

``HostingViewController`` はイニシャライザとして ``HostingViewController/init(store:makeView:)-6i0iw`` を持ち、<doc:03-RouteStore> の UIKit の例と同じく `store` を第 1 引数に受け取ることができます。

ここで、第 2 引数は `makeView: (Store<Action, State, Environment>.Proxy) -> some View` という型を持っています。これは、

- （RouteStore 内部で）第 1 引数の ``Store`` を ``Store/Proxy-swift.struct`` に変えてクロージャーの引数に提供するので、開発者はそれを使って SwiftUI View を組み立てて下さい

という意味です。

``Store/Proxy-swift.struct`` については後述するとして、まずは ``HostingViewController`` の実際の使用例を見てみましょう。

```swift
import SwiftUI
import ActomatonStore

// SwiftUI View の例
@MainActor
struct ContentView: View {
    // Store.Proxy を保持 (NOTE: @ObservedObject 等は不要)
    private let store: Store<Action, State, Environment>.Proxy

    init(store: Store<Action, State, Environment>.Proxy) {
        self.store = store
    }

    var body: some View {
        HStack {
            Text("\(store.state.count)")

            Button(action: { store.send(.increment) }) {
                Image(systemName: "plus.circle")
            }

            Button(action: { store.send(.push) }) {
                Text("Navigation Push")
            }
        }
    }
}

enum SwiftUIBuilder {
    static func buildNavigation() -> UIViewController {
        // RouteStore (ViewModel) の作成（前ページと同じ）
        let store = RouteStore(
            state: State(),
            reducer: reducer,
            routeType: Route.self
        )

        // HostingViewController を使ったViewController の作成
        let vc = HostingViewController(store: store, makeView: ContentView.init)

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

`HostingViewController` 初期化時の `makeView` に `ContentView` (SwiftUI View) のイニシャライザを渡します。
すると、開発者は ``Store/Proxy-swift.struct`` を ViewModel と見立てて、SwiftUI View 内部の開発のみに専念することができます。

## Store.Proxy について

![store-proxy](store-proxy.png)

``Store/Proxy-swift.struct`` は ``Store`` (``RouteStore`` の親クラス) から生成される SwiftUI view binding 用の Sub-Store クラスです。
主な用途として、

1. SwiftUI `@Binding` に便利なヘルパーメソッドを提供する
2. 関数型プログラミングの手法を使って、 1 つの ``Store`` のみを Single Source of Truth として扱い、 Sub-Store  に分解して個々の画面を表現する（上図参照、ただし上級者向け）

があり、ここでは 1. に絞って使い方を解説します。

### @Binding (状態の直接更新) を store.send (間接更新) に変換する

Actomaton におけるビジネスロジックの基本的な設計は `Reducer` が担います。
`Reducer` は状態遷移関数のことで、 **状態を直接更新する代わりにアクションを介して「間接的に」更新する** というのが特徴です。
この動作は、ステートマシン全般の基本的な振る舞いになりますが、残念ながら SwiftUI の世界では
`@Binding` が「状態の直接更新」を中心とする設計になっているため、 `Reducer` を介して状態を間接更新することを難しくしています。

ここで `Reducer` を介した状態の間接更新のメリットを挙げておきましょう。
これまでの例題で見てきた通り、`Reducer` を使った場合は状態をただ単に変更するだけでなく、
**トリガー（アクション）をフックポイントとして副作用を追加できる** という点にあります。
例えば、状態更新をコンソールログに表示したり、分析ログを外部送信したい場合などに便利です。

このように、 Actomaton の `Reducer` には大きな利点がありますが、 SwiftUI 上でその機能を享受するためには、

- SwiftUI の `@Binding` (状態の直接更新) を `store.send` (アクションを送って間接更新) に変換する

という仕組みが必要になります。

その具体的な方法として、``Store/Proxy-swift.struct`` の ``Store/Proxy-swift.struct/stateBinding(get:onChange:)`` を使います。

例えば、テキストフィールドの入力状態をバインディングする例を考えてみます：

```swift
import SwiftUI

@MainActor
struct SearchView: View {
    @Binding // または @State
    private var text: String

    ...

    var body: some View {
        TextField("Search", text: $text)
    }
}
```

Actomaton ではこれを次のように書くことができます：

```swift
import SwiftUI
import ActomatonStore

enum Action {
    case updateText(String) // 入力フック用アクション
}

struct State {
    var text: String
}

typealias Environment = Void

let reducer = Reducer { action, state, environment in
    switch action {
    case let .updateText(text):
        state.text = text

        // フックして副作用を追加
        return Effect.fireAndForget { print("Updated to \(text)") }
    }
}

// NOTE: HostingViewController を使うと Store.Proxy 化する
let store: RouteStore<Action, State, Environment, Route> = .init(
    state: State(),
    reducer: reducer
)

@MainActor
struct SearchView: View {
    private let store: Store<Action, State, Environment>.Proxy

    init(store: Store<Action, State, Environment>.Proxy) {
        self.store = store
    }

    var body: some View {
        // NOTE: store.stateBinding は、状態 @Binding のセッターを onChange に変換して store.send する
        TextField("Search", text: store.stateBinding(
            get: { $0.text },
            onChange: { Action.updateText($0) }
        )
    }
}
```

おおっと、コードの量が一気に増えてしまいました！
SwiftUI View の中で `store.stateBinding` が使われているだけでなく、 
`Action.updateText` を書いたり、 `Reducer` を定義したり、一見するとコードが複雑になってしまっているように見えますね。

しかし、 **開発者が適切な設計のもと、状態と副作用をきちんと管理するためには、アクションによる状態の間接操作が不可欠です。**
これらの冗長化を許容しないまま、追加の副作用を記述することは容易なことではありません。

とはいえ、もし完璧な状態管理・副作用管理を求めていない場合は、上記のような余計なコードを省きたいケースもあるでしょう。
その場合は、 ``Store/Proxy-swift.struct/directStateBinding`` を使って、冗長化を避けることが可能です。

```swift
@MainActor
struct SearchView: View {
    private let store: Store<Action, State, Environment>.Proxy

    init(store: Store<Action, State, Environment>.Proxy) {
        self.store = store
    }

    var body: some View {
        // NOTE: store.directStateBinding (生の state) を使って直接更新
        TextField("Search", text: store.directStateBinding.text
    }
}
```

``Store/Proxy-swift.struct/stateBinding(get:onChange:)`` と ``Store/Proxy-swift.struct/directStateBinding`` を適材適所で使い分けながら、理想の状態・副作用管理を目指しましょう！

## Next Step

``RouteStore`` を使ったアプリ開発のチュートリアルは以上です 🎉

