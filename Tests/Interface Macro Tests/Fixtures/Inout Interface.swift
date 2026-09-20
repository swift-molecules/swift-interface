import Interface_Macro

@Interface
struct Mutation: Mutation.`Protocol` {
    @Operations(composed: true)
    protocol `Protocol` {
        func mutate(_ value: inout Int)
    }
}
