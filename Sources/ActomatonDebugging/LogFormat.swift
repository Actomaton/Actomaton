/// Reducer logging format when calling `Reducer.log(format:)`.
public struct LogFormat: Hashable, Sendable
{
    /// Prefix name of the logging line.
    let name: String?

    /// `Action` logging format.
    let actionLogFormat: ActionLogFormat?

    /// `State` logging format.
    let stateLogFormat: StateLogFormat?

    public init(
        name: String? = nil,
        action actionLogFormat: ActionLogFormat? = .all(maxDepth: .max),
        state stateLogFormat: StateLogFormat? = .diff
    )
    {
        self.name = name
        self.actionLogFormat = actionLogFormat
        self.stateLogFormat = stateLogFormat
    }
}
