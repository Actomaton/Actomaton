extension AsyncSequence where Self: SendableMetatype
{
    /// Erases the `Failure` associated type to `any Error`,
    /// returning `any AsyncSequence<Element, any Error> & SendableMetatype`.
    func eraseToAnyError() -> any AsyncSequence<Element, any Error> & SendableMetatype
    {
        map { $0 }
    }
}
