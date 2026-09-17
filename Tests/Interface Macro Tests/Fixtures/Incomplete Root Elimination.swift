import Interface_Macro

enum Greeting {
    @Interface
    protocol `Protocol` {
        func greet(_ name: String) -> String
    }
}

enum Counter {
    @Interface
    protocol `Protocol` {
        func increment(_ value: Int) -> Int
    }
}

enum Example {
    @Interface
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
