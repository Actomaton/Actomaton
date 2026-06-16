import Actomaton
import XCTest

final class LoginLogoutTests: MainTestCase
{
    fileprivate var actomaton: Actomaton<Action, State, Never>!

    private var flags = Flags()

    private actor Flags
    {
        var isLoginCancelled = false

        func mark(
            isLoginCancelled: Bool? = nil
        )
        {
            if let isLoginCancelled {
                self.isLoginCancelled = isLoginCancelled
            }
        }
    }

    override func setUp() async throws
    {
        flags = Flags()

        struct LoginFlowEffectQueue: Newest1EffectQueue {}

        let actomaton = Actomaton<Action, State, Never>(
            state: .loggedOut,
            reducer: Reducer { [flags] action, state, _ in
                switch (action, state) {
                case (.login, .loggedOut):
                    state = .loggingIn
                    return Effect(queue: LoginFlowEffectQueue()) { context in
                        do {
                            return try await context.clock.sleep(for: .ticks(1)) {
                                return .loginOK
                            } ifCancelled: {
                                await flags.mark(isLoginCancelled: true)
                                return nil
                            }
                        }
                        catch {
                            return nil
                        }
                    }

                case (.loginOK, .loggingIn):
                    state = .loggedIn
                    return .empty

                case (.logout, .loggedIn),
                     (.forceLogout, .loggingIn),
                     (.forceLogout, .loggedIn):
                    state = .loggingOut
                    return Effect(queue: LoginFlowEffectQueue()) { context in
                        try await context.clock.sleep(for: .ticks(1))
                        return .logoutOK
                    }

                case (.logoutOK, .loggingOut):
                    state = .loggedOut
                    return .empty

                default:
                    return .empty
                }
            },
            effectContext: effectContext
        )
        self.actomaton = actomaton
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
        var results: SendResults<Never>?

        assertEqual(await actomaton.state, .loggedOut)

        results = await actomaton.send(.login)
        assertEqual(await actomaton.state, .loggingIn)

        await clock.advance(by: .ticks(1))
        await results?.completion // wait for previous effect
        assertEqual(await actomaton.state, .loggedIn)

        results = await actomaton.send(.logout)
        assertEqual(await actomaton.state, .loggingOut)

        await clock.advance(by: .ticks(1))
        await results?.completion // wait for previous effect
        assertEqual(await actomaton.state, .loggedOut)

        let isLoginCancelled = await flags.isLoginCancelled
        XCTAssertFalse(isLoginCancelled)
    }

    // `loggedOut => loggingIn ==(ForceLogout)==> loggingOut => loggedOut` succeeds.
    func test_login_forceLogout() async throws
    {
        var results: SendResults<Never>?

        assertEqual(await actomaton.state, .loggedOut)

        await actomaton.send(.login)
        assertEqual(await actomaton.state, .loggingIn)

        // Wait for a while and interrupt by `forceLogout`.
        await clock.advance(by: .ticks(0.1))
        results = await actomaton.send(.forceLogout)

        assertEqual(await actomaton.state, .loggingOut)

        await clock.advance(by: .ticks(1))
        await results?.completion // wait for previous effect
        assertEqual(await actomaton.state, .loggedOut)

        let isLoginCancelled = await flags.isLoginCancelled
        XCTAssertTrue(
            isLoginCancelled,
            "login's effect should be cancelled"
        )
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
