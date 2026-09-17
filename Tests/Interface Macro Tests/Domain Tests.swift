import Interface_Macro
import Testing

private enum Greeting {
    struct Name: Equatable {
        var value: String
    }

    struct Message: Equatable {
        var value: String
    }

    @Interface
    protocol `Protocol` {
        func greet(_ name: Name) async -> Message
    }
}

private enum Counter {
    struct Limit {
        var value: Int
    }

    struct Value: Equatable {
        var value: Int
    }

    enum Error: Swift.Error, Equatable {
        case exceeded
    }

    @Interface
    protocol `Protocol` {
        func increment(limit: Limit) async throws(Error) -> Value
    }
}

private enum Example {
    @Interface
    protocol `Protocol` {
        associatedtype Greeting: Interface_Macro_Tests::Greeting.`Protocol`
        associatedtype Counter: Interface_Macro_Tests::Counter.`Protocol`

        var greeting: Greeting { get }
        var counter: Counter { get }
    }
}

private enum Nested {
    struct Input {}
    struct Output {}
    enum Failure: Swift.Error {}

    @Interface
    protocol `Protocol` {
        func transform(
            _ values: [Input]
        ) throws(Failure) -> Swift.Result<Output, Failure>
    }
}

private enum Numerals {
    struct Digit: Equatable {
        var value: Int
    }

    enum Failure: Swift.Error, Equatable {
        case unreadable
    }

    @Interface
    protocol `Protocol` {
        func digit(_ digit: Digit) throws(Failure) -> Digit
    }
}

private enum Linear {
    struct Token: ~Copyable {
        let value: Int
    }

    @Interface
    protocol `Protocol` {
        func consume(_ token: consuming Token) -> Int
    }
}

private enum LinearExample {
    @Interface
    protocol `Protocol` {
        associatedtype Linear: Interface_Macro_Tests::Linear.`Protocol`

        var linear: Linear { get }
    }
}

private enum LinearPair {
    struct Token: ~Copyable {
        let value: Int
    }

    @Interface
    protocol `Protocol` {
        func combine(
            _ first: consuming Token,
            with second: consuming Token
        ) -> Int
    }
}

private enum Observation {
    @Interface
    protocol `Protocol` {
        func inspect(_ value: borrowing Int) -> Int
    }
}

private enum Owned {
    @Interface
    protocol `Protocol` {
        func consume(_ value: consuming Int) -> Int
    }
}

private func use<Client: Greeting.`Protocol`>(
    _ client: Client,
    name: Greeting.Name
) async -> Greeting.Message {
    await client.greet(name)
}

private func use<Client: Example.`Protocol`>(
    _ client: Client,
    name: Greeting.Name,
    limit: Counter.Limit
) async throws(Counter.Error) -> (Greeting.Message, Counter.Value) {
    let message = await client.greeting.greet(name)
    let value = try await client.counter.increment(limit: limit)
    return (message, value)
}

private func success<Index: Operation.Symbol>(
    _: borrowing Operation.Application<Index>,
    _ output: consuming Index.Output
) -> Either<Index.Failure, Index.Output> {
    .right(output)
}

private func requireEscapable<Value: ~Copyable & Escapable>(_: consuming Value) {}
private func requireCopyable<Value: Copyable>(_: Value) {}

@Suite
private struct `Domain Tests` {
    let greeting = Greeting.Product(
        greet: { .init(value: "Hello, \($0.value)!") }
    )
    let counter = Counter.Product(
        increment: { limit throws(Counter.Error) in
            guard limit.value < 10 else { throw .exceeded }
            return .init(value: limit.value + 1)
        }
    )

    @Test
    func `operation application carries its input and dependent result family`() {
        let operation = Greeting.Operations.Greet.Application(
            Greeting.Name(value: "Blob")
        )
        let result = success(
            operation,
            Greeting.Message(value: "Hello, Blob!")
        )

        #expect(operation.input == .init(value: "Blob"))
        switch result {
        case let .right(message):
            #expect(message == .init(value: "Hello, Blob!"))
        case .left:
            Issue.record("Never is uninhabited")
        }
    }

