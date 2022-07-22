import SwiftUI

extension ForEach
{
    /// `ForEach` for `Store` where its state is a collection of child states identified by `id` keyPath.
    /// - SeeAlso: Why `zip` is used: https://stackoverflow.com/a/63145650/666371
    @MainActor
    public init<C, Action, Environment, InnerContent>(
        store: Store<Action, C, Environment>,
        id: KeyPath<C.Element, ID>,
        @ViewBuilder content: @escaping (Store<Action, C.Element, Environment>) -> InnerContent
    ) where
        Data == [Zip2Sequence<C.Indices, C>.Element],
        InnerContent: View,
        Content == InnerContent?,
        C: MutableCollection & RandomAccessCollection & Sendable,
        C.Index: Hashable & Sendable,
        C.Element: Sendable,
        Action: Sendable,
        Environment: Sendable
    {
        let firstKeyPath = \Zip2Sequence<C.Indices, C>.Element.1

        let state = store.state

        self.init(
            Array(zip(state.indices, state)),
            id: firstKeyPath.appending(path: id)
        ) { index, child in
            // IMPORTANT:
            // Safe array access is needed to avoid `ContiguousArrayBuffer` index out of range error.
            // https://stackoverflow.com/questions/59295206/how-do-you-use-enumerated-with-foreach-in-swiftui/63145650
            let substore = store.map(state: \.[safe: index]).optionalize()

            if let substore = substore {
                content(substore)
            }
        }
    }

    /// `ForEach` for `Store` where its state is a collection of child states identified by `Identifiable` protocol.
    /// - SeeAlso: Why `zip` is used: https://stackoverflow.com/a/63145650/666371
    @MainActor
    public init<C, Action, Environment, InnerContent>(
        store: Store<Action, C, Environment>,
        @ViewBuilder content: @escaping (Store<Action, C.Element, Environment>) -> InnerContent
    ) where
        Data == [Zip2Sequence<C.Indices, C>.Element],
        InnerContent: View,
        Content == InnerContent?,
        C: MutableCollection & RandomAccessCollection & Sendable,
        C.Index: Hashable & Sendable,
        C.Element: Identifiable & Sendable,
        C.Element.ID == ID,
        Action: Sendable,
        Environment: Sendable
    {
        self.init(store: store, id: \.id, content: content)
    }
}
