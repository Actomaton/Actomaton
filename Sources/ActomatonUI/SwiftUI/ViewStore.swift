import Combine
import SwiftUI

/// ``Store``'s `ObservableObject` proxy type that can create direct (state-to-state) & indirect (state-to-action) `Binding`s.
///
/// 1. Indirectly mutate `state` by ``binding(get:onChange:)`` and providing action "onChange"
/// 2. Directly mutate `state` by ``directBinding``
///     - Updated state that passes through this `Binding` will NOT pass user-defined `Reducer`.
///
/// Since ``Store`` is not capable of observing its state in SwiftUI, ``ViewStore`` is needed to be attached to SwiftUI view instead, either by:
///
/// 1. Create via ``Store/viewStore`` and attach to `SwiftUI.View` by writing
///   `@ObservedObject var viewStore: ViewStore<Action, State>`
/// 2. Use ``WithViewStore``
///
/// For example:
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
///
/// - Note: Ideally, minimal size of `ViewStore` should be owned by `SwiftUI.View` for optimized SwiftUI rendering.
///   To optimize as so, use ``Store/map(state:)`` to narrow-down its scope before converting to `ViewStore`
///   via ``WithViewStore`` or ``Store/viewStore``.
@dynamicMemberLookup
@MainActor
public final class ViewStore<Action, State>: ObservableObject
    where Action: Sendable, State: Sendable
{
    /// State to be rendered for `SwiftUI.View`.
    @Published
    public private(set) var state: State

    private let _send: @MainActor (
        BindableAction<Action, State>, TaskPriority?, _ tracksFeedbacks: Bool
    ) -> Task<(), Error>?

    private var cancellables: Set<AnyCancellable> = []

    /// Designated initializer with receiving `send` from single-source-of-truth `Store`.
    internal init(
        state: CurrentValuePublisher<State>,
        send: @escaping @MainActor (
            BindableAction<Action, State>, TaskPriority?, _ tracksFeedbacks: Bool
        ) -> Task<(), Error>?,
        areStatesEqual: @escaping (State, State) -> Bool
    )
    {
        self.state = state.wrappedValue
        self._send = send

        // Sync from `StoreCore` state (upstream) to `ViewStore` state (downstream).
        state
            .sink(receiveValue: { [weak self] state in
                guard let oldState = self?.state else { return }

                if !areStatesEqual(state, oldState) {
                    self?.state = state
                }
            })
            .store(in: &self.cancellables)
    }

    /// Gets sub-state through `@dynamicMemberLookup`.
    public subscript<SubState>(
        dynamicMember keyPath: KeyPath<State, SubState>
    ) -> SubState
    {
        self.state[keyPath: keyPath]
    }

    /// Sends either `action` or `state`.
    @discardableResult
    internal func _send(
        _ action: BindableAction<Action, State>,
        priority: TaskPriority? = nil,
        tracksFeedbacks: Bool = false
    ) -> Task<(), Error>?
    {
        self._send(action, priority, tracksFeedbacks)
    }
}

// MARK: - Indirect (state-to-action) binding

extension ViewStore
{
    /// Indirect state-to-action conversion binding to create `Binding<State>`.
    public func binding(
        onChange: @escaping (State) -> Action?
    ) -> Binding<State>
    {
        self.binding(get: { $0 }, onChange: onChange)
    }

    /// Indirect state-to-action conversion binding to create `Binding<SubState>`.
    public func binding<SubState>(
        get: @escaping (State) -> SubState,
        onChange: @escaping (SubState) -> Action?
    ) -> Binding<SubState>
    {
        Binding<SubState>(
            get: {
                get(self.state)
            },
            set: { value, transaction in
                if let action = onChange(value) {
                    // NOTE:
                    // `withTransaction` will work correctly only when
                    // `configuration.updatesStateImmediately` is `true`
                    // which will update state immediately on `@MainActor`.
                    _ = withTransaction(transaction) {
                        self._send(.action(action))
                    }
                }
            }
        )
    }

    /// Creates indirect `Binding<Bool>` as SwiftUI presentation binding from optional `State`, and sends `Action` on dismissal.
    public func isPresented<Wrapped>(onDismiss: @autoclosure @escaping () -> Action) -> Binding<Bool>
        where State == Wrapped?
    {
        self.binding(
            get: { $0 != nil },
            onChange: { isPresented in
                isPresented ? nil : onDismiss()
            }
        )
    }

    /// Creates indirect `Binding<Bool>` from `State` as `Bool`, and sends `Action` on dismissal.
    public func isPresented(onDismiss: @autoclosure @escaping () -> Action) -> Binding<Bool>
        where State == Bool
    {
        self.binding(
            onChange: { isPresented in
                isPresented ? nil : onDismiss()
            }
        )
    }
}

// MARK: - Direct (state-to-state) binding

extension ViewStore
{
    /// Direct 2-way state binding for SwiftUI without sending user-defined action.
    ///
    /// - Warning:
    ///   This binding will NOT run user-defined `Reducer`.
    ///   Like Elm Architecture, if user wants to always run `Reducer` per UI state change,
    ///   conversion from mutated state to `Action` is needed, e.g. ``binding(get:onChange:)``.
    public var directBinding: Binding<State>
    {
        Binding<State>(
            get: { self.state },
            set: { newState, transaction in
                _ = withTransaction(transaction) {
                    // Send framework-defined `BindableAction.state`.
                    self._send(.state(newState))
                }
            }
        )
    }
}
