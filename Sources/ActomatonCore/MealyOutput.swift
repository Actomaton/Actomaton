/// Bare-minimum protocol that ``MealyMachine`` needs from its `Output` type so it can drive
/// the synchronous-feedback loop without knowing anything about effects.
///
/// One `Output` value may contain both synchronous feedback actions (to be fed back into the
/// reducer immediately, inside the same `send(_:)` call) and asynchronous remainders (which a
/// downstream effect manager will turn into Swift Concurrency tasks). ``MealyMachine`` uses
/// the two operations below to:
///
/// 1. Extract the synchronous feedback actions from the reducer's output, mutating the output
///    itself into the asynchronous remainder.
/// 2. Append the asynchronous remainders of every recursive reducer run into a single value.
public protocol MealyOutput<Action>: SendableMetatype
{
    associatedtype Action

    /// Splits this output into its synchronous feedback actions (to be re-fed into the reducer,
    /// in order), mutating this output into the asynchronous remainder (everything else).
    mutating func splitSynchronousActions() -> [Action]

    /// In-place semigroup append: combines `other` into this output.
    mutating func append(_ other: Self)
}
