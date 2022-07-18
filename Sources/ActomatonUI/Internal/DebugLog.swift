// MARK: - DebugLog

enum Debug
{
    static func print(_ msg: Any)
    {
#if DEBUG
//        Swift.print("===>", msg)
#endif
    }
}
