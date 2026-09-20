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

enum Counter {
    struct Limit: Hashable {}
}

let application: Greeting.Greet.Application = .init(Counter.Limit())

// Capabilities are declared using Swift protocols at the point of use.
extension Greeting.Greet.Input: Hashable, Sendable {}
