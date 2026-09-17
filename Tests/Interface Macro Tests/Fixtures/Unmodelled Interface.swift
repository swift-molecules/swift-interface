import Interface_Macro

@Interface
struct Greeting {
    protocol `Protocol` {
        func greet(_ name: String) -> String
    }
}
