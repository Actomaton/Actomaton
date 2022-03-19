// Code from: https://github.com/Apodini/Apodini/blob/develop/Sources/ApodiniExtension/AsyncSequenceHelpers/AnyAsyncSequence.swift

/// A type-erased version of a `AsyncSequence` that contains values of type `Element`.
struct AnyAsyncSequence<Element>: AsyncSequence
{
    private let _makeAsyncIterator: () -> AsyncIterator

    init<S>(_ sequence: S) where S: AsyncSequence, S.Element == Element
    {
        self._makeAsyncIterator = {
            AsyncIterator(sequence.makeAsyncIterator())
        }
    }

    func makeAsyncIterator() -> AsyncIterator
    {
        _makeAsyncIterator()
    }
}

extension AnyAsyncSequence
{
    struct AsyncIterator: AsyncIteratorProtocol
    {
        private let _next: (Any) async throws -> (Any, Element?)
        private var iterator: Any

        init<I>(_ iterator: I) where I: AsyncIteratorProtocol, I.Element == Element
        {
            self.iterator = iterator
            self._next = { iterator in
                guard var iterator = iterator as? I else {
                    fatalError("Internal logic of 'AnyAsyncSequence' is broken. Incorrect typing.")
                }

                let next = try await iterator.next()
                return (iterator, next)
            }
        }

        mutating func next() async throws -> Element?
        {
            let (iterator, next) = try await _next(self.iterator)
            self.iterator = iterator
            return next
        }
    }
}

extension AsyncSequence
{
    var typeErased: AnyAsyncSequence<Element>
    {
        AnyAsyncSequence(self)
    }
}
