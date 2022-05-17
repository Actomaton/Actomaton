# RouteStore チュートリアル

``RouteStore`` を使った MVVM 構成の iOS アプリ開発の解説 (for UIKit & SwiftUI)

## Overview

このチュートリアルでは、 ``RouteStore`` を用いた MVVM 構成（オブジェクト指向プログラミング方式）の iOS アプリ開発の解説をします。

``RouteStore`` は次の用途で使うことに適しています。

- UIKit `UIViewController` 用の ViewModel として使う
- SwiftUI `View` の `@ObservedObject` として使う
- 1 画面 1 ViewModel 構成で **複数の `RouteStore`** を使う
    - 関数型プログラミング方式による `Reducer` 合成を使わない

## Steps

- <doc:01-Counter>
- <doc:02-LoginLogout>
- <doc:03-RouteStore>
- <doc:04-HostingViewController>

## RouteStore を使ったアプリの例

- [Actomaton-Favorite-Sync](https://github.com/Actomaton/Actomaton-Gallery/tree/main/Examples/Favorite-Sync/Actomaton-Favorite-Sync)
