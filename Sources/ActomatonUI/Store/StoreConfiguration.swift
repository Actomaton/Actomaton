import ActomatonDebugging

/// ``Store`` configuration for customization, e.g. `logFormat`.
public struct StoreConfiguration
{
    /// Reducer debug-logging format that also detects direct-state-binding changes.
    let logFormat: LogFormat?

    /// - Parameter logFormat:
    ///   Debug-logging format for ``Store``, including detection of direct-state-binding changes. Default value is `nil` (no logging).
    public init(logFormat: LogFormat? = nil)
    {
        self.logFormat = logFormat
    }
}
