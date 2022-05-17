# 2. 認証フローの状態管理・副作用管理

認証フローで行われる複雑な状態管理とその副作用管理を扱う例

## Overview

![login-diagram](login-logout.png)

このチュートリアルでは、上図の状態遷移を Actomaton 上で設計します。

- 状態：ログイン中、ログイン後、ログアウト中、ログアウト後
- アクション： ログイン、 ログアウト、 強制ログアウト
    - 内部アクション：ログイン完了、ログアウト完了
    - ログインとログアウト時に API 通信を行う（副作用）

特に、次の `Actomaton` の副作用管理の機能について見ていきます。

1. `Effect` (副作用) の実装
2. `EffectID` による副作用の手動キャンセル
3. `EffectQueue` による副作用の自動キャンセル・自動サスペンド

> Tip:
今回の実装ではコアモジュールの `Actomaton` を状態機械として使用しますが、
UI 開発向けの `Store` や `RouteStore` に置き換えることも可能です。

## Action, State, Reducer, Effect

まず、基本的な `Action` 、 `State` 、 `Reducer` を定義しましょう。


```swift
enum Action: Sendable {
    case login, loginOK, logout, logoutOK
    case forceLogout
}

enum State: Equatable, Sendable {
    case loggedOut, loggingIn, loggedIn, loggingOut
}

let reducer = Reducer { action, state, environment in
    switch (action, state) {
    case (.login, .loggedOut):
        state = .loggingIn
        return login(state.userId) // ログイン処理（副作用）

    case (.loginOK, .loggingIn):
        state = .loggedIn
        return .empty

    case (.logout, .loggedIn),
        (.forceLogout, .loggingIn),
        (.forceLogout, .loggedIn):
        state = .loggingOut
        return logout() // ログアウト処理（副作用）

    case (.logoutOK, .loggingOut):
        state = .loggedOut
        return .empty

    default:
        return Effect.fireAndForget {
            print("State transition failed...")
        }
    }
}
```

ここでは、`login`、`logout` 時に副作用を伴う関数を `return` しているほか、画面遷移の失敗時に `default` 句で `Effect` （副作用）が `print` 出力を行うように定義されています。

> Important:
これらの副作用は `return` されているだけで、まだ実行されていません！ なので、この `Reducer` は **純粋関数** です。実際には `Reducer` を純粋関数として実行した後、得られた `Effect` について Actomaton の内部で遅延評価されます（このとき初めて「現実世界における副作用」が発生します）。副作用を常に `Effect` の中に宣言することが、副作用を適切に管理・設計する上で "とてもとても" 大切です。

`Effect` の実装方法は5種類があります。特に重要なのが 3. 4. 5. です（3. は 1. と 2. を兼ねます）。

1. 副作用を発生せず、次のアクションのみを転送する
    - `Effect.nextAction()`
2. `async` 関数で副作用を発生し、次のアクションは送らない
    - `Effect.fireAndForget(id:queue:run:)`
3. `async` 関数で副作用を発生し、次のアクションを送る
    - `Effect.init(id:queue:run:)`
4. `AsyncSequence` で副作用を発生させつつ次のアクションを送る処理を「複数回」行う
    - `Effect.init(id:queue:sequence:)`
5. `EffectID` を使った手動キャンセル
    - `Effect.cancel(id:)`
    - `Effect.cancel(ids:)`

`EffectID` によるキャンセルの方法と `EffectQueue` を使ったより高度な副作用管理については、次節で詳しく解説します。

## Environment (副作用コンテナとしての外部環境)

次に、 `login` と `logout` 関数を実装します。

```swift
struct Environment: Sendable {
    let login: @Sendable (userId: String) -> Effect<Action>
    let logout: Effect<Action>
}

let environment = Environment(
    login: { userId in
        Effect {
            let loginRequest = ...
            let data = try? await URLSession.shared.data(for: loginRequest) // API 通信
            ...
            return Action.loginOK // 次のアクション
        }
    },
    logout: Effect {
        let logoutRequest = ...
        let data = try? await URLSession.shared.data(for: logoutRequest) // API 通信
        ...
        return Action.logoutOK // 次のアクション
    }
)
```

ここで `struct Environment` がはじめて使われていますが、これは依存注入コンテナ (Dependency Injection Container) と考えるのが分かりやすいです。
例えば、モックに差し替えたい場合は、

```swift
let mockEnvironment = Environment(
    login: { userId in
        Effect.nextAction(.loginOK) // API 通信をせず、次のアクションだけ送る
    },
    logout: Effect.nextAction(.logoutOK)
)
```

のように、`Effect` 内部で API 通信などの副作用を実行せず次のアクションのみを送る処理に変更できます。
この方法を使うことで、 **副作用を発生しないユニットテスト** が手軽に実行できます。

## EffectID と EffectQueue による副作用管理

前述の `environment` 実装で API 通信として定義した `login` と `logout` ですが、例えば今回の例における `forceLogout` のように、 **ログイン途中でも強制的にキャンセルしてログアウト処理に移行したい** 場合などが考えられます。

