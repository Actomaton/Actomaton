/// Actor + Automaton = Actomaton.
///
/// `Actomaton` is `MealyMachine` specialized with `Output == Effect<Action>`.
public typealias Actomaton<Action, State> = MealyMachine<Action, State, Effect<Action>>
