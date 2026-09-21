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

let result: Either<Greeting.Greet.Failure, Greeting.Greet.Output> =
    .left(Counter.Failure.refused)

// Capabilities are declared using Swift protocols at the point of use.
extension Greeting.Greet.Input: Hashable, Sendable {}
