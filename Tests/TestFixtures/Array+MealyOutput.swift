import ActomatonCore

/// `Array<Action>` is the simplest ``MealyOutput``: every element is itself a synchronous
/// feedback action, and the asynchronous remainder is always empty.
extension Array: MealyOutput
{
    public mutating func splitSynchronousActions() -> [Element]
    {
        let actions = self
        self.removeAll(keepingCapacity: true)
        return actions
    }

    public mutating func append(_ other: [Element])
    {
        self.append(contentsOf: other)
    }
}
