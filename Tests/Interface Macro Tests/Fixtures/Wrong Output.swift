import Either
import Interface_Macro

@Interface
struct Greeting: Greeting.`Protocol` {
    struct Name: Hashable {}
    struct Message: Hashable {}
    enum Failure: Swift.Error {}

    @Operations
    protocol `Protocol` {
        func greet(_ name: Name) throws(Failure) -> Message
    }
}

enum Counter {
    struct Value: Hashable {}
}

let result: Either<Greeting.Greet.Failure, Greeting.Greet.Output> =
    .right(Counter.Value())
