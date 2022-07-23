import Actomaton

#if DEBUG
import CustomDump
#endif

// MARK: - debug (logging on `#if DEBUG`)

extension Reducer
{
    /// Debug-logging `Action` and `State` during `self`'s reducer's run, only in DEBUG configuration.
    public func debug(
        _ name: String? = nil,
        action actionLogFormat: ActionLogFormat? = .all(maxDepth: .max),
        state stateLogFormat: StateLogFormat? = .diff
    ) -> Reducer
        where Action: Sendable, State: Sendable
    {
#if DEBUG
        self.log(format: LogFormat(name: name, action: actionLogFormat, state: stateLogFormat))
#else
        self
#endif
    }

    /// Convenient constructor for debug-logging `Action` and `State` during target reducer's run,
    /// by replacing `targetReducer = Reducer.init { ... }` with `Reducer.debug { ... }`,
    /// only in DEBUG configuration.
    public static func debug(
        _ name: String? = nil,
        action actionLogFormat: ActionLogFormat? = .all(maxDepth: .max),
        state stateLogFormat: StateLogFormat? = .diff,
        _ nextRun: @escaping @Sendable (Action, inout State, Environment) -> Effect<Action> = Reducer.empty.run
    ) -> Reducer
        where Action: Sendable, State: Sendable
    {
#if DEBUG
        self.log(
            format: LogFormat(name: name, action: actionLogFormat, state: stateLogFormat),
            nextRun
        )
#else
        Reducer(nextRun)
#endif
    }
}

// MARK: - log

extension Reducer
{
    /// Debug-logging `Action` and `State` during `self`'s reducer's run, using ``LogFormat``.
    ///
    /// - Parameters:
    ///   - format: ``LogFormat`` that formats console-logging. No logging if `format = nil`.
    public func log(format: LogFormat?) -> Reducer
        where Action: Sendable, State: Sendable
    {
        Self.log(format: format, self.run)
    }

    /// Convenient constructor for debug-logging `Action` and `State` during target reducer's run using ``LogFormat``
    /// by replacing `targetReducer = Reducer.init { ... }` with `Reducer.debug { ... }`.
    ///
    /// - Parameters:
    ///   - format: ``LogFormat`` that formats console-logging. No logging if `format = nil`.
    public static func log(
        format: LogFormat?,
        _ nextRun: @escaping @Sendable (Action, inout State, Environment) -> Effect<Action> = Reducer.empty.run
    ) -> Reducer
        where Action: Sendable, State: Sendable
    {
        // Return normal reducer without logging.
        guard let format = format else {
            return Reducer(nextRun)
        }

        return Reducer { action, state, environment in
            let currentState = state // Needs copy to not carry `inout`.

            /// Effect for  Action & State `.simple` or `.all` printing.
            let preEffect = Effect<Action>.fireAndForget {
                let name = format.name.map { "\($0) " } ?? ""

                if let actionLogFormat = format.actionLogFormat {
                    switch actionLogFormat.format {
                    case .simple:
                        print("\(name)action = \(debugCaseOutput(action))")

                    case let .all(maxDepth):
                        print("\(name)action = ", terminator: "") // NOTE: No linebreak before `customDump`.
                        customDump(action, maxDepth: maxDepth)
                    }
                }

                if let stateLogFormat = format.stateLogFormat {
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
                if let stateLogFormat = format.stateLogFormat {
                    switch stateLogFormat.format {
                    case .simple, .all:
                        break

                    case .diff:
                        let name = format.name.map { "\($0) " } ?? ""

                        if let diffString = diff(currentState, nextState) {
                            print("\(name)state diff = ") // NOTE: Adds linebreak because `diffString` contains +- symbols.
                            print(diffString)
                        }
                        else {
                            print("\(name)state diff = (no diff)")
                        }
                    }
                }
            }

            return preEffect + effect + postEffect
        }
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
