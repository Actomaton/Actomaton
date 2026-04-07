extension AsyncSequence where Self: Sendable, Element: Sendable
{
    /// Erases the `Failure` associated type to `any Error`,
    /// returning `any AsyncSequence<Element, any Error> & Sendable`.
    func eraseToAnyError() -> any AsyncSequence<Element, any Error> & Sendable
    {
        map { $0 }
    }
}
