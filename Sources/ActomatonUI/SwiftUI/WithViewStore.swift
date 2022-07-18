import SwiftUI

/// Observable ``ViewStore`` holder view that is created from unobservable ``Store``.
///
/// Example code:
///
/// ```swift
/// struct ContentView: View {
///     let store: Store<Action, State, Environment>
///     ...
///     var body: some View {
///         WithViewStore(store) { viewStore in
///             Text("Hello, \(viewStore.state.username)") // NOTE: Can shorten to `viewStore.username`.
///         }
///     }
/// }
/// ```
public struct WithViewStore<Action, State, Content>: View
    where Action: Sendable, State: Sendable, Content: View
{
    @ObservedObject
    private var viewStore: ViewStore<Action, State>

    private let content: @MainActor (ViewStore<Action, State>) -> Content

    /// Initializer with `@ViewBuilder` and `areStatesEqual`.
    public init<Environment>(
        _ store: Store<Action, State, Environment>,
        areStatesEqual: @escaping (State, State) -> Bool,
        @ViewBuilder content: @escaping @MainActor (ViewStore<Action, State>) -> Content
    ) where Environment: Sendable
    {
        self.viewStore = store.viewStore(areStatesEqual: areStatesEqual)
        self.content = content
    }

    /// Initializer with `@ViewBuilder`.
    public init<Environment>(
        _ store: Store<Action, State, Environment>,
        @ViewBuilder content: @escaping @MainActor (ViewStore<Action, State>) -> Content
    ) where State: Equatable, Environment: Sendable
    {
        self.init(store, areStatesEqual: ==, content: content)
    }

    /// Initializer without `@ViewBuilder`, with `areStatesEqual`.
    public init<Environment>(
        _ store: Store<Action, State, Environment>,
        areStatesEqual: @escaping (State, State) -> Bool,
        _ content: @escaping @MainActor (ViewStore<Action, State>) -> Content
    ) where State: Equatable, Environment: Sendable
    {
        self.init(store, areStatesEqual: areStatesEqual, content: content)
    }

    /// Initializer without `@ViewBuilder`.
    public init<Environment>(
        _ store: Store<Action, State, Environment>,
        _ content: @escaping @MainActor (ViewStore<Action, State>) -> Content
    ) where State: Equatable, Environment: Sendable
    {
        self.init(store, areStatesEqual: ==, content: content)
    }

    public var body: Content
    {
        self.content(self.viewStore)
    }
}
