import Distributed
import DistributedActomaton
import XCTest

final class DistributedActomatonSmokeTests: XCTestCase
{
    func test_send_runsReducer_overLocalTestingActorSystem() async throws
    {
        let recorder = Recorder()

        let actomaton = DistributedActomaton<Int, Int, Never, LocalTestingDistributedActorSystem>(
            state: 0,
            reducer: Reducer { action, state, _ in
                state += action
                let snapshot = state
                return Effect.fireAndForget { _ in
                    await recorder.append(snapshot)
                }
            },
            actorSystem: LocalTestingDistributedActorSystem()
        )

        // `SendResults.completion()` awaits the whole effect chain deterministically,
        // so no polling is needed before asserting.
        await actomaton.whenLocal { local in
            await local.sendLocal(1).completion()
            await local.sendLocal(2).completion()
            await local.sendLocal(3).completion()
        }

        let values = await recorder.values
        XCTAssertEqual(values, [1, 3, 6])
    }
}

private actor Recorder
{
    private(set) var values: [Int] = []

    func append(_ value: Int)
    {
        values.append(value)
    }
}
