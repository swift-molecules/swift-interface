import Either
import Interface_Macro

@Interface
struct Greeting: Greeting.`Protocol` {
    struct Name: Hashable {}
    struct Message: Hashable {}

    @Operations
    protocol `Protocol` {
        func greet(_ name: Name) -> Message
    }
}

@Interface
struct Counter: Counter.`Protocol` {
    struct Limit: Hashable {}
    struct Value: Hashable {}
    enum Failure: Swift.Error {}

    @Operations
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
