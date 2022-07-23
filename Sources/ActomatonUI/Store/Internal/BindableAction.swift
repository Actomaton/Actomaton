import CustomDump

/// `action` as indirect messaging, or `state` that can directly replace `actomaton.state` via SwiftUI 2-way binding.
internal enum BindableAction<Action, State>: Sendable, CustomDumpRepresentable
    where Action: Sendable, State: Sendable
{
    case action(Action)
    case state(State)

    func map<SubAction>(action f: (Action) -> SubAction) -> BindableAction<SubAction, State>
    {
        switch self {
        case let .action(action):
            return .action(f(action))
        case let .state(state):
            return .state(state)
        }
    }

    var customDumpValue: Any
    {
        switch self {
        case let .action(action):
            return action
        case .state:
            return "BindableAction.state"
        }
    }
}
