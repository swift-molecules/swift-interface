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
func `one declaration derives leaves product and call coproduct`() async throws {
    let first = Finite.First.Application(.init(1))
    let second = Finite.Second.Application(.init(true))
    let call = Finite.Call.second(true)
    let eliminate = Finite.Call.Eliminator<String>(
        first: { "first=\($0.input.value)" },
        second: { "second=\($0.input.flag)" }
    )
    let output = try await eliminate(call)

    let _: Finite.First.Input = first.input
    let _: Finite.First.Output = "one"
    let _: Finite.First.Failure.Type = Never.self
    let _: Finite.Second.Input = second.input
    let _: Finite.Second.Output = 2
    let _: Finite.Second.Failure.Type = Finite.Failure.self
    #expect(output == "second=true")
    requireCopyable(Finite.Call.first(1))
    requireEscapable(Finite.Call.second(true))
}

@Test
private func `pure elimination can return an effectful arrow without another operation enum`() async throws {
    let call = Finite.Call.second(true)
    let eliminator = Finite.Call.Eliminator<
        () async -> Either<String, Finite.Failure>
    >(
        first: { operation in
            { Either<String, Finite.Failure>.left("first=\(operation.input.value)") }
        },
        second: { operation in
            {
                operation.input.flag
                    ? .left("second=true")
                    : .right(.refused)
            }
        }
    )
    let effect = try await eliminator(call)

    switch await effect() {
    case let .left(output): #expect(output == "second=true")
    case .right: Issue.record("Expected success")
    }
}

// Capabilities are declared using Swift protocols at the point of use.
extension Finite.First.Input: Hashable, Sendable {}
