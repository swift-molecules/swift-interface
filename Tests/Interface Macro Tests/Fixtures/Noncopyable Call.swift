import Interface_Macro

enum Linear {
    struct Token: ~Copyable {}

    @Interface
    protocol `Protocol` {
        func consume(_ token: consuming Token)
    }
}

func requireCopyable<Value: Copyable>(_: Value) {}

func prove() {
    requireCopyable(Linear.Call.consume(.init()))
}
