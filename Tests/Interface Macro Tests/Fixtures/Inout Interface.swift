import Interface_Macro

@Interface
struct Mutation: Mutation.`Protocol` {
    @Operations
    protocol `Protocol` {
        func mutate(_ value: inout Int)
    }
}