    @Test
    func `call directly stores its operation leaf and eliminates exhaustively`() {
        let call = Greeting.Call.greet(.init(value: "Blob"))
        let eliminate = Greeting.Call.Eliminator<Greeting.Name>(
            greet: { $0.input }
        )
        let name = eliminate(call)

        #expect(name == .init(value: "Blob"))
    }

    @Test
    func `call receives canonical coproduct prisms`() {
        let call = Greeting.Call.greet(.init(value: "Blob"))

        switch Greeting.Call.prisms.greet.match(call) {
        case let .right(application):
            let name: Greeting.Name = application.input
            #expect(name == Greeting.Name(value: "Blob"))
        case .left:
            Issue.record("Expected the greet prism to match")
        }
    }

    @Test
    func `call carries a noncopyable input through elimination and a prism`() {
        let eliminate = Linear.Call.Eliminator<Int>(
            consume: { $0.input.value }
        )
        let eliminated = Linear.Call.consume(.init(value: 41))

        #expect(eliminate(eliminated) == 41)

        let matched = Linear.Call.prisms.consume.match(
            .consume(.init(value: 42))
        )
        switch consume matched {
        case let .right(application):
            #expect(application.input.value == 42)
        case .left:
            Issue.record("Expected the consuming call prism to match")
        }
        requireEscapable(Linear.Call.consume(.init(value: 43)))
    }

    @Test
    func `composed call carries a noncopyable child call`() {
        let eliminateChild = Linear.Call.Eliminator<Int>(
            consume: { $0.input.value }
        )
        let eliminateRoot = LinearExample.Call.Eliminator<Int>(
            linear: { eliminateChild($0) }
        )
        let call = LinearExample.Call.linear(
            .consume(.init(value: 44))
        )

        #expect(eliminateRoot(call) == 44)

        let matched = LinearExample.Call.prisms.linear.match(
            .linear(.consume(.init(value: 45)))
        )
        switch consume matched {
        case let .right(child):
            #expect(eliminateChild(child) == 45)
        case .left:
            Issue.record("Expected the composed call prism to match")
        }
        requireEscapable(
            LinearExample.Call.linear(.consume(.init(value: 46)))
        )
    }

    @Test
    func `derived folds lend a payload without consuming the call`() {
        let greeting = Greeting.Call.greet(.init(value: "Blob"))
        var name: Greeting.Name? = nil
        let visited = Greeting.Call.folds.greet(greeting) { name = $0.input }
        #expect(visited)
        #expect(name == .init(value: "Blob"))

        let linear = Linear.Call.consume(.init(value: 41))
        var total = 0
        let first = Linear.Call.folds.consume(linear) { total += $0.input.value }
        let second = Linear.Call.folds.consume(linear) { total += $0.input.value }
        #expect(first)
        #expect(second)
        #expect(total == 82)

        let composed = LinearExample.Call.linear(.consume(.init(value: 2)))
        var seen = 0
        let composedVisited = LinearExample.Call.folds.linear(composed) { child in
            _ = Linear.Call.folds.consume(child) { seen = $0.input.value }
        }
        #expect(composedVisited)
        #expect(seen == 2)
    }

    @Test
    func `derived cases pair each prism with its fold`() {
        let call = Greeting.Call.greet(.init(value: "Blob"))
        var name: Greeting.Name? = nil
        let visited = Greeting.Call.cases.greet.visit(call) { name = $0.input }
        let embedded = Greeting.Call.cases.greet.embed(.init(.init(value: "Blob")))
        #expect(visited)
        #expect(name == .init(value: "Blob"))
        #expect(Greeting.Call.cases.greet.matches(embedded))

        let linear = LinearExample.Call.linear(.consume(.init(value: 2)))
        let composed = LinearExample.Call.cases.linear.matches(linear)
        #expect(composed)
    }

