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
import ActomatonStore

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

`RouteStore` を `@StateObject` として View 内部で宣言します。

`RouteStore` の状態を参照するには `store.state`、次のアクションを送る場合は `store.send()` を呼び出します。

```swift
import SwiftUI
import ActomatonStore

@MainActor
struct CounterView: View {
    // Store を作成
    @StateObject
    private var store: RouteStore<Action, State, Environment, Route> = .init(
        state: State(),
        reducer: reducer
    )

    var body: some View {
        HStack {
            // ボタン： decrement を送信
            Button(action: { store.send(.decrement) }) {
                Image(systemName: "minus.circle")
            }

            // 現在のカウントを画面に表示
            Text("Count: \(store.state.count)")

            // ボタン： increment を送信
            Button(action: { store.send(.increment) }) {
                Image(systemName: "plus.circle")
            }
        }
    }
}
```

> Important:
> ``RouteStore`` は外部出力可能なルーティング機能を持った ``Store`` のサブクラスです。
> ``Store`` は `actor Actomaton` を UI (メイン) スレッド用にラップしたクラスです。
>
> ``RouteStore`` の具体的な使い方については、<doc:03-RouteStore> で解説しています。

#### 2. UIKit View の場合

UIKit では SwiftUI と異なり、UI binding を自ら実装しなくてはならない手間がかかりますが、
`Store` の状態更新を受け取る `Publisher` (`store.$state`) を使って簡単に実装することができます。

```swift
import UIKit
import ActomatonStore
import Combine

final class ViewController: UIViewController {
    // Store を作成
    private let store: RouteStore<Action, State, Environment, Route> = .init(
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

        // 以下は、RouteStore との UIKit view binding

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

これで完成です！
`RouteStore` を従来の MVVM ViewModel に見立てると、ほとんど書き方が似ていることが分かります。

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
> そのビジネスロジックの基本設計図をそのまま UIKit にも適用できるのが、この `RouteStore` を使った例です。

## サンプルコード

- [Actomaton-Basic](https://github.com/Actomaton/Actomaton-Gallery/tree/main/Examples/Actomaton-Basic.swiftpm)

## Next Step

<doc:02-LoginLogout>
