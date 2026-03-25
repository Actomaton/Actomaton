import ActomatonCore
import XCTest

/// Double-loop implemented with a **single** `MealyMachine` using `ActionEffectManager`.
/// See ``makeDoubleLoopMachine()`` for the corresponding `MealyMachine` construction.
final class DoubleLoopSingleMealyMachineTests: XCTestCase
{
    func test_doubleLoop() async
    {
        let n = 3
        let m = 4

        let machine = makeDoubleLoopMachine(n: n, m: m)
        await machine.send(.start)

        let state = await machine.state
        XCTAssertEqual(state.results.count, n * m)
        XCTAssertEqual(state.results, makeExpectedPairs(n: n, m: m))
    }

    func test_doubleLoop_zeroN() async
    {
        let machine = makeDoubleLoopMachine(n: 0, m: 3)
        await machine.send(.start)

        let results = await machine.state.results
        XCTAssertEqual(results, [])
    }

    func test_doubleLoop_zeroM() async
    {
        let machine = makeDoubleLoopMachine(n: 3, m: 0)
        await machine.send(.start)

        let results = await machine.state.results
        XCTAssertEqual(results, [])
    }
}

// MARK: - Private

private enum LoopAction: Sendable
{
    case start
    case doSomething(i: Int, j: Int)
}

private struct Pair: Equatable, Sendable
{
    var i: Int
    var j: Int
}

private struct LoopState: Equatable, Sendable
{
    var results: [Pair] = []
}

/// Constructs a single `MealyMachine` that runs the double-loop via action feedback.
///
/// The original double while-loop:
///
/// ```
/// i = 0
/// while i < N:
///     j = 0
///     while j < M:
///         do_something(i, j)
///         j += 1
///     i += 1
/// ```
///
/// is normalized into a flattened single loop:
///
/// ```
/// i, j = 0, 0
/// while i < N:
///     do_something(i, j)
///     if j + 1 < M:
///         j += 1          // inner step
///     else:
///         i += 1; j = 0   // outer step
/// ```
///
/// Each iteration maps to a `.doSomething(i, j)` action whose reducer returns
/// the next `(i, j)` as feedback, or `nil` when done.
private func makeDoubleLoopMachine(n: Int, m: Int) -> MealyMachine<LoopAction, LoopState, LoopAction?>
{
    MealyMachine(
        state: LoopState(),
        reducer: MealyReducer { action, state, _ in
            switch action {
            case .start:
                guard n > 0 && m > 0 else { return nil }
                return .doSomething(i: 0, j: 0)

            case let .doSomething(i, j):
                state.results.append(Pair(i: i, j: j))

                if j + 1 < m {
                    return .doSomething(i: i, j: j + 1)
                }
                else if i + 1 < n {
                    return .doSomething(i: i + 1, j: 0)
                }
                else {
                    return nil
                }
            }
        },
        effectManager: ActionEffectManager()
    )
}

private func makeExpectedPairs(n: Int, m: Int) -> [Pair]
{
    var expected: [Pair] = []
    for i in 0 ..< n {
        for j in 0 ..< m {
            expected.append(Pair(i: i, j: j))
        }
    }
    return expected
}
