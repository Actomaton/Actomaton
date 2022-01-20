import XCTest
@testable import Actomaton

import Combine

/// Tests for `Newest1EffectQueueProtocol` where previous effect will be automatically cancelled by the next effect.
final class EffectIDAutoCancellationTests: XCTestCase
{
    fileprivate var actomaton: Actomaton<Action, State>!

    private var flags = Flags()

    private actor Flags
    {
        var is1To2Cancelled = false
        var is2To3Cancelled = false

        func mark(
            is1To2Cancelled: Bool? = nil,
            is2To3Cancelled: Bool? = nil
        )
        {
            if let is1To2Cancelled = is1To2Cancelled {
                self.is1To2Cancelled = is1To2Cancelled
            }
            if let is2To3Cancelled = is2To3Cancelled {
                self.is2To3Cancelled = is2To3Cancelled
            }
        }
    }

    override func setUp() async throws
    {
        flags = Flags()

        struct Newest1EffectQueue: Newest1EffectQueueProtocol {}

        let actomaton = Actomaton<Action, State>(
            state: ._1,
            reducer: Reducer { [flags] action, state, _ in
                switch action {
                case ._1To2:
                    guard state == ._1 else { return .empty }

                    state = ._2
                    return Effect(queue: Newest1EffectQueue()) {
                        await tick(1)
                        if Task.isCancelled {
                            Debug.print("_1To2 cancelled")
                            await flags.mark(is1To2Cancelled: true)
                            return nil
                        }
                        return ._2To3
                    }

                case ._2To3:
                    guard state == ._2 else { return .empty }

                    state = ._3
                    return Effect(queue: Newest1EffectQueue()) {
                        await tick(1)
                        if Task.isCancelled {
                            Debug.print("_2To3 cancelled")
                            await flags.mark(is2To3Cancelled: true)
                            return nil
                        }
                        return ._3To4
                    }

                case ._3To4:
                    guard state == ._3 else { return .empty }

                    state = ._4
                    return .empty

                case ._toEnd:
                    state = ._end
                    return Effect(queue: Newest1EffectQueue()) {
                        await tick(1)
                        return nil
                    }
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

        let is1To2Cancelled = await flags.is1To2Cancelled
        XCTAssertFalse(is1To2Cancelled)

        let is2To3Cancelled = await flags.is2To3Cancelled
        XCTAssertFalse(is2To3Cancelled)
    }

    func test_interrupt_at_0() async throws
    {
        assertEqual(await actomaton.state, ._1)

        await actomaton.send(._1To2)
        assertEqual(await actomaton.state, ._2)

        await tick(0.1)
        assertEqual(await actomaton.state, ._2,
                    "Only delta time has passed, so state should not change")

        await actomaton.send(._toEnd)
        assertEqual(await actomaton.state, ._end)

        await tick(5)
        assertEqual(await actomaton.state, ._end,
                    "Waited for enough time, and state should not change")

        let is1To2Cancelled = await flags.is1To2Cancelled
        XCTAssertTrue(is1To2Cancelled)

        let is2To3Cancelled = await flags.is2To3Cancelled
        XCTAssertFalse(is2To3Cancelled)
    }

    func test_interrupt_at_1() async throws
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

        await actomaton.send(._toEnd)
        assertEqual(await actomaton.state, ._end)

        await tick(5)
        assertEqual(await actomaton.state, ._end,
                    "Waited for enough time, and state should not change")

        let is1To2Cancelled = await flags.is1To2Cancelled
        XCTAssertFalse(is1To2Cancelled)

        let is2To3Cancelled = await flags.is2To3Cancelled
        XCTAssertTrue(is2To3Cancelled)
    }
}

// MARK: - Private

private enum Action
{
    case _1To2
    case _2To3
    case _3To4
    case _toEnd
}

private enum State
{
    case _1
    case _2
    case _3
    case _4
    case _end
}
