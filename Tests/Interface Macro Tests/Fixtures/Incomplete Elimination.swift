import Interface_Macro

@Interface
struct Fixture: Fixture.`Protocol` {
    protocol `Protocol` {
        func first(_ value: Int) -> String
        func second(_ value: Bool) -> Int
    }
}

let incomplete = Fixture.Call.Eliminator<String>(
    first: { String($0.input.value) }
)

// Capabilities are declared using Swift protocols at the point of use.
extension Fixture.First.Input: Hashable, Sendable {}
extension Fixture.Second.Input: Hashable, Sendable {}
