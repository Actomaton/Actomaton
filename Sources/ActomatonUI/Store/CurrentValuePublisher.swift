import Combine

/// Read-only `CurrentValueSubject` with sharing original value on `map`.
@propertyWrapper
public struct CurrentValuePublisher<Value>
{
    private let _value: () -> Value
    private let publisher: AnyPublisher<Value, Never>

    private init(value: @escaping () -> Value, publisher: AnyPublisher<Value, Never>)
    {
        self._value = value
        self.publisher = publisher
    }

    public init(_ currentValueSubject: CurrentValueSubject<Value, Never>)
    {
        self.init(
            value: { currentValueSubject.value },
            publisher: currentValueSubject.eraseToAnyPublisher()
        )
    }

    public var wrappedValue: Value
    {
        nonmutating get {
            self._value()
        }
    }

    public var projectedValue: AnyPublisher<Value, Never>
    {
        self.publisher
    }

    /// Functor-map with sharing original value.
    public func map<Value2>(_ f: @escaping (Value) -> Value2) -> CurrentValuePublisher<Value2>
    {
        .init(
            value: { f(self._value()) },
            publisher: self.publisher.map(f).eraseToAnyPublisher()
        )
    }
}

extension CurrentValuePublisher: Publisher
{
    public func receive<S>(subscriber: S)
        where S: Subscriber, S.Failure == Never, S.Input == Value
    {
        self.publisher.subscribe(subscriber)
    }

    public typealias Output = Value
    public typealias Failure = Never
}
