import Actomaton

#if DEBUG
import CustomDump
#endif

extension Reducer
{
    /// Debug-logging `Action` and `State` during `self`'s reducer's run.
    /// - Warning: Only for debugging purpose, so should not use in production.
    public func debug(
        name: String? = nil,
        action actionLogFormat: ActionDebugLogFormat? = .all(maxDepth: .max),
        state stateLogFormat: StateDebugLogFormat? = .diff
    ) -> Reducer
        where Action: Sendable, State: Sendable
    {
        Self.debug(name: name, action: actionLogFormat, state: stateLogFormat, self.run)
    }

    /// Convenient constructor for debug-logging `Action` and `State` during target reducer's run,
    /// by replacing `targetReducer = Reducer.init { ... }` with `Reducer.debug { ... }`.
    ///
    /// - Warning: Only for debugging purpose, so should not use in production.
    public static func debug(
        name: String? = nil,
        action actionLogFormat: ActionDebugLogFormat? = .all(maxDepth: .max),
        state stateLogFormat: StateDebugLogFormat? = .diff,
        _ nextRun: @escaping (Action, inout State, Environment) -> Effect<Action> = Reducer.empty.run
    ) -> Reducer
        where Action: Sendable, State: Sendable
    {
#if DEBUG
        .init { action, state, environment in
            let currentState = state // Needs copy to not carry `inout`.

            /// Effect for  Action & State `.simple` or `.all` printing.
            let preEffect = Effect<Action>.fireAndForget {
                let name = name.map { "\($0) " } ?? ""

                if let actionLogFormat = actionLogFormat {
                    switch actionLogFormat.format {
                    case .simple:
                        print("\(name)action = \(debugCaseOutput(action))")

                    case let .all(maxDepth):
                        print("\(name)action = ", terminator: "") // NOTE: No linebreak before `customDump`.
                        customDump(action, maxDepth: maxDepth)
                    }
                }

                if let stateLogFormat = stateLogFormat {
                    switch stateLogFormat.format {
                    case .simple:
                        print("\(name)state = ", terminator: "") // NOTE: No linebreak before `customDump`.

                        var output = ""
                        customDump(currentState, to: &output, maxDepth: 1)
                        output = output.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                        print(output)

                    case let .all(maxDepth):
                        print("\(name)state = ", terminator: "") // NOTE: No linebreak before `customDump`.
                        customDump(currentState, maxDepth: maxDepth)

                    case .diff:
                        break
                    }
                }
            }

            let effect = nextRun(action, &state, environment)

            let nextState = state // Needs copy to not carry `inout`.

            /// Effect for State's `.diff` printing.
            let postEffect = Effect<Action>.fireAndForget {
                if let stateLogFormat = stateLogFormat {
                    switch stateLogFormat.format {
                    case .simple, .all:
                        break

                    case .diff:
                        let name = name.map { "\($0) " } ?? ""

                        if let diffString = diff(currentState, nextState) {
                            print("\(name)state diff = ") // NOTE: Adds linebreak because `diffString` contains +- symbols.
                            print(diffString)
                        }
                    }
                }
            }

            return preEffect + effect + postEffect
        }
#else
        .init(nextRun)
#endif
    }
}

// MARK: - Private

// Code from swift-composable-architecture:
// https://github.com/pointfreeco/swift-composable-architecture/blob/0.33.0/Sources/ComposableArchitecture/Debugging/ReducerInstrumentation.swift
private func debugCaseOutput(_ value: Any) -> String {
    func debugCaseOutputHelp(_ value: Any) -> String {
        let mirror = Mirror(reflecting: value)
        switch mirror.displayStyle {
        case .enum:
            guard let child = mirror.children.first else {
                let childOutput = "\(value)"
                return childOutput == "\(type(of: value))" ? "" : ".\(childOutput)"
            }
            let childOutput = debugCaseOutputHelp(child.value)
            return ".\(child.label ?? "")\(childOutput.isEmpty ? "" : "(\(childOutput))")"
        case .tuple:
            return mirror.children.map { label, value in
                let childOutput = debugCaseOutputHelp(value)
                return "\(label.map { isUnlabeledArgument($0) ? "_:" : "\($0):" } ?? "")\(childOutput.isEmpty ? "" : " \(childOutput)")"
            }
            .joined(separator: ", ")
        default:
            return ""
        }
    }

    return "\(type(of: value))\(debugCaseOutputHelp(value))"
}

private func isUnlabeledArgument(_ label: String) -> Bool {
    label.firstIndex(where: { $0 != "." && !$0.isNumber }) == nil
}
