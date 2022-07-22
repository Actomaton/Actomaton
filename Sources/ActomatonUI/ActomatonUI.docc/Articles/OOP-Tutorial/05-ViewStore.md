# 5. ViewStore

``ViewStore`` を使った SwiftUI との連携

## Overview

``ViewStore`` は ``Store`` (``RouteStore`` の親クラス) から生成される SwiftUI view binding 用のクラスです。
これまでの章では、

1. ``WithViewStore`` を使って ``Store`` から ``ViewStore`` に変換
2. `SwiftUI.View.body` の中で `viewStore.state` を読み取って UI 表示に反映

という流れで簡単に説明しましたが、この章では **UI の状態が変化したときの Binding** について見ていきます。

## ViewStore による状態 Binding

``ViewStore`` から状態 `Binding` を作る方法は、主に次の 2 通りです：

1. 状態の「間接」更新 **（推奨）**
    - ``ViewStore/binding(get:onChange:)``
    - `get` で状態を read 、`onChange` で変更した状態を直接 ``Store`` に送る代わりに `Action` に変換して送信する
2. 状態の「直接」更新
    - ``ViewStore/directBinding``
    - `viewStore.state` の状態を直接 read/write する `Binding`

> Note:
> 状態の直接更新について、 ``ViewStore`` を `@ObservedObject` で監視する場合、
> `$viewStore.state` を使った `Binding` の取得が考えられますが、
> `viewStore.state` は read-only のため使用できません。代わりに ``ViewStore/directBinding`` を使います。

### @Binding (状態の直接更新) を store.send (間接更新) に変換する

Actomaton におけるビジネスロジックの基本的な設計は `Reducer` が担います。
`Reducer` は状態遷移関数のことで、 **状態を直接更新する代わりにアクションを介して「間接的に」更新する (Elm Architecture)** というのが特徴です。
この動作は、ステートマシン全般の基本的な振る舞いになりますが、残念ながら SwiftUI の世界では
`@Binding` が「状態の直接更新」を中心とする設計になっているため、 `Reducer` を介して状態を間接更新することを難しくしています。

ここで `Reducer` を介した状態の間接更新のメリットを挙げておきましょう。
これまでの例題で見てきた通り、`Reducer` を使った場合は状態をただ単に変更するだけでなく、
**トリガー（アクション）をフックポイントとして副作用を追加できる** という点にあります。
例えば、状態更新をコンソールログに表示したり、分析ログを外部送信したい場合などに便利です。

このように、 Actomaton の `Reducer` には大きな利点がありますが、 SwiftUI 上でその機能を享受するためには、

- SwiftUI の `@Binding` (状態の直接更新) を `store.send` (アクションを送って間接更新) に変換する

という仕組みが必要になります。

その具体的な方法として、``ViewStore`` の ``ViewStore/binding(get:onChange:)`` を使います。

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
import ActomatonUI

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

@MainActor
struct SearchView: View {
    private let store: Store<Action, State, Environment>

    init(store: Store<Action, State, Environment>) {
        self.store = store
    }

    var body: some View {
        WithViewStore(self.store) { viewStore in
            // NOTE: `viewStore.binding` は、状態 Binding のセッターを `onChange` アクションに変換して `store.send` する
            TextField("Search", text: viewStore.binding(
                get: { $0.text },
                onChange: { Action.updateText($0) }
            )
        }
    }
}

let store: RouteStore<Action, State, Environment, Route> = .init(
    state: State(),
    reducer: reducer
)

let searchView = SearchView(store: store)
...
```

おおっと、コードの量が一気に増えてしまいました！
SwiftUI View の中で `store.binding(get:onChange:)` が使われているだけでなく、 
`Action.updateText` を書いたり、 `Reducer` を定義したり、一見するとコードが複雑になってしまっているように見えますね。

しかし、 **開発者が適切な設計のもと、状態と副作用をきちんと管理するためには、アクションによる状態の間接操作が不可欠です。**
これらの冗長化を許容しないまま、追加の副作用を記述することは容易なことではありません。

> Important:
> Elm Architecture が状態管理のフレームワークとして優れている点は、 **「状態操作の一般化」
> （状態の get / set 直接更新から get / reducer 間接更新への一般化）** にあります。

とはいえ、もし完璧な状態管理・副作用管理を求めていない場合は、上記のような余計なコードを省きたいケースもあるでしょう。
その場合は、 ``ViewStore/directBinding`` (直接更新 `Binding`) を使って、冗長化を避けることが可能です。

```swift
@MainActor
struct SearchView: View {
    private let store: Store<Action, State, Environment>

    init(store: Store<Action, State, Environment>) {
        self.store = store
    }

    var body: some View {
        WithViewStore(self.store) { viewStore in
            // NOTE: `viewStore.directBinding` (mutable な state) を使って直接更新
            TextField("Search", text: viewStore.directBinding.text)
        }
    }
}
```

ただしこの場合、 **`Action` が無くなってしまっているので、`store` の `Reducer` が呼ばれない点に注意してください。**
`Action` が無い場合、その呼び出しに紐づく「追加の副作用」を実行することもできません。

このように、 ``ViewStore/binding(get:onChange:)`` (間接更新 `Binding`) と ``ViewStore/directBinding`` (直接更新 `Binding`) には
一長一短があります。
基本的には「間接更新」(Elm Architecture) を中心としながら適材適所で使い分け、理想の状態・副作用管理を目指しましょう！

## Next Step

``RouteStore`` を使ったアプリ開発のチュートリアルは以上です 🎉
