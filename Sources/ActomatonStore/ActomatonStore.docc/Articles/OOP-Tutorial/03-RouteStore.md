# 3. RouteStore によるルーティング

``RouteStore`` を使って他の ``RouteStore`` にメッセージングする例

## Overview

`Actomaton` は Elm Architecture をベースに設計されており、理想的な使い方として 1 つの `Actomaton` (状態機械) のみでアプリの全画面を設計する（複数の `Reducer` を合成する関数型プログラミング方式）のに最も適しています。

しかし、実際の iOS アプリ開発の現場では、

- 関数型プログラミングの難易度が高い (`Reducer` の合成が理解しにくい)
- 宣言的な SwiftUI が使えず、引き続き UIKit と UI binding を使って開発する必要があり、1つの状態機械では扱いにくい

といった理由で、そのままの形で導入するにはハードルが高いことがしばしば挙げられます。

この ``RouteStore`` チュートリアルでは、 `Actomaton` (状態機械) を **個々の画面単位で独立に定義して、
互いにメッセージングし合いながら従来の MVVM 開発（オブジェクト指向プログラミング方式）をサポートする仕組み** について解説します。

この記事では、主に次の型について見ていきます

1. ``RouteStore`` (外部ルーティング処理)
2. ``SendRouteEnvironment`` による ``SendRouteEnvironment/sendRoute`` 可能な `Environment` ラッパー
3. ``HostingViewController`` と組み合わせた SwiftUI View 開発

## 例題

ここでは、前回の <doc:01-Counter> における `increment` ボタンのほか、`push` ボタンをタップして `UINavigationController` による画面遷移を行いつつ、カウンターの値を次の画面に渡して表示する例を見ていきます。

## RouteStore と SendRouteEnvironment

まず、ビジネスロジックとなる `Action` 、 `State` 、 `Reducer` を定義します。

```swift
import ActomatonStore

// 入力アクション
enum Action: Sendable {
    case increment
    case push // 画面遷移
}

// 状態
struct State: Equatable, Sendable {
    var count: Int = 0
}

// 外部環境からの副作用の依存注入は今回必要ないので、Void 。
typealias _Environment = Void

// 状態遷移関数
let reducer: Reducer<Action, State, _Environment>
reducer = Reducer { action, state, environment in
    switch action {
    case .increment:
        state.count += 1
        return Effect.empty
    case .push:
        // TODO: どのように画面遷移の副作用を入れる？
        return Effect.empty
    }
}
```

ここまでは <doc:01-Counter> の例とほぼ同じですが、 `Action.push` を受け取った後の `case .push` 分岐をどのように実装するのが良いのかが悩みの種です。

``RouteStore`` を使った設計では、従来の `Environment` 定義に ``SendRouteEnvironment/sendRoute`` 関数を加えるためのラッパーとして ``SendRouteEnvironment`` を使います。
これを使うと、次の形で `environment.sendRoute()` を呼び出すことができるようになります。


```swift
// 外部環境からの副作用の依存注入は今回必要ないので、Void 。
// NOTE: この型は `SendRouteEnvironment` でラップされるので、
//       名前の区別のため "_" を接頭辞につけておく。
typealias _Environment = Void

// SendRouteEnvironment によるラップ。
// これを使うと `environment.sendRoute()` が実行できる。
typealias Environment = SendRouteEnvironment<_Environment, Route>

// 外部ルーティング出力用データ
enum Route: Sendable {
    case push(count: Int)
}

// 状態遷移関数
let reducer: Reducer<Action, State, Environment>
reducer = Reducer { action, state, environment in
    switch action {
    case .increment:
        state.count += 1
        return Effect.empty
    case .push:
        // `sendRoute` を使った副作用
        return environment.sendRoute(Route.push(count: state.count))
    }
}
```

これでルーティング（外部出力）を含んだビジネスロジックが完成しました！

次に UIKit View にルーティングをつなぎこむ処理を見ていきます。

## UI route ハンドリング

Actomaton に限らず、 ViewModel がルーティング処理を兼ねる場合、その実装を `UIViewController` が内部で受け取って処理するよりも、外部から注入した方が ViewController 間が疎結合になり、より良い設計になります。

ここでは ``RouteStore`` を生成して `UIViewController` を注入しつつ、ルーティング処理を外部から差し込める builder 関数を定義します。

```swift
import UIKit
import ActomatonStore

@MainActor
public enum Builder {
    // ViewController の builder 関数（ここでは UINavigationController までまとめて生成）
    static func buildNavigation() -> UIViewController {
        // RouteStore (ViewModel) の作成
        let store = RouteStore(
            state: State(),
            reducer: reducer,
            routeType: Route.self
        )

        // ViewController の作成
        let vc = ViewController(store: store)

        let navC = UINavigationController(rootViewController: vc)

        // ルーティング処理
        store.subscribeRoutes { [weak navC] route in
            switch route {
            case let .push(count):
                // 次の画面の ViewController を生成し、navigation push する。
                // （次の画面用の NextBuilder の実装は省略）
                let vc = NextBuilder.build(count: count)
                navC?.pushViewController(vc, animated: true)
            }
        }

        return navC
    }
}
```

ここで重要なメソッドが ``RouteStore/subscribeRoutes(_:)`` です。
この関数のクロージャー引数が、前述のビジネスロジックにおける出力値 `Route.push` を受け取り、
その値を様々な形で解釈して次の画面へと遷移させます。

まさに、このクロージャーが画面間の遷移を担うルーターとして存在することに相当します。

## Next Step

<doc:04-HostingViewController>
