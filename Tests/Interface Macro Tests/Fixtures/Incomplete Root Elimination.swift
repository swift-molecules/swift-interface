import Interface_Macro

@Interface
struct Greeting: Greeting.`Protocol` {
    protocol `Protocol` {
        func greet(_ name: String) -> String
    }
}

@Interface
struct Counter: Counter.`Protocol` {
    protocol `Protocol` {
        func increment(_ value: Int) -> Int
    }
}

@Interface
struct Example: Example.`Protocol` {
    protocol `Protocol` {
        associatedtype Greeting: Proof::Greeting.`Protocol`
        associatedtype Counter: Proof::Counter.`Protocol`

        var greeting: Greeting { get }
        var counter: Counter { get }
    }
}

let incomplete = Example.Call.Eliminator<String>(
    greeting: { _ in "greeting" }
)

// Capabilities are declared using Swift protocols at the point of use.
extension Greeting.Greet.Input: Hashable, Sendable {}
extension Counter.Increment.Input: Hashable, Sendable {}
