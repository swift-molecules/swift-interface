import Interface_Macro

@Interface
struct Fixture: Fixture.`Protocol` {
    @Operations(composed: true)
    protocol `Protocol` {
        func first(_ value: Int) -> String
        func second(_ value: Bool) -> Int
    }
}

let product = Fixture(first: { String($0.value) })

// Capabilities are declared using Swift protocols at the point of use.
extension Fixture.First.Input: Hashable, Sendable {}
extension Fixture.Second.Input: Hashable, Sendable {}
