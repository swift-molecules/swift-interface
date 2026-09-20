import Interface_Macro

@Interface
struct Greeting {
    @Operations(composed: true)
    protocol `Protocol` {
        func greet(_ name: String) -> String
    }
}

// Capabilities are declared using Swift protocols at the point of use.
extension Greeting.Greet.Input: Hashable, Sendable {}
