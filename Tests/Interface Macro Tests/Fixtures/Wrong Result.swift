import Either
import Interface_Macro

@Interface
struct Greeting: Greeting.`Protocol` {
    struct Name: Hashable {}
    struct Message: Hashable {}

    protocol `Protocol` {
        func greet(_ name: Name) -> Message
    }
}

@Interface
struct Counter: Counter.`Protocol` {
    struct Limit: Hashable {}
    struct Value: Hashable {}
    enum Failure: Swift.Error {}

    protocol `Protocol` {
        func increment(_ limit: Limit) throws(Failure) -> Value
    }
}

func accept<Index: Operation.Symbol>(
    _: borrowing Operation.Application<Index>,
    result: borrowing Either<Index.Failure, Index.Output>
) {}

let operation = Greeting.Operations.Greet.Application(.init())
let result: Either<Counter.Operations.Increment.Failure, Counter.Operations.Increment.Output> =
    .right(.init())
accept(operation, result: result)