    @Test
    func `call carries a noncopyable tuple input`() {
        let eliminate = LinearPair.Call.Eliminator<Int>(
            combine: { _ in 42 }
        )
        let call = LinearPair.Call.combine(
            LinearPair.Token(value: 20),
            with: LinearPair.Token(value: 22)
        )

        #expect(eliminate(call) == 42)
    }

    @Test
    func `an owned copyable input keeps its call copyable`() {
        let call = Owned.Call.consume(7)
        let eliminate = Owned.Call.Eliminator<Int>(
            consume: { $0.input }
        )
        requireCopyable(call)

        #expect(eliminate(call) == 7)
    }

    @Test
    func `call snapshots a borrowed copyable input`() {
        let call = Observation.Call.inspect(42)
        let copy = call
        let eliminate = Observation.Call.Eliminator<Int>(
            inspect: { $0.input }
        )

        #expect(eliminate(copy) == 42)
        #expect(eliminate(call) == 42)
    }

    @Test
    func `a value type and an operation may share a name`() throws {
        let application = Numerals.Operations.Digit.Application(.init(value: 7))
        let _: Numerals.Digit = application.input
        let _: Numerals.Operations.Digit.Input.Type = Numerals.Digit.self
        let _: Numerals.Operations.Digit.Output.Type = Numerals.Digit.self
        let _: Numerals.Operations.Digit.Failure.Type = Numerals.Failure.self
        let eliminate = Numerals.Call.Eliminator<Numerals.Digit>(
            digit: { $0.input }
        )

        #expect(eliminate(.digit(.init(value: 7))) == .init(value: 7))
    }

    @Test
    func `nested domain types remain qualified throughout syntax trees`() {
        let application = Nested.Operations.Transform.Application([.init()])
        let _: Nested.Operations.Transform.Input = application.input
        let _: Nested.Operations.Transform.Output.Type = Swift.Result<
            Nested.Output,
            Nested.Failure
        >.self
        let _: Nested.Operations.Transform.Failure.Type = Nested.Failure.self
    }

    @Test
    func `generated product is the semantic client interpretation`() async {
        let message = await use(greeting, name: .init(value: "Blob"))
        let _: any Greeting.`Protocol` = greeting

        #expect(message == .init(value: "Hello, Blob!"))
    }

    @Test
    func `root signature composes child algebras and child calls`() async throws {
        let client = Example.Product(greeting: greeting, counter: counter)
        let values = try await use(
            client,
            name: .init(value: "Blob"),
            limit: .init(value: 2)
        )
        let call = Example.Call.greeting(.greet(.init(value: "Blob")))
        let eliminateGreeting = Greeting.Call.Eliminator<Greeting.Name>(
            greet: { $0.input }
        )
        let eliminate = Example.Call.Eliminator<Greeting.Name>(
            greeting: { eliminateGreeting($0) },
            counter: { _ in Greeting.Name(value: "counter") }
        )
        let name = eliminate(call)
        requireCopyable(call)

        #expect(values.0 == .init(value: "Hello, Blob!"))
        #expect(values.1 == .init(value: 3))
        #expect(name == .init(value: "Blob"))
    }

    @Test
    func `ordinary calls preserve labels and effects`() async throws {
        let client = Example.Product(greeting: greeting, counter: counter)
        let call = Counter.Call.increment(limit: Counter.Limit(value: 2))
        let eliminate = Counter.Call.Eliminator<Counter.Limit>(
            increment: { $0.input }
        )
        let limit = eliminate(call)
        let message = await client.greeting.greet(.init(value: "Blob"))
        let value = try await client.counter.increment(limit: .init(value: 2))

        #expect(limit.value == 2)
        #expect(message == .init(value: "Hello, Blob!"))
        #expect(value == .init(value: 3))
        await #expect(throws: Counter.Error.exceeded) {
            try await client.counter.increment(limit: .init(value: 10))
        }
    }
}
