import Interface_Macro

enum Fixture {
    @Interface
    protocol `Protocol` {
        func first(_ value: Int) -> String
        func second(_ value: Bool) -> Int
    }
}

let incomplete = Fixture.Call.Eliminator<String>(
    first: { String($0.input) }
)
