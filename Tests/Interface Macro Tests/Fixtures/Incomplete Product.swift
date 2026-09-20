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
