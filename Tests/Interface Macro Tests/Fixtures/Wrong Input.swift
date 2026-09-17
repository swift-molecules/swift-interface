import Interface_Macro

enum Greeting {
    struct Name {}
    struct Message {}

    @Interface
    protocol `Protocol` {
        func greet(_ name: Name) -> Message
    }
}

enum Counter {
    struct Limit {}
}

let application: Greeting.Operations.Greet.Application = .init(Counter.Limit())
