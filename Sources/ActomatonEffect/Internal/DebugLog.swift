// MARK: - DebugLog

package enum Debug
{
    package static func print(_ msg: Any)
    {
#if DEBUG
//        Swift.print("===>", msg)
#endif
    }
}
