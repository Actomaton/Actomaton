import ActomatonCore
import XCTest

/// Double-loop implemented with **two nested** `MealyMachine` instances using `ActionEffectManager`.
/// See ``makeOuterMachine(m:)`` for the corresponding `MealyMachine` construction.
final class DoubleLoopDoubleMealyMachineTests: XCTestCase
{
    func test_doubleLoop() async
    {
        let n = 3
        let m = 4

        let machine = makeOuterMachine(n: n, m: m)
        await machine.send(.start)

        let state = await machine.state
        XCTAssertEqual(state.results.count, n * m)
        XCTAssertEqual(state.results, makeExpectedPairs(n: n, m: m))
    }

    func test_doubleLoop_zeroN() async
    {
        let machine = makeOuterMachine(n: 0, m: 3)
        await machine.send(.start)

        let results = await machine.state.results
        XCTAssertEqual(results, [])
    }

    func test_doubleLoop_zeroM() async
    {
        let machine = makeOuterMachine(n: 3, m: 0)
        await machine.send(.start)

        let results = await machine.state.results
        XCTAssertEqual(results, [])
    }
}

// MARK: - Private

private enum OuterAction: Sendable
{
    case start
    case innerDone(results: [Pair])
}

private struct OuterState: Equatable, Sendable
{
    var i: Int = 0
    var results: [Pair] = []
}

private struct Pair: Equatable, Sendable
{
    var i: Int
    var j: Int
}

/// Constructs an outer `MealyMachine` that drives the `i` loop via action feedback.
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
/// maps to the following structure in pseudocode:
///
/// ```
/// i = 0
/// while i < N:
///     results = inner_machine_run(i, M)   // delegated computation
///     collect(results)
///     i += 1
/// ```
///
/// Since the reducer must be synchronous, the inner loop results are computed inline
/// using `makePairsForRow` (a pure computation), and action feedback drives the `i` loop.
/// Each `.innerDone(results)` action appends results, increments `i`, and feeds back
/// the next iteration — or returns `nil` when all rows are complete.
private func makeOuterMachine(n: Int, m: Int) -> MealyMachine<OuterAction, OuterState, OuterAction?>
{
    MealyMachine(
        state: OuterState(),
        reducer: MealyReducer { action, state, _ in
            switch action {
            case .start:
                guard n > 0 && m > 0 else { return nil }
                let results = makePairsForRow(i: 0, m: m)
                return .innerDone(results: results)

            case let .innerDone(results):
                state.results.append(contentsOf: results)
                state.i += 1

                if state.i < n {
                    let innerResults = makePairsForRow(i: state.i, m: m)
                    return .innerDone(results: innerResults)
                }
                else {
                    return nil
                }
            }
        },
        effectManager: ActionEffectManager()
    )
}

private func makePairsForRow(i: Int, m: Int) -> [Pair]
{
    (0 ..< m).map { j in Pair(i: i, j: j) }
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
