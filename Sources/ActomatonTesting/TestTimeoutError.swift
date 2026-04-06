/// Error thrown when an async operation does not finish before the timeout expires.
public struct TestTimeoutError: Error
{
    public let duration: Duration

    public init(duration: Duration)
    {
        self.duration = duration
    }
}
