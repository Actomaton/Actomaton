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

        await actomaton.whenLocal { local in
            local.send(1)
            local.send(2)
            local.send(3)
        }

        await recorder.waitForCount(3)
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

    func waitForCount(_ count: Int) async
    {
        while values.count < count {
            try? await Task.sleep(for: .milliseconds(5))
        }
    }
}
