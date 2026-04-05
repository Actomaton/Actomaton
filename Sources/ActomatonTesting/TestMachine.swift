import ActomatonCore
import ActomatonEffect
import CustomDump
import XCTest

/// A testing utility that wraps `MealyMachine` + `ActionEffectManager` to provide
/// exhaustive state-transition assertions with readable diff output.
///
/// ```swift
/// let tm = TestMachine(
///     state: MyState(),
///     reducer: myReducer,
///     environment: ()
/// )
///
/// await tm.send(.increment) { state in
///     state.count = 1
/// }
///
/// await tm.send(.login) { state in
///     state.isLoggedIn = true
///     state.username = "alice"
/// }
/// ```
public final class TestMachine<Action, State, Environment>
    where Action: Sendable, State: Sendable & Equatable, Environment: Sendable
{
    private let machine: MealyMachine<Action, State, [Action]>

    /// Creates a `TestMachine` with a reducer that already outputs `[Action]`.
    public init(
        state: State,
        reducer: MealyReducer<Action, State, Environment, [Action]>,
        environment: Environment
    )
    {
        let envReducer = MealyReducer<Action, State, (), [Action]> { action, state, _ in
            reducer.run(action, &state, environment)
        }

        self.machine = MealyMachine(
            state: state,
            reducer: envReducer,
            effectManager: ActionEffectManager()
        )
    }

    /// Creates a `TestMachine` from an `Effect`-based reducer.
    ///
    /// The reducer's `Effect<Action>` output is transformed via `map(output:)` to extract
    /// synchronous `.next` actions, discarding async effects. This enables deterministic,
    /// synchronous testing using `ActionEffectManager`.
    public convenience init(
        state: State,
        reducer: MealyReducer<Action, State, Environment, Effect<Action>>,
        environment: Environment
    )
    {
        let mappedReducer: MealyReducer<Action, State, Environment, [Action]> = reducer.map(output: { effect in
            effect.kinds.compactMap { kind in
                if case let .next(action) = kind { return action }
                return nil
            }
        })

        self.init(state: state, reducer: mappedReducer, environment: environment)
    }

    /// Sends an action and asserts state changes exhaustively.
    ///
    /// The closure receives `expectedState` as `inout`. Mutate it to declare
    /// what the state should look like after the action. If the mutated expected state
    /// differs from the actual state, the test fails with a `customDump` diff.
    ///
    /// - Parameters:
    ///   - action: The action to send.
    ///   - assert: A closure that mutates the expected state. Omit if the state should not change.
    public func send(
        _ action: Action,
        fileID: StaticString = #fileID,
        file filePath: StaticString = #filePath,
        line: UInt = #line,
        assert: ((_ state: inout State) -> Void)? = nil
    ) async
    {
        var expected = await machine.state
        await machine.send(action)
        let actual = await machine.state

        assert?(&expected)

        if expected != actual {
            let diff = CustomDump.diff(expected, actual) ?? "(diff unavailable)"

            XCTFail(
                """
                State mismatch after sending \(action):

                  \(fileID):\(line)

                \(diff)
                """,
                file: filePath,
                line: line
            )
        }
    }
}
