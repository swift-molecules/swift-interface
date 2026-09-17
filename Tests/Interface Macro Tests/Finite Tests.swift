import Interface_Macro
import Testing

@Interface
struct Finite: Finite.`Protocol` {
    enum Failure: Swift.Error {
        case refused
    }

    protocol `Protocol` {
        func first(_ value: Int) -> String
        func second(_ flag: Bool) throws(Failure) -> Int
    }
}

private func requireCopyable<Value: Copyable>(_: Value) {}
private func requireEscapable<Value: Escapable>(_: Value) {}

@Test
func `one declaration derives leaves product and call coproduct`() {
    let first = Finite.Operations.First.Application(1)
    let second = Finite.Operations.Second.Application(true)
    let call = Finite.Call.second(true)
    let eliminate = Finite.Call.Eliminator<String>(
        first: { "first=\($0.input)" },
        second: { "second=\($0.input)" }
    )
    let output = eliminate(call)

    let _: Finite.Operations.First.Input = first.input
    let _: Finite.Operations.First.Output = "one"
    let _: Finite.Operations.First.Failure.Type = Never.self
    let _: Finite.Operations.Second.Input = second.input
    let _: Finite.Operations.Second.Output = 2
    let _: Finite.Operations.Second.Failure.Type = Finite.Failure.self
    #expect(output == "second=true")
    requireCopyable(Finite.Call.first(1))
    requireEscapable(Finite.Call.second(true))
}

@Test
private func `pure elimination can return an effectful arrow without another operation enum`() async {
    let call = Finite.Call.second(true)
    let eliminator = Finite.Call.Eliminator<
        () async -> Either<String, Finite.Failure>
    >(
        first: { operation in
            { Either<String, Finite.Failure>.left("first=\(operation.input)") }
        },
        second: { operation in
            {
                operation.input
                    ? .left("second=true")
                    : .right(.refused)
            }
        }
    )
    let effect = eliminator(call)

    switch await effect() {
    case let .left(output): #expect(output == "second=true")
    case .right: Issue.record("Expected success")
    }
}
