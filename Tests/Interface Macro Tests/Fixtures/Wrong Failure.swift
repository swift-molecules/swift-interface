import Either
import Interface_Macro

@Interface
struct Greeting: Greeting.`Protocol` {
    struct Name: Hashable {}
    struct Message: Hashable {}
    enum Failure: Swift.Error { case refused }

    protocol `Protocol` {
        func greet(_ name: Name) throws(Failure) -> Message
    }
}

enum Counter {
    enum Failure: Swift.Error { case refused }
}

let result: Either<Greeting.Operations.Greet.Failure, Greeting.Operations.Greet.Output> =
    .left(Counter.Failure.refused)
