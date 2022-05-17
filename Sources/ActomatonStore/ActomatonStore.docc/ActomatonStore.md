# ``ActomatonStore``

Swift Concurrency (async/await、Structured Concurrency、Actor) を使った、状態と副作用の管理のためのフレームワーク。

## Overview

**Actomaton** は Swift Concurrency を使った **状態と副作用の管理のためのフレームワーク** です。
[Elm](http://elm-lang.org/) や [Redux](https://redux.js.org/)、[swift-composable-architecture](https://github.com/pointfreeco/swift-composable-architecture) などを参考に、Swift Concurrency を用いた高度な副作用管理システムを備えています。

- Repository: [https://github.com/Actomaton/Actomaton](https://github.com/Actomaton/Actomaton)

### Actomaton (親モジュール)

**Actomaton** は Actor を用いた状態管理のコアモジュールで、Linux を含めた各種プラットフォーム上で動作します。
大きく分けて、次の5つの型ないしその実装を開発者が定義することで、アプリの振る舞い（ビジネスロジック）を決定します。

1. **Action (入力)**: 
`enum` を用いた「メッセージ」を Actomaton に送り、Reducer（ビジネスロジック）を実行する
2. **State (状態)**: 
アプリの全体、あるいは部分的なドメインに特化した「状態」。
`Action` を受信後に Reducer によって状態変更が行われる。この状態を使って、ユーザーインターフェースなどシステム外部に対して表現を行う。
3. **Reducer (状態遷移関数)**: 
アプリの全体、あるいは部分的なドメインに特化した「ビジネスロジック」。
`Action` を入力として受け取り、`State` を更新した後、 `Effect` を出力として発生する。
4. **Effect (副作用)**: `Action` 受信後の Reducer の実行で発生する「副作用」
    - 副作用実行の後、次のアクションを1回送信する `async` 関数方式と、複数回のアクションを連続送信できる `AsyncStream` 方式の2パターン
    - `EffectID` を使った（手動）キャンセル処理
    - `EffectQueue` を使った副作用のキュー管理（自動キャンセル・自動待機など）
3. **Environment (外部環境)**: 実行する副作用の差し替え（モック化）を可能にする「外部環境」。これにより Actomaton は依存注入コンテナとしても機能する。

これらの単純なデータ構造をアプリの設計図として、**actor Actomaton** を作成することができます。

`Actomaton` は状態機械を使った計算モデルの１つです。その使い方として、

- 1つの `Actomaton` のみを用いてアプリ全体の状態を管理（**関数型プログラミング方式**）
- 各ドメインごとに `Actomaton` を作成して複数間でメッセージパッシングする設計（**オブジェクト指向プログラミング方式**）

など、様々な設計指針に合わせて柔軟に開発することができます。

> Tip:
> - **オブジェクト指向プログラミング方式** では、 `Actomaton` を UI 開発における「ViewModel」に見立てて設計することができます。初級〜中級者向け。
> - **関数型プログラミング方式** では、`WritableKeyPath` と [`CasePath`](https://github.com/pointfreeco/swift-case-paths) を用いた
> Optics (Lens) と呼ばれる手法を使って `Actomaton` の代わりに `Reducer` をドメインごとに分解し、アプリ全体へと合成することができます。上級者向け。

### ActomatonStore

この **ActomatonStore** モジュールでは、上述の Actomaton を SwiftUI / UIKit / AppKit 向けにラップした 
`Store` と UI binding に便利な各種機能を提供します。

1. Store (共通)
    - **``Store``**: `Actomaton` をメインスレッド化した薄いラッパー
2. SwiftUI binding + 関数型プログラミング用
    - **``Store/Proxy-swift.struct``**: SwiftUI `@Binding` に特化した ``Store`` の部分構造 (Sub-Store)
3. UIKit binding + オブジェクト指向プログラミング用
    - **``RouteStore``**: ``Store`` のサブクラスで、追加の `Route` 外部出力（副作用）を持つ
    - MVVMにおける ViewModel と同等の機能を提供する一方、Sub-Store に分解できない

<!--
4. UIKit binding + 関数型プログラミング用 (Experimental)
    - **``Store/ObservableProxy-swift.class``** : UIKit / AppKit view binding (via Combine Publisher) に特化した ``Store`` の部分構造 (Sub-Store)
-->

この中で簡単に始められるのは、従来の MVVM 構成に最も近い 3. の ``RouteStore`` です。
``RouteStore`` を用いたチュートリアル (for UIKit & SwiftUI) については、下記のリンクをご参照下さい。

- <doc:OOP-Tutorial>

2, 3, 4 を使った実際のサンプルアプリについては、次の SwiftUI / UIKit Gallery アプリをご参照下さい。

- [Actomaton-Gallery](https://github.com/Actomaton/Actomaton-Gallery)


## Topics

### Getting Started

- <doc:OOP-Tutorial>

### Esssentials

- ``Store``

### For SwiftUI binding + Functional Programmers

- ``Store/Proxy-swift.struct``

### For UIKit binding + Object-Oriented Programmers

- ``RouteStore``
- ``SendRouteEnvironment``

### For UIKit binding + Functional Programmers

- ``Store/ObservableProxy-swift.class``

### UIKit View Hosting Helper

- ``HostingViewController``
