import ActomatonCore

/// `Reducer` is `MealyReducer` specialized with `Output == Effect<Action>`.
public typealias Reducer<Action, State, Environment> = MealyReducer<Action, State, Environment, Effect<Action>>
