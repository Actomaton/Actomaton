import ActomatonCore

/// `Array<Action>` is the simplest ``MealyOutput``: every element is itself a synchronous
/// feedback action, the asynchronous remainder is always empty, and concatenation is the
/// stdlib `+`.
extension Array: MealyOutput
{
    public func splitSynchronousActions() -> (actions: [Element], remainder: [Element])
    {
        (actions: self, remainder: [])
    }
}
