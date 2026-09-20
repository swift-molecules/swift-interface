import Either
import Interface_Macro

@Interface
struct Greeting: Greeting.`Protocol` {
    struct Name: Hashable {}
    struct Message: Hashable {}

    @Operations(composed: true)
    protocol `Protocol` {
        func greet(_ name: Name) -> Message
    }
}

@Interface
struct Counter: Counter.`Protocol` {
    struct Limit: Hashable {}
    struct Value: Hashable {}
    enum Failure: Swift.Error {}

    @Operations(composed: true)
    protocol `Protocol` {
        func increment(_ limit: Limit) throws(Failure) -> Value
    }
}

func accept<Index: Operation.Symbol>(
    _: borrowing Operation.Application<Index>,
    result: borrowing Either<Index.Failure, Index.Output>
) {}

let operation = Greeting.Greet.Application(.init(.init()))
let result: Either<Counter.Increment.Failure, Counter.Increment.Output> =
    .right(.init())
accept(operation, result: result)

// Capabilities are declared using Swift protocols at the point of use.
extension Greeting.Greet.Input: Hashable, Sendable {}
extension Counter.Increment.Input: Hashable, Sendable {}
