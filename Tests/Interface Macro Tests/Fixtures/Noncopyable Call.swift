import Interface_Macro

@Interface
struct Linear: Linear.`Protocol` {
    struct Token: ~Copyable {}

    protocol `Protocol` {
        func consume(_ token: consuming Token)
    }
}

func requireCopyable<Value: Copyable>(_: Value) {}

func prove() {
    requireCopyable(Linear.Call.consume(.init()))
}
