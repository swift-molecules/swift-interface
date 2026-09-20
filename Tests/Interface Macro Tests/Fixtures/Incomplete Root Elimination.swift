import Interface_Macro

@Interface
struct Greeting: Greeting.`Protocol` {
    @Operations(composed: true)
    protocol `Protocol` {
        func greet(_ name: String) -> String
    }
}

@Interface
struct Counter: Counter.`Protocol` {
    @Operations(composed: true)
    protocol `Protocol` {
        func increment(_ value: Int) -> Int
    }
}

@Interface
struct Example: Example.`Protocol` {
    @Operations(composed: true)
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
