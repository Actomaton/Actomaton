import Actomaton
import XCTest

final class SendResultTests: MainTestCase
{
    func test_actomatonSend_returnsEmissions() async throws
    {
        let actomaton = Actomaton<EmissionAction, EmissionState, String>(
            state: EmissionState(),
            reducer: emissionReducer,
            effectContext: effectContext
        )

        let result = await actomaton.send(.start, tracksFeedbacks: true)
        let values = await result.emissions
        let visitedActions = await actomaton.state.visitedActions

        XCTAssertEqual(values, ["start", "finish"])
        XCTAssertEqual(visitedActions, [.start, .finish])
    }

    func test_mealyDriverSend_returnsEmissions() async throws
    {
        let driver = MealyDriver<EmissionAction, EmissionState, String>(
            state: EmissionState(),
            reducer: emissionReducer,
            effectContext: effectContext
        )

        let result = driver.send(.start, tracksFeedbacks: true)
        let values = await result.emissions

        XCTAssertEqual(values, ["start", "finish"])
        XCTAssertEqual(driver.state.visitedActions, [.start, .finish])
    }

    // MARK: - In-band errors

    /// A `.single` effect that throws a non-cancellation error surfaces the error in-band as a
    /// `.failure` element, NOT by throwing from iteration.
    func test_actomatonSend_singleEffectThrows_deliversInBandFailure() async throws
    {
        let actomaton = Actomaton<ErrorAction, ErrorState, String>(
            state: ErrorState(),
            reducer: errorReducer,
            effectContext: effectContext
        )

        let result = await actomaton.send(.throwImmediately)
        let results = await result.allResults

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(result.isCancelled, false, "Finished by an in-band failure, not cancellation.")
        guard case let .failure(error)? = results.first else {
            return XCTFail("Expected a single `.failure` element, got \(results).")
        }
        XCTAssertEqual(error as? TestError, TestError())
    }

    /// An effect that emits a value and then throws delivers the value as `.success` followed by
    /// the error as `.failure` — both in-band, iteration never throws.
    func test_actomatonSend_emitsValueThenThrows() async throws
    {
        let actomaton = Actomaton<ErrorAction, ErrorState, String>(
            state: ErrorState(),
            reducer: errorReducer,
            effectContext: effectContext
        )

        let result = await actomaton.send(.emitThenThrow)

        var collected: [Result<String, any Error>] = []
        for await element in result {
            collected.append(element)
        }

        XCTAssertEqual(collected.count, 2)
        XCTAssertEqual(collected.first.flatMap { try? $0.get() }, "first")
        guard case let .failure(error)? = collected.last else {
            return XCTFail("Expected trailing `.failure`, got \(collected).")
        }
        XCTAssertEqual(error as? TestError, TestError())
    }

    /// **The core guarantee:** one effect throwing must NOT cancel its concurrent siblings.
    /// The sibling keeps running (across an `await`) and still emits its value.
    func test_actomatonSend_oneEffectThrows_doesNotCancelSiblings() async throws
    {
        let actomaton = Actomaton<ErrorAction, ErrorState, String>(
            state: ErrorState(),
            reducer: errorReducer,
            effectContext: effectContext
        )

        // `.concurrent` fires two independent single effects:
        //   - one throws immediately
        //   - one sleeps briefly then emits "delayed"
        // Under fail-fast aggregation the throw would cancel the sleeping sibling and "delayed"
        // would never arrive (or arrive as a CancellationError failure).
        let result = await actomaton.send(.concurrent)
        let results = await result.allResults

        let successes = results.compactMap { try? $0.get() }
        let failures = results.filter { if case .failure = $0 { return true } else { return false } }

        XCTAssertEqual(successes, ["delayed"], "Sibling effect must survive and emit its value.")
        XCTAssertEqual(failures.count, 1, "Exactly one effect failed in-band.")
    }

