import ActomatonCore
import XCTest

/// Tests for `MealyMachine`'s built-in synchronous action feedback loop (driven by `MealyOutput`).
final class MealyMachineActionFeedbackTests: XCTestCase
{
    func test_singleFeedback() async
    {
        let machine = MealyMachine<FeedbackAction, String, [FeedbackAction]>(
            state: "",
            reducer: MealyReducer { action, state, _ in
                switch action {
                case .start:
                    state = "started"
                    return [.finish]
                case .finish:
                    state = "finished"
                    return []
                }
            }
        )

        machine.send(.start)

        // Both .start and .finish should have been processed synchronously.
        let s = machine.state
        XCTAssertEqual(s, "finished")
    }

    func test_chainedFeedback() async
    {
        let machine = MealyMachine<ChainAction, [String], [ChainAction]>(
            state: [],
            reducer: MealyReducer { action, state, _ in
                switch action {
                case .step1:
                    state.append("step1")
                    return [.step2]
                case .step2:
                    state.append("step2")
                    return [.step3]
                case .step3:
                    state.append("step3")
                    return []
                }
            }
        )

        machine.send(.step1)
        let s = machine.state
        XCTAssertEqual(s, ["step1", "step2", "step3"])
    }

    func test_noFeedback() async
    {
        let machine = MealyMachine<ChainAction, [String], [ChainAction]>(
            state: [],
            reducer: MealyReducer { action, state, _ in
                state.append("\(action)")
                return []
            }
        )

        machine.send(.step1)
        var s = machine.state
        XCTAssertEqual(s, ["step1"])

        machine.send(.step2)
        s = machine.state
        XCTAssertEqual(s, ["step1", "step2"])
    }
}

// MARK: - Private

private enum FeedbackAction: Sendable
{
    case start
    case finish
}

private enum ChainAction: Sendable, CustomStringConvertible
{
    case step1
    case step2
    case step3

    var description: String
    {
        switch self {
        case .step1: "step1"
        case .step2: "step2"
        case .step3: "step3"
        }
    }
}
