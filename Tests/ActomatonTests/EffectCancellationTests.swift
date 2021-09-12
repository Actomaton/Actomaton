import XCTest
@testable import Actomaton

import Combine

/// Tests for `Effect.cancel`.
final class EffectCancellationTests: XCTestCase
{
    fileprivate var actomaton: Actomaton<Action, State>!

    fileprivate var is1To2Cancelled = false
    fileprivate var is2To3Cancelled = false

    override func setUp() async throws
    {
        is1To2Cancelled = false
        is2To3Cancelled = false

        struct EffectID1To2: EffectIDProtocol {}
        struct EffectID2To3: EffectIDProtocol {}

        let actomaton = Actomaton<Action, State>(
            state: ._1,
            reducer: Reducer { action, state, _ in
                switch action {
                case ._1To2:
                    guard state == ._1 else { return .empty }

                    state = ._2
                    return Effect(id: EffectID1To2()) {
                        await tick(1)
                        if Task.isCancelled {
                            Debug.print("_1To2 cancelled")
                            self.is1To2Cancelled = true
                            return nil
                        }
                        return ._2To3
                    }

                case ._2To3:
                    guard state == ._2 else { return .empty }

                    state = ._3
                    return Effect(id: EffectID2To3()) {
                        await tick(1)
                        if Task.isCancelled {
                            Debug.print("_2To3 cancelled")
                            self.is2To3Cancelled = true
                            return nil
                        }
                        return ._3To4
                    }

                case ._3To4:
                    guard state == ._3 else { return .empty }

                    state = ._4
                    return .empty

                case ._cancel1To2:
                    state = .cancelled
                    return Effect {
                        await tick(1)
                        return nil
                    } + Effect.cancel(id: EffectID1To2())

                case ._cancel2To3:
                    state = .cancelled
                    return Effect {
                        await tick(1)
                        return nil
                    } + Effect.cancel(id: EffectID2To3())
                }

            }
        )
        self.actomaton = actomaton

        var cancellables: [AnyCancellable] = []

        await actomaton.$state
            .sink(receiveValue: { state in
                Debug.print("publisher: state = \(state)")
            })
            .store(in: &cancellables)
    }

    func test_noInterrupt() async throws
    {
        assertEqual(await actomaton.state, ._1)

        await actomaton.send(._1To2)
        assertEqual(await actomaton.state, ._2)

        await tick(1.5)
        assertEqual(await actomaton.state, ._3)

        await tick(1.5)
        assertEqual(await actomaton.state, ._4)

        XCTAssertFalse(is1To2Cancelled)
        XCTAssertFalse(is2To3Cancelled)
    }

    func test_cancel1To2_at_0() async throws
    {
        assertEqual(await actomaton.state, ._1)

        await actomaton.send(._1To2)
        assertEqual(await actomaton.state, ._2)

        await tick(0.1)
        assertEqual(await actomaton.state, ._2,
                    "Only delta time has passed, so state should not change")

        // Cancel 1To2.
        await actomaton.send(._cancel1To2)
        assertEqual(await actomaton.state, .cancelled)

        await tick(5)
        assertEqual(await actomaton.state, .cancelled,
                    "Waited for enough time, and state should not change")

        XCTAssertTrue(is1To2Cancelled, "Should cancel.")
        XCTAssertFalse(is2To3Cancelled)
    }

    func test_cancel1To2_at_1_tooLate() async throws
    {
        assertEqual(await actomaton.state, ._1)

        await actomaton.send(._1To2)
        assertEqual(await actomaton.state, ._2)

        // Wait until `state = _3`.
        await tick(1.3)
        assertEqual(await actomaton.state, ._3)

        await tick(0.1)
        assertEqual(await actomaton.state, ._3,
                    "Only delta time has passed, so state should not change")

        // Cancel 1To2.
        await actomaton.send(._cancel1To2)
        assertEqual(await actomaton.state, .cancelled)

        await tick(5)
        assertEqual(await actomaton.state, .cancelled,
                    "Waited for enough time, and state should not change")

        XCTAssertFalse(is1To2Cancelled, "Should not cancel because send is too late.")
        XCTAssertFalse(is2To3Cancelled)
    }

    func test_cancel2To3_at_0_tooEarly() async throws
    {
        assertEqual(await actomaton.state, ._1)

        await actomaton.send(._1To2)
        assertEqual(await actomaton.state, ._2)

        await tick(0.1)
        assertEqual(await actomaton.state, ._2,
                    "Only delta time has passed, so state should not change")

        // Cancel 2To3.
        await actomaton.send(._cancel2To3)
        assertEqual(await actomaton.state, .cancelled)

        await tick(5)
        assertEqual(await actomaton.state, .cancelled,
                    "Waited for enough time, and state should not change")

        XCTAssertFalse(is1To2Cancelled, "Should not cancel because send is too early.")
        XCTAssertFalse(is2To3Cancelled)
    }

    func test_cancel2To3_at_1() async throws
    {
        assertEqual(await actomaton.state, ._1)

        await actomaton.send(._1To2)
        assertEqual(await actomaton.state, ._2)

        // Wait until `state = _3`.
        await tick(1.3)
        assertEqual(await actomaton.state, ._3)

        await tick(0.1)
        assertEqual(await actomaton.state, ._3,
                    "Only delta time has passed, so state should not change")

        // Cancel 2To3.
        await actomaton.send(._cancel2To3)
        assertEqual(await actomaton.state, .cancelled)

        await tick(5)
        assertEqual(await actomaton.state, .cancelled,
                    "Waited for enough time, and state should not change")

        XCTAssertFalse(is1To2Cancelled)
        XCTAssertTrue(is2To3Cancelled, "Should cancel.")
    }
}

// MARK: - Private

private enum Action
{
    case _1To2
    case _2To3
    case _3To4
    case _cancel1To2
    case _cancel2To3
}

private enum State
{
    case _1
    case _2
    case _3
    case _4
    case cancelled
}
