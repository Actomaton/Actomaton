import SwiftUI

extension ForEach where Content: View
{
    /// `ForEach` for `Store` where its state is a collection of child states identified by `id` keyPath.
    /// - SeeAlso: Why `zip` is used: https://stackoverflow.com/a/63145650/666371
    @MainActor
    public init<C, Action>(
        store: Store<Action, C>.Proxy,
        id: KeyPath<C.Element, ID>,
        @ViewBuilder content: @escaping (Store<Action, C.Element>.Proxy) -> Content
    ) where
        Data == [Zip2Sequence<C.Indices, C>.Element],
        C: MutableCollection, C: RandomAccessCollection, C.Index: Hashable
    {
        let firstKeyPath = \Zip2Sequence<C.Indices, C>.Element.1

        self.init(
            Array(zip(store.state.indices, store.state)),
            id: firstKeyPath.appending(path: id)
        ) { index, child in
            content(store[index])
        }
    }

    /// `ForEach` for `Store` where its state is a collection of child states identified by `Identifiable` protocol.
    /// - SeeAlso: Why `zip` is used: https://stackoverflow.com/a/63145650/666371
    @MainActor
    public init<C, Action>(
        store: Store<Action, C>.Proxy,
        @ViewBuilder content: @escaping (Store<Action, C.Element>.Proxy) -> Content
    ) where
        Data == [Zip2Sequence<C.Indices, C>.Element],
        C: MutableCollection, C: RandomAccessCollection, C.Index: Hashable,
        C.Element: Identifiable, C.Element.ID == ID
    {
        self.init(store: store, id: \.id, content: content)
    }
}
