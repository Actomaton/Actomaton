import SwiftUI
import CasePaths

extension Binding
{
    /// Transforms `<Value>` to `<SubValue>` using `get` and `set`.
    public func transform<SubValue>(
        get: @escaping (Value) -> SubValue,
        set: @escaping (Value, SubValue) -> Value
    ) -> Binding<SubValue>
    {
        Binding<SubValue>(
            get: { get(self.wrappedValue) },
            set: { self.wrappedValue = set(self.wrappedValue, $0) }
        )
    }

    /// Transforms `<Value>` to `<SubValue>` using `WritableKeyPath`.
    ///
    /// - Note:
    ///   This is almost the same as `subscript(dynamicMember:)` provided by SwiftUI,
    ///   but this implementation can avoid internal `SwiftUI.BindingOperations.ForceUnwrapping` failure crash.
    public subscript<SubValue>(_ keyPath: WritableKeyPath<Value, SubValue>)
        -> Binding<SubValue>
    {
        Binding<SubValue>(
            get: { self.wrappedValue[keyPath: keyPath] },
            set: { self.wrappedValue[keyPath: keyPath] = $0 }
        )
    }

    /// Transforms `<Value>` to `<SubValue?>` using `CasePath`.
    /// - Note: `Value` should be enum value.
    public subscript<SubValue>(casePath casePath: CasePath<Value, SubValue>)
        -> Binding<SubValue?>
    {
        Binding<SubValue?>(
            get: {
                casePath.extract(from: self.wrappedValue)
            },
            set: { value in
                if let value = value {
                    self.wrappedValue = casePath.embed(value)
                }
            }
        )
    }
}

// MARK: - Traversable

extension Binding where Value: OptionalProtocol
{
    /// Transforms `Binding<Value?>` to `Binding<Value>?`.
    public var sequence: Binding<Value.Wrapped>?
    {
        let binding: Binding<Value.Wrapped?> = self[casePath: CasePath(embed: Value.init, extract: { $0.asOptional() })]
        return Binding<Value.Wrapped>(binding)
    }
}
