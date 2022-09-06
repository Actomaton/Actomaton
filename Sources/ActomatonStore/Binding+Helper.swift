#if canImport(SwiftUI)

import SwiftUI
import CasePaths

// MARK: - Functor

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
            set: { self.transaction($1).wrappedValue = set(self.wrappedValue, $0) }
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
            set: { self.transaction($1).wrappedValue[keyPath: keyPath] = $0 }
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
            set: { value, transaction in
                if let value = value {
                    self.transaction(transaction).wrappedValue = casePath.embed(value)
                }
            }
        )
    }
}

// MARK: - Traversable

extension Binding
{
    /// Moves `SubValue?`'s optional part outside of `Binding`.
    ///
    /// - Note:
    ///   `traverse(\.self)` will be same as `Bind.init?` (failable initializer),
    ///   which turns `Binding<Value?>` into `Binding<Value>?`.
    public func traverse<SubValue>(_ keyPath: WritableKeyPath<Value, SubValue?>)
        -> Binding<SubValue>?
    {
        guard let subValue = self.wrappedValue[keyPath: keyPath] else {
            return nil
        }

        return Binding<SubValue>(
            get: { subValue },
            set: { self.transaction($1).wrappedValue[keyPath: keyPath] = $0 }
        )
    }
}

#endif