このようなシナリオでは、次の2つのキャンセル処理のアプローチを検討することができます。

1. `EffectID` による手動キャンセル
2. `EffectQueue` による自動キャンセル

### 1. EffectID による手動キャンセル

`Effect` の初期化時に識別子として `EffectID` を付与し、 `Effect.cancel(id:)` を手動で呼ぶ方法です。
具体的には `protocol EffectIDProtocol` を使い、 `Hashable` な識別子を `Effect` の初期化時に渡します。

```swift
struct LoginEffectID: EffectIDProtocol {} // 空実装でOK

let environment = Environment(
    login: { userId in
        Effect(id: LoginFlowEffectID()) { // EffectID 追加
            ... // 実際のログイン処理
        }
    },
    logout: Effect.cancel(id: LoginFlowEffectID()) // 事前にキャンセル処理
        + Effect { // Effect の足し算
            ... // 実際のログアウト処理
        }
)
```

このように、「実際のログアウト処理」の前に「キャンセル」を呼ぶことができます。
面白いことに **`Effect` は足し算を使って合成** することができるのです！
（もちろん、キャンセル処理を単体として実装することも可能です）

### 2. EffectQueue による自動キャンセル

`EffectID` による手動キャンセルは、毎回直前に `Effect.cancel(id:)` を書く必要性があるため、時として面倒に感じることもあります。
その場合は Actomaton の `EffectQueue` を使った、より高度な副作用管理システムを試してみて下さい。

`EffectID` と同様、`EffectQueue` もまた Hashable ベースの識別子として、 `protocol EffectQueueProtocol` を採用することで作成できます。
今回の例では、その中でも最も利用頻度の高い `Newest1EffectQueueProtocol` サブプロトコルを使います。
これは **最新1件の副作用のみを実行し、直前までに同じキューで登録されていた副作用をすべてキャンセルする** というキューです。

```swift
struct LoginFlowEffectQueue: Newest1EffectQueueProtocol {} // 空実装でOK

let environment = Environment(
    login: { userId in
        Effect(queue: LoginFlowEffectQueue()) { // EffectQueue に追加
            ... // 実際のログイン処理
        }
    },
    logout: Effect(queue: LoginFlowEffectQueue()) { // EffectQueue に追加
        ... // 実際のログアウト処理
    }
)
```

このように `login` と `logout` が同じキューに登録されることを明記することで、
互いの最新のタスクのみを実行し、古いタスクについては自動的にキャンセルされます。

> Note:
> リアクティブプログラミング (Rx) における `Rx.flatMapLatest` と同じ処理を実現しています。

> Important:
> `EffectQueue` の種類には：
> 
> - `Newest1EffectQueueProtocol` (Rx.flatMapLatest)
> - `Oldest1DiscardNewEffectQueueProtocol` (Rx.flatMapFirst)
> - `Oldest1SuspendNewEffectQueueProtocol` (Rx.concat)
> 
> などがビルトインで定義されており、カスタムで最大同時実行数の設定もできます。

## Actomaton の実装とテスト

それでは最後に、上記の設計図から `Actomaton` を生成してテストを書いてみましょう。

```swift
let actomaton = Actomaton<Action, State>(
    state: .loggedOut,
    reducer: reducer,
    environment: environment // 依存注入コンテナを追加
)

@main
enum Main {
    static func test_login_logout() async {
        var t: Task<(), Error>?

        // ログアウト状態
        assertEqual(await actomaton.state, .loggedOut)

        // ログイン
        t = await actomaton.send(.login)
        assertEqual(await actomaton.state, .loggingIn)

        await t?.value // 完了まで待機

        // ログイン完了状態
        assertEqual(await actomaton.state, .loggedIn)

        // ログアウト
        t = await actomaton.send(.logout)

        // ログアウト中状態
        assertEqual(await actomaton.state, .loggingOut)

        await t?.value // 完了まで待機

        // ログアウト完了状態
        assertEqual(await actomaton.state, .loggedOut)
    }

    static func test_login_forceLogout() async throws {
        var t: Task<(), Error>?

        // ログアウト状態
        assertEqual(await actomaton.state, .loggedOut)

        // ログイン
        await actomaton.send(.login)
        assertEqual(await actomaton.state, .loggingIn)

        // 少し待機してから強制ログアウト
        try await Task.sleep(/* 1 ms */)
        t = await actomaton.send(.forceLogout)

        // ログアウト中状態
        assertEqual(await actomaton.state, .loggingOut)

        await t?.value // 完了まで待機

        // ログアウト完了状態
        assertEqual(await actomaton.state, .loggedOut)
    }
}
```

## サンプルコード

[Actomaton-Gallery/StateDiagram.swift](https://github.com/Actomaton/Actomaton-Gallery/blob/main/Sources/StateDiagram/StateDiagram.swift)

## Next Step

<doc:03-RouteStore>
