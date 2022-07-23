/// State logging format for `Reducer.log(format:)` and `Reducer.debug`.
/// Available formats are: ``simple``, ``all(maxDepth:)``, ``diff``.
public struct StateLogFormat: Hashable, Sendable
{
    let format: _LogFormat

    enum _LogFormat: Hashable, Sendable
    {
        case simple
        case all(maxDepth: Int = .max)
        case diff
    }
}

// MARK: - Presets

extension StateLogFormat
{
    /// Simple oneline-printing mode.
    public static let simple = StateLogFormat(format: .simple)

    /// Uses `CustomDump` to multiline-print all data.
    public static func all(maxDepth: Int = .max) -> StateLogFormat
    {
        StateLogFormat(format: .all(maxDepth: maxDepth))
    }

    /// State diff-printing.
    public static let diff = StateLogFormat(format: .diff)
}
