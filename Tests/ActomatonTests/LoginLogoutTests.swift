import XCTest
@testable import Actomaton

import Combine

final class LoginLogoutTests: XCTestCase
{
    fileprivate var actomaton: Actomaton<Action, State>!

    private var flags = Flags()

    private actor Flags
    {
        var isLoginCancelled = false

        func mark(
            isLoginCancelled: Bool? = nil
        )
        {
            if let isLoginCancelled = isLoginCancelled {
                self.isLoginCancelled = isLoginCancelled
            }
        }
    }

    override func setUp() async throws
    {
        flags = Flags()

        struct LoginFlowEffectQueue: Newest1EffectQueueProtocol {}

        let actomaton = Actomaton<Action, State>(
            state: .loggedOut,
            reducer: Reducer { [flags] action, state, _ in
                switch (action, state) {
                case (.login, .loggedOut):
                    state = .loggingIn
                    return Effect(queue: LoginFlowEffectQueue()) {
                        await tick(1)
                        if Task.isCancelled {
                            await flags.mark(isLoginCancelled: true)
                            return nil
                        }
                        return .loginOK
                    }

                case (.loginOK, .loggingIn):
                    state = .loggedIn
                    return .empty

                case (.logout, .loggedIn),
                    (.forceLogout, .loggingIn),
                    (.forceLogout, .loggedIn):
                    state = .loggingOut
                    return Effect(queue: LoginFlowEffectQueue()) {
                        await tick(1)
                        return .logoutOK
                    }

                case (.logoutOK, .loggingOut):
                    state = .loggedOut
                    return .empty

                default:
                    return .empty
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

    func test_noChange_wrongAction() async throws
    {
        assertEqual(await actomaton.state, .loggedOut)

        await actomaton.send(.logout) // wrong action
        assertEqual(await actomaton.state, .loggedOut, "No change, because of wrong action")

        let isLoginCancelled = await flags.isLoginCancelled
        XCTAssertFalse(isLoginCancelled)
    }

    // `loggedOut => loggingIn => loggedIn => loggingOut => loggedOut` succeeds.
    func test_login_logout() async throws
    {
        var t: Task<(), Error>?

        assertEqual(await actomaton.state, .loggedOut)

        t = await actomaton.send(.login)
        assertEqual(await actomaton.state, .loggingIn)

        try await t?.value // wait for previous effect
        assertEqual(await actomaton.state, .loggedIn)

        t = await actomaton.send(.logout)
        assertEqual(await actomaton.state, .loggingOut)

        try await t?.value // wait for previous effect
        assertEqual(await actomaton.state, .loggedOut)

        let isLoginCancelled = await flags.isLoginCancelled
        XCTAssertFalse(isLoginCancelled)
    }

    // `loggedOut => loggingIn ==(ForceLogout)==> loggingOut => loggedOut` succeeds.
    func test_login_forceLogout() async throws
    {
        var t: Task<(), Error>?

        assertEqual(await actomaton.state, .loggedOut)

        await actomaton.send(.login)
        assertEqual(await actomaton.state, .loggingIn)

        // Wait for a while and interrupt by `forceLogout`.
        await tick(0.1)
        t = await actomaton.send(.forceLogout)

        assertEqual(await actomaton.state, .loggingOut)

        try await t?.value // wait for previous effect
        assertEqual(await actomaton.state, .loggedOut)

        let isLoginCancelled = await flags.isLoginCancelled
        XCTAssertTrue(isLoginCancelled,
                      "login's effect should be cancelled")
    }
}

// MARK: - Private

private enum Action
{
    case login
    case loginOK
    case logout
    case logoutOK
    case forceLogout
}

private enum State
{
    case loggingIn
    case loggedIn
    case loggingOut
    case loggedOut
}
