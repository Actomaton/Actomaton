extension MutableCollection
{
    /// Safe get / set element for `MutableCollection`.
    ///
    /// - Note: When working with SwiftUI, safe array access is often needed to avoid `ContiguousArrayBuffer` index out of range error.
    ///   https://stackoverflow.com/questions/59295206/how-do-you-use-enumerated-with-foreach-in-swiftui/63145650
    public subscript (safe index: Index) -> Iterator.Element?
    {
        get {
            self.startIndex <= index && index < self.endIndex
                ? self[index]
                : nil
        }
        set {
            guard let newValue = newValue, self.startIndex <= index && index < self.endIndex else { return }
            self[index] = newValue
        }
    }
}
