/// Bare-minimum protocol that ``MealyMachine`` needs from its `Output` type so it can drive
/// the synchronous-feedback loop without knowing anything about effects.
///
/// One `Output` value may contain both synchronous feedback actions (to be fed back into the
/// reducer immediately, inside the same `send(_:)` call) and asynchronous remainders (which a
/// downstream effect manager will turn into Swift Concurrency tasks). ``MealyMachine`` uses
/// the three operations below to:
///
/// 1. Extract the synchronous feedback actions from the reducer's output.
/// 2. Keep the asynchronous remainder around so it can be returned to the caller.
/// 3. Merge the asynchronous remainders of every recursive reducer run into a single value.
public protocol MealyOutput<Action>: SendableMetatype
{
    associatedtype Action

    /// Splits this output into its synchronous feedback actions (to be re-fed into the reducer,
    /// in order) and the asynchronous remainder (everything else).
    func splitSynchronousActions() -> (actions: [Action], remainder: Self)

    /// Semigroup append: combines two outputs into one.
    static func + (lhs: Self, rhs: Self) -> Self
}

extension MealyOutput {
    func splitSynchronousActions() -> (actions: [Action], remainder: Self) {
        (actions: [], remainder: self) // No synchronous actions.
    }

    static func + (lhs: Self, rhs: Self) -> Self {
        // Choose first output only, discarding consecutive nested output.
        //
        // NOTE:
        // This default implementation should be harmless
        // since default `splitSynchronousActions` assumes no consecutive actions
        // to produce consecutive output.
        lhs
    }
}
