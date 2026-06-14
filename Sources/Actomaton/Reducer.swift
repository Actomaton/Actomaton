import ActomatonCore

/// `Reducer` is `MealyReducer` specialized with `Output == Effect<Action, Emission>`.
///
/// `Emission` denotes the side-channel value type yielded back to `send` callers via
/// ``SendResults``. Use `Never` when no side-channel is needed.
public typealias Reducer<Action, State, Environment, Emission>
    = MealyReducer<Action, State, Environment, Effect<Action, Emission>>
