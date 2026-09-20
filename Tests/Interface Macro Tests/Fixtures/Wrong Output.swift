import Either
import Interface_Macro

@Interface
struct Greeting: Greeting.`Protocol` {
    struct Name: Hashable {}
    struct Message: Hashable {}
    enum Failure: Swift.Error {}

    @Operations(composed: true)
    protocol `Protocol` {
        func greet(_ name: Name) throws(Failure) -> Message
    }
}

enum Counter {
    struct Value: Hashable {}
}

let result: Either<Greeting.Greet.Failure, Greeting.Greet.Output> =
    .right(Counter.Value())

// Capabilities are declared using Swift protocols at the point of use.
extension Greeting.Greet.Input: Hashable, Sendable {}
