import Interface_Macro

@Interface
struct Mutation: Mutation.`Protocol` {
    protocol `Protocol` {
        func mutate(_ value: inout Int)
    }
}

// Capabilities are declared using Swift protocols at the point of use.
extension Mutation.Mutate.Input: Hashable, Sendable {}
