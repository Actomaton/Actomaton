import Actomaton

#if DEBUG
import CustomDump
#endif

extension Reducer
{
    /// Convenient constructor for debug-logging `Action` and `State` before target reducer's run,
    /// either by replacing `targetReducer = Reducer.init { ... }` with `Reducer.debug { ... }`
    /// or prepending as `Reducer.debug() + targetReducer`.
    ///
    /// - Warning: Only for debugging purpose, so should not use in production.
    public static func debug(
        name: String? = nil,
        action actionDebugStyle: ReducerDebugLogStyle? = .all(maxDepth: .max),
        state stateDebugStyle: ReducerDebugLogStyle? = .all(maxDepth: .max),
        _ nextRun: @escaping (Action, inout State, Environment) -> Effect<Action> = Reducer.empty.run
    ) -> Reducer
    {
#if DEBUG
        .init { action, state, environment in
            let state = state // Needs copy to not carry `inout`.
            return .fireAndForget {
                let name = name.map { "\($0) " } ?? ""

                if let actionDebugStyle = actionDebugStyle {
                    switch actionDebugStyle.style {
                    case .simple:
                        print("\(name)action = \(debugCaseOutput(action))")

                    case let .all(maxDepth):
                        print("\(name)action = ", terminator: "") // NOTE: No linebreak before `customDump`.
                        customDump(action, maxDepth: maxDepth)
                    }
                }

                if let stateDebugStyle = stateDebugStyle {
                    print("\(name)state = ", terminator: "") // NOTE: No linebreak before `customDump`.

                    switch stateDebugStyle.style {
                    case .simple:
                        var output = ""
                        customDump(state, to: &output, maxDepth: 1)
                        output = output.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                        print(output)

                    case let .all(maxDepth):
                        customDump(state, maxDepth: maxDepth)
                    }
                }
            }
        }
        + .init(nextRun)
#else
        .init(nextRun)
#endif
    }
}

/// Debug-logging style for `Reducer.debug` .
public struct ReducerDebugLogStyle: Equatable
{
    fileprivate let style: _DebugStyle

    /// Simple oneline-printing mode.
    public static let simple: ReducerDebugLogStyle = ReducerDebugLogStyle(style: .simple)

    /// Uses `CustomDump` to multiline-print all data.
    public static func all(maxDepth: Int = .max) -> ReducerDebugLogStyle
    {
        ReducerDebugLogStyle(style: .all(maxDepth: maxDepth))
    }

    enum _DebugStyle: Equatable
    {
        case simple
        case all(maxDepth: Int = .max)
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
