import Interface_Macro

@Interface
struct Greeting {
    @Operations(composed: true)
    protocol `Protocol` {
        func greet(_ name: String) -> String
    }
}
