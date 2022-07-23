/// Action logging format for `Reducer.log(format:)` and `Reducer.debug` .
/// Available formats are: ``simple``, ``all(maxDepth:)``.
public struct ActionLogFormat: Hashable, Sendable
{
    let format: _LogFormat

    enum _LogFormat: Hashable, Sendable
    {
        case simple
        case all(maxDepth: Int = .max)
    }
}

// MARK: - Presets

extension ActionLogFormat
{
    /// Simple oneline-printing mode.
    public static let simple = ActionLogFormat(format: .simple)

    /// Uses `CustomDump` to multiline-print all data.
    public static func all(maxDepth: Int = .max) -> ActionLogFormat
    {
        ActionLogFormat(format: .all(maxDepth: maxDepth))
    }
}
