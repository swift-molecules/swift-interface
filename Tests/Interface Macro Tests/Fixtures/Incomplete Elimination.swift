import Interface_Macro

@Interface
struct Fixture: Fixture.`Protocol` {
    @Operations(composed: true)
    protocol `Protocol` {
        func first(_ value: Int) -> String
        func second(_ value: Bool) -> Int
    }
}

let incomplete = Fixture.Call.Eliminator<String>(
    first: { String($0.input.value) }
)
