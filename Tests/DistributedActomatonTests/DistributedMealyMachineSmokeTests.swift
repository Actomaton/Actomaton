import Distributed
import DistributedActomaton
import XCTest

final class DistributedActomatonSmokeTests: XCTestCase
{
    func test_send_runsReducer_overLocalTestingActorSystem() async throws
    {
        let recorder = Recorder()

        let actomaton = DistributedActomaton<Int, Int, LocalTestingDistributedActorSystem>(
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

        // Await each send's effect task before the next send so the recorder's
        // append order is deterministic (concurrent fire-and-forget effects would
        // otherwise race, e.g. recording [1, 6, 3]).
        await actomaton.whenLocal { local in
            await local.sendLocal(1)?.value
            await local.sendLocal(2)?.value
            await local.sendLocal(3)?.value
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
