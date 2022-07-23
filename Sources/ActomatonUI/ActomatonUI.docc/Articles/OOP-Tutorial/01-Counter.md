# 1. シンプルなカウンター 

`increment` と `decrement` を行うカウンターの例

## Overview

Actomaton を使ったアプリのビジネスロジックを作成するために最低限、必要な情報は：

1. Action (入力) の型定義
2. State (状態) の型定義
3. Reducer (状態遷移関数) の実装

の3つです。この例では、これらの定義の仕方について見ていきます。

（他にも、副作用に関連する `Effect`, `Environment`, `Route` がありますが、この記事では使用しません）

### カウンターのビジネスロジック

今回は、`increment` と `decrement` を行うシンプルなカウンターを題材に、上記3点を次のように定義します。

```swift
import ActomatonUI

// 入力アクション (Sendable が必要)
enum Action: Sendable {
    case increment
    case decrement
}

// 状態 (Sendable が必要)
// NOTE: Equatable にしておくと差分更新とテスト比較がしやすいので、基本的に付けること。
struct State: Equatable, Sendable {
    var count: Int = 0
}

// 外部環境からの副作用の依存注入は今回必要ないので、Void 。
// NOTE: Never ではないので注意。通常は struct で定義する。
typealias Environment = Void

// 他画面へのルーティング処理は今回必要ないので、Never 。
// NOTE: Void ではないので注意。通常は enum で定義する。
typealias Route = Never

// 状態遷移関数：アクションが送られる度に呼ばれる
let reducer: Reducer<Action, State, Environment>
reducer = Reducer { action, state, environment in
    switch action { // 受信したアクションをパターンマッチで分岐処理
    case .increment:
        state.count += 1    // 状態を更新
        return Effect.empty // 副作用を出力（ここでは空）
    case .decrement:
        state.count -= 1
        return Effect.empty
    }
}
```

カウンターのビジネスロジックは以上で完成です。

### カウンターの UI view binding

上記のビジネスロジックを UI に反映する方法として、

1. SwiftUI View 
2. UIKit View

それぞれについて見ていきます。

#### 1. SwiftUI View の場合

まずはじめに、 ``Store`` を View 内部で宣言します。

```swift
import SwiftUI
import ActomatonUI

@MainActor
struct CounterView: View {
    // Store を作成
    private let store: Store<Action, State, Environment, Route> = .init(
        state: State(),
        reducer: reducer
    )

    var body: some View {
        // 注意： store.state にアクセスしても、View は更新されません 
    }
}
```

ここで **`Store` はまだ SwiftUI View と連携していない** 点に注意してください。
つまり、 `store.state` を直接呼んでも `CounterView` は再レンダリングの対象になりません。

SwiftUI と連携するには、 ``WithViewStore`` (SwiftUI View) を使って、 **``Store`` から ``ViewStore`` を作る** 必要があります。
これにより、``WithViewStore`` 内部で監視可能な ``ViewStore`` を保持し、その内部 View を再レンダリングすることができます。

```swift
import SwiftUI
import ActomatonUI

@MainActor
struct CounterView: View {
    // Store を作成
    private let store: Store<Action, State, Environment> = .init(
        state: State(),
        reducer: reducer
    )

    var body: some View {
        // `WithViewStore` を使って Store から ViewStore に変換。
        // これにより、`WithViewStore` (View) が `self.store` の状態更新に対応して内部の再レンダリングが可能。
        WithViewStore(self.store) { viewStore in 
            HStack {
                // ボタン： decrement を送信
                Button(action: { store.send(.decrement) }) {
                    Image(systemName: "minus.circle")
                }

                // 現在のカウントを画面に表示
                Text("Count: \(viewStore.state.count)")

                // ボタン： increment を送信
                Button(action: { store.send(.increment) }) {
                    Image(systemName: "plus.circle")
                }
            }
        }
    }
}
```

`Store` の状態を参照するには `viewStore.state`、次のアクションを送る場合は `store.send()` を呼び出します。


> Important:
> `Store` の状態を参照するには `viewStore.state` 以外に `store.state` も可能ですが、
> 状態へのアクセスは基本的に `viewStore` の方を使うようにしましょう。
> その理由は、 ``ViewStore/binding(get:onChange:)`` などの「状態 `Binding`」が、このクラスでのみ呼び出し可能なためです。
> 状態以外のアクセス（e.g. アクションを送る、依存コンテナ `Environment` にアクセスする）については、
> `store.send()`、`store.environment` を使います。

#### 2. UIKit View の場合

UIKit 実装では、 ``Store`` の状態更新を受け取る `Publisher` (`store.$state`) を使って簡単に UI binding を適用することができます。

```swift
import UIKit
import ActomatonUI
import Combine

final class ViewController: UIViewController {
    // Store を作成
    private let store: Store<Action, State, Environment, Route> = .init(
        state: State(),
        reducer: reducer
    ) 

    private var cancellables: Set<AnyCancellable> = []

    override func viewDidLoad() {
        super.viewDidLoad()

        let counterLabel = UILabel()
        let incrementButton = UIButton()
        let decrementButton = UIButton()

        ...

        // 以下は、Store との UIKit view binding

        store.$state
            .map { "Count: \($0.count)" }
            .removeDuplicates() // NOTE: 前回分と比較して同じなら無視する
            .assign(to: \.text, on: counterLabel)
            .store(in: &cancellables)

        incrementButton.tapPublisher
            .sink { [store] in
                store.send(.increment) // アクションを送る
            }
            .store(in: &cancellables)

        decrementButton.tapPublisher
            .sink { [store] in
                store.send(.decrement) // アクションを送る
            }
            .store(in: &cancellables)
    }
}
```

ここで Combine Publisher の `removeDuplicates()` を使って、必要な変更のみを UI binding すると良いでしょう。

さあ、これで完成です！
`Store` を従来の MVVM ViewModel に見立てると、ほとんど書き方が似ていることが分かります。

> Note:
> Actomaton が従来の MVVM と異なる点として次のようなものがあります：
>
> - MVVM のメソッド"直接"呼び出しに対して、Actomaton では enum を使ってメソッド群を定義し、`store.send(action)` でメッセージとして送信している（"間接"呼び出し）
> - MVVM では個々の状態の `Publisher` を集めて（複雑な）`Publisher` 全体の状態が作られるのに対して、Actomaton では全体の状態がシンプルな `struct` で出来ている
>     - 複数画面の状態を合成する際に、シンプルな構成の方が有利。例えば、`store.$state` で状態全体を1本の `Publisher` で一括で受け取れる (MVVM では事前に `combineLatest` 等をたくさん書く必要がある)
>     - 状態がシンプルな `Sendable` でもあるので、複数の状態をまとめて次の `Task` (非同期計算)に渡すことが出来る
>     - その一方で、UI binding 毎に `.map` と `.removeDuplicates()` を追加で書く手間がかかる
>
> Actomaton のような「状態を一括で受け取れる」設計は、UI binding と差分更新が自動的に適用される SwiftUI で特に真価を発揮します。
> そのビジネスロジックの基本設計図をそのまま UIKit にも適用できるのが、この `Store` を使った例です。

## サンプルコード

- [Actomaton-Basic](https://github.com/Actomaton/Actomaton-Gallery/tree/main/Examples/Actomaton-Basic.swiftpm)

## Next Step

<doc:02-LoginLogout>
