import Interface_Macro

@Interface
struct Scoped: Scoped.`Protocol` {
    struct ScopedToken: ~Escapable {}

    @Operations(composed: true)
    protocol `Protocol` {
        func inspect(_ token: consuming ScopedToken)
    }
}

func prove() {
    _ = Scoped.Call.inspect(.init())
}

// Capabilities are declared using Swift protocols at the point of use.
extension Scoped.Inspect.Input: Sendable {}
