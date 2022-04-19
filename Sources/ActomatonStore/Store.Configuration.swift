import SwiftUI

/// ``Store`` configuration.
public struct StoreConfiguration
{
    /// A flag to run `Reducer` to update state on `@MainActor` immediately on ``Store/send(_:priority:tracksFeedbacks:)``
    /// so that SwiftUI `Transaction` (including animation) will work correctly for ``Store`` and ``Store/Proxy-swift.struct``.
    ///
    /// - Note:
    ///   If this value is `true`, **`Reducer` will run twice per `Action`**: on both `@MainActor` and `Actomaton`'s background actor.
    ///   This behavior is for updating state on main-thread to run SwiftUI `Transaction` correctly
    ///   while background-thread also takes care of `Reducer`-run including effect-handling.
    ///   However, if effects aren't correctly inside `Reducer`'s returning `Effect` scope, this twice-reducer-call may cause duplicated effect-run issue,
    ///   so make sure to write a proper, referentially-transparent `Reducer` first before setting this flag to `true`.
    let updatesStateImmediately: Bool

    public init(
        updatesStateImmediately: Bool = false
    )
    {
        self.updatesStateImmediately = updatesStateImmediately
    }
}
