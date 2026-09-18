import Interface_Macro

@Interface
struct Scoped: Scoped.`Protocol` {
    struct ScopedToken: ~Escapable {}

    @Operations
    protocol `Protocol` {
        func inspect(_ token: consuming ScopedToken)
    }
}

func prove() {
    _ = Scoped.Call.inspect(.init())
}
