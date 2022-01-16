/// Action debug-logging format for `Reducer.debug` .
/// Available formats are: ``simple``, ``all(maxDepth:)``.
public struct ActionDebugLogFormat: Equatable
{
    let format: _LogFormat

    enum _LogFormat: Equatable
    {
        case simple
        case all(maxDepth: Int = .max)
    }
}

// MARK: - Presets

extension ActionDebugLogFormat
{
    /// Simple oneline-printing mode.
    public static let simple = ActionDebugLogFormat(format: .simple)

    /// Uses `CustomDump` to multiline-print all data.
    public static func all(maxDepth: Int = .max) -> ActionDebugLogFormat
    {
        ActionDebugLogFormat(format: .all(maxDepth: maxDepth))
    }
}
