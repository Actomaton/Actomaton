import XCTest
@testable import Actomaton

#if !DISABLE_COMBINE && canImport(Combine)
import Combine
#endif

/// Tests for `Effect.cancel`.
final class EffectCancellationTests: MainTestCase
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

        struct EffectID1To2: EffectIDProtocol {}
        struct EffectID2To3: EffectIDProtocol {}

        let actomaton = Actomaton<Action, State>(
            state: ._1,
            reducer: Reducer { [flags] action, state, _ in
                switch action {
                case ._1To2:
                    guard state == ._1 else { return .empty }

                    state = ._2
                    return Effect(id: EffectID1To2()) {
                        try await tick(1) {
                            return ._2To3
                        } ifCancelled: {
                            Debug.print("_1To2 cancelled")
                            await flags.mark(is1To2Cancelled: true)
                            return nil
                        }
                    }

                case ._2To3:
                    guard state == ._2 else { return .empty }

                    state = ._3
                    return Effect(id: EffectID2To3()) {
                        try await tick(1) {
                            return ._3To4
                        } ifCancelled: {
                            Debug.print("_2To3 cancelled")
                            await flags.mark(is2To3Cancelled: true)
                            return nil
                        }
                    }

                case ._3To4:
                    guard state == ._3 else { return .empty }

                    state = ._4
                    return .empty

                case ._cancel1To2:
                    state = .cancelled
                    return Effect {
                        try await tick(1)
                        return nil
                    } + Effect.cancel(id: EffectID1To2())

                case ._cancel2To3:
                    state = .cancelled
                    return Effect {
                        try await tick(1)
                        return nil
                    } + Effect.cancel(id: EffectID2To3())
                }

            }
        )
        self.actomaton = actomaton

#if !DISABLE_COMBINE && canImport(Combine)
        var cancellables: [AnyCancellable] = []

        await actomaton.$state
            .sink(receiveValue: { state in
                Debug.print("publisher: state = \(state)")
            })
            .store(in: &cancellables)
#endif
    }

    func test_noInterrupt() async throws
    {
        assertEqual(await actomaton.state, ._1)

        await actomaton.send(._1To2)
        assertEqual(await actomaton.state, ._2)

        try await tick(1.5)
        assertEqual(await actomaton.state, ._3)

        try await tick(1.5)
        assertEqual(await actomaton.state, ._4)

        let is1To2Cancelled = await flags.is1To2Cancelled
        XCTAssertFalse(is1To2Cancelled)

        let is2To3Cancelled = await flags.is2To3Cancelled
        XCTAssertFalse(is2To3Cancelled)
    }

    func test_cancel1To2_at_0() async throws
    {
        assertEqual(await actomaton.state, ._1)

        await actomaton.send(._1To2)
        assertEqual(await actomaton.state, ._2)

        try await tick(0.1)
        assertEqual(await actomaton.state, ._2,
                    "Only delta time has passed, so state should not change")

        // Cancel 1To2.
        await actomaton.send(._cancel1To2)
        assertEqual(await actomaton.state, .cancelled)

        try await tick(5)
        assertEqual(await actomaton.state, .cancelled,
                    "Waited for enough time, and state should not change")

        let is1To2Cancelled = await flags.is1To2Cancelled
        XCTAssertTrue(is1To2Cancelled, "Should cancel.")

        let is2To3Cancelled = await flags.is2To3Cancelled
        XCTAssertFalse(is2To3Cancelled)
    }

    func test_cancel1To2_at_1_tooLate() async throws
    {
        assertEqual(await actomaton.state, ._1)

        await actomaton.send(._1To2)
        assertEqual(await actomaton.state, ._2)

        // Wait until `state = _3`.
        try await tick(1.3)
        assertEqual(await actomaton.state, ._3)

        try await tick(0.1)
        assertEqual(await actomaton.state, ._3,
                    "Only delta time has passed, so state should not change")

        // Cancel 1To2.
        await actomaton.send(._cancel1To2)
        assertEqual(await actomaton.state, .cancelled)

        try await tick(5)
        assertEqual(await actomaton.state, .cancelled,
                    "Waited for enough time, and state should not change")

        let is1To2Cancelled = await flags.is1To2Cancelled
        XCTAssertFalse(is1To2Cancelled, "Should not cancel because send is too late.")

        let is2To3Cancelled = await flags.is2To3Cancelled
        XCTAssertFalse(is2To3Cancelled)
    }

    func test_cancel2To3_at_0_tooEarly() async throws
    {
        assertEqual(await actomaton.state, ._1)

        await actomaton.send(._1To2)
        assertEqual(await actomaton.state, ._2)

        try await tick(0.1)
        assertEqual(await actomaton.state, ._2,
                    "Only delta time has passed, so state should not change")

        // Cancel 2To3.
        await actomaton.send(._cancel2To3)
        assertEqual(await actomaton.state, .cancelled)

        try await tick(5)
        assertEqual(await actomaton.state, .cancelled,
                    "Waited for enough time, and state should not change")

        let is1To2Cancelled = await flags.is1To2Cancelled
        XCTAssertFalse(is1To2Cancelled, "Should not cancel because send is too early.")

        let is2To3Cancelled = await flags.is2To3Cancelled
        XCTAssertFalse(is2To3Cancelled)
    }

    func test_cancel2To3_at_1() async throws
    {
        assertEqual(await actomaton.state, ._1)

        await actomaton.send(._1To2)
        assertEqual(await actomaton.state, ._2)

        // Wait until `state = _3`.
        try await tick(1.3)
        assertEqual(await actomaton.state, ._3)

        try await tick(0.1)
        assertEqual(await actomaton.state, ._3,
                    "Only delta time has passed, so state should not change")

        // Cancel 2To3.
        await actomaton.send(._cancel2To3)
        assertEqual(await actomaton.state, .cancelled)

        try await tick(5)
        assertEqual(await actomaton.state, .cancelled,
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
