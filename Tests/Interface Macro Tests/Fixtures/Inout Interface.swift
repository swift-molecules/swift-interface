import Interface_Macro

@Interface
struct Mutation: Mutation.`Protocol` {
    protocol `Protocol` {
        func mutate(_ value: inout Int)
    }
}
