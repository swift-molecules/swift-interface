import Interface_Macro

@Interface
struct Fixture: Fixture.`Protocol` {
    protocol `Protocol` {
        func first(_ value: Int) -> String
        func second(_ value: Bool) -> Int
    }
}

let incomplete = Fixture.Call.Eliminator<String>(
    first: { String($0.input) }
)
