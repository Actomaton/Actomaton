/// State debug-logging format for `Reducer.debug` .
/// Available formats are: ``simple``, ``all(maxDepth:)``, ``diff``.
public struct StateDebugLogFormat: Equatable
{
    let format: _LogFormat

    enum _LogFormat: Equatable
    {
        case simple
        case all(maxDepth: Int = .max)
        case diff
    }
}

// MARK: - Presets

extension StateDebugLogFormat
{
    /// Simple oneline-printing mode.
    public static let simple = StateDebugLogFormat(format: .simple)

    /// Uses `CustomDump` to multiline-print all data.
    public static func all(maxDepth: Int = .max) -> StateDebugLogFormat
    {
        StateDebugLogFormat(format: .all(maxDepth: maxDepth))
    }

    /// State diff-printing.
    public static let diff = StateDebugLogFormat(format: .diff)
}
