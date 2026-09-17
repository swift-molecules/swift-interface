import Interface_Macro

enum Mutation {
    @Interface
    protocol `Protocol` {
        func mutate(_ value: inout Int)
    }
}
