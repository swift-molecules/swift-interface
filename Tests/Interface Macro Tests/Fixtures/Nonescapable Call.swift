import Interface_Macro

enum Scoped {
    struct ScopedToken: ~Escapable {}

    @Interface
    protocol `Protocol` {
        func inspect(_ token: consuming ScopedToken)
    }
}

func prove() {
    _ = Scoped.Call.inspect(.init())
}
