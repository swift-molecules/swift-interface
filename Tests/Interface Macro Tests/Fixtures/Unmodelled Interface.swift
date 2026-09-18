import Interface_Macro

@Interface
struct Greeting {
    @Operations
    protocol `Protocol` {
        func greet(_ name: String) -> String
    }
}
