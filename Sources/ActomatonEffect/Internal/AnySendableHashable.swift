/// A wrapper for `AnyHashable` as well as `Sendable`.
struct AnySendableHashable: Hashable, @unchecked Sendable
{
    let value: AnyHashable

    init<Value>(_ value: Value) where Value: Hashable & Sendable
    {
        self.value = AnyHashable(value)
    }

    static func == (l: Self, r: Self) -> Bool
    {
        l.value == r.value
    }

    func hash(into hasher: inout Hasher)
    {
        value.hash(into: &hasher)
    }
}
