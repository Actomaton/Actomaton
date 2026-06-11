/// Effect type to run `async`, `AsyncSequence`, or cancellation.
///
/// `Effect` carries two channels:
///
/// - **`Action`**: synchronous (`.next`) and asynchronous (`.single` / `.sequence` / `.stream`)
///   feedback actions, recursively re-fed into the reducer through ``MealyMachine/send(_:)``.
/// - **`Emission`**: side-channel values yielded back to top-level `send` callers.
///   Use `Never` when no side-channel is needed.
///
/// Async-effect steps produce ``Outcome`` values that may carry an action, an emission, or both.
public struct Effect<Action, Emission>
{
    internal var kinds: [Kind]
}
