public protocol OptionalProtocol
{
    associatedtype Wrapped

    init(_ value: Wrapped?)
    func asOptional() -> Wrapped?
}

extension Optional: OptionalProtocol
{
    public init(_ value: Wrapped?)
    {
        self = value
    }

    public func asOptional() -> Wrapped?
    {
        self
    }
}