    /// A `CancellationError` thrown from inside an effect is swallowed (not reported as a
    /// `.failure`); the chain finishes cleanly.
    func test_actomatonSend_effectThrowsCancellationError_finishesCleanlyNoFailure() async throws
    {
        let actomaton = Actomaton<ErrorAction, ErrorState, String>(
            state: ErrorState(),
            reducer: errorReducer,
            effectContext: effectContext
        )

        let result = await actomaton.send(.throwCancellation)
        let results = await result.allResults

        XCTAssertTrue(results.isEmpty, "CancellationError must not surface as an in-band element.")
        XCTAssertFalse(result.isCancelled, "The effect threw cancellation; the chain itself wasn't cancelled.")
    }

    func test_firstResult_returnsInBandFailure() async throws
    {
        let actomaton = Actomaton<ErrorAction, ErrorState, String>(
            state: ErrorState(),
            reducer: errorReducer,
            effectContext: effectContext
        )

        let result = await actomaton.send(.throwImmediately)

        guard case let .failure(error)? = await result.firstResult else {
            return XCTFail("Expected first result to be an in-band failure.")
        }

        XCTAssertEqual(error as? TestError, TestError())
    }

    func test_neverEmission_completion_finishes() async throws
    {
        let actomaton = Actomaton<NeverEmissionAction, ErrorState, Never>(
            state: ErrorState(),
            reducer: neverEmissionReducer,
            effectContext: effectContext
        )

        let result = await actomaton.send(.throwImmediately)

        await result.completion()
        XCTAssertFalse(result.isCancelled)
    }

    func test_mealyDriverSend_singleEffectThrows_deliversInBandFailure() async throws
    {
        let driver = MealyDriver<ErrorAction, ErrorState, String>(
            state: ErrorState(),
            reducer: errorReducer,
            effectContext: effectContext
        )

        let result = driver.send(.throwImmediately)
        let errors = await result.errors

        XCTAssertEqual(errors.count, 1)
        XCTAssertEqual(errors.first as? TestError, TestError())
    }
}

// MARK: - Private

private enum EmissionAction: Equatable, Sendable
{
    case start
    case finish
}

private struct EmissionState: Equatable, Sendable
{
    var visitedActions: [EmissionAction] = []
}

private let emissionReducer = Reducer<EmissionAction, EmissionState, Void, String> { action, state, _ in
    state.visitedActions.append(action)

    switch action {
    case .start:
        return .emit("start") + .next(action: .finish)
    case .finish:
        return .emit("finish")
    }
}

// MARK: - Error helpers

private struct TestError: Error, Equatable {}

private enum ErrorAction: Equatable, Sendable
{
    case throwImmediately
    case emitThenThrow
    case throwCancellation
    case concurrent
}

private struct ErrorState: Equatable, Sendable {}

private let errorReducer = Reducer<ErrorAction, ErrorState, Void, String> { action, _, _ in
    switch action {
    case .throwImmediately:
        return Effect { _ in throw TestError() }

    case .emitThenThrow:
        return Effect.stream { send, _ in
            send(.emission("first"))
            throw TestError()
        }

    case .throwCancellation:
        return Effect { _ in throw CancellationError() }

    case .concurrent:
        // One effect throws immediately; the sibling sleeps then emits. If the throw were to
        // cancel siblings, "delayed" would never be emitted.
        let throwing = Effect<ErrorAction, String> { _ in throw TestError() }
        let delayed = Effect<ErrorAction, String> { _ in
            try await Task.sleep(for: .milliseconds(50))
            return .emission("delayed")
        }
        return throwing + delayed
    }
}

// MARK: - Never-emission helpers

private enum NeverEmissionAction: Equatable, Sendable
{
    case throwImmediately
}

private let neverEmissionReducer = Reducer<NeverEmissionAction, ErrorState, Void, Never> { action, _, _ in
    switch action {
    case .throwImmediately:
        return Effect.fireAndForget { _ in
            throw TestError()
        }
    }
}
