import Interface_Macro
import Testing

@Interface
struct Greeting: Greeting.`Protocol` {
    struct Name: Hashable {
        var value: String
    }

    struct Message: Hashable {
        var value: String
    }

    protocol `Protocol` {
        func greet(_ name: Name) async -> Message
    }
}

@Interface
struct Counter: Counter.`Protocol` {
    struct Limit: Hashable {
        var value: Int
    }

    struct Value: Hashable {
        var value: Int
    }

    enum Error: Swift.Error, Equatable {
        case exceeded
    }

    protocol `Protocol` {
        func increment(limit: Limit) async throws(Error) -> Value
    }
}

@Interface
struct Example: Example.`Protocol` {
    protocol `Protocol` {
        associatedtype Greeting: Interface_Macro_Tests::Greeting.`Protocol`
        associatedtype Counter: Interface_Macro_Tests::Counter.`Protocol`

        var greeting: Greeting { get }
        var counter: Counter { get }
    }
}

@Interface
struct Nested: Nested.`Protocol` {
    struct Input: Hashable {}
    struct Output: Hashable {}
    enum Failure: Swift.Error {}

    protocol `Protocol` {
        func transform(
            _ values: [Input]
        ) throws(Failure) -> Swift.Result<Output, Failure>
    }
}

@Interface
struct Numerals: Numerals.`Protocol` {
    struct Numeral: Hashable {
        var value: Int
    }

    enum Failure: Swift.Error, Equatable {
        case unreadable
    }

    protocol `Protocol` {
        func digit(_ digit: Numeral) throws(Failure) -> Numeral
    }
}

@Interface
struct Linear: Linear.`Protocol` {
    struct Token: ~Copyable {
        let value: Int
    }

    protocol `Protocol` {
        func consume(_ token: consuming Token) -> Int
    }
}

@Interface
struct LinearExample: LinearExample.`Protocol` {
    protocol `Protocol` {
        associatedtype Linear: Interface_Macro_Tests::Linear.`Protocol`

        var linear: Linear { get }
    }
}

@Interface
struct LinearPair: LinearPair.`Protocol` {
    struct Token: ~Copyable {
        let value: Int
    }

    protocol `Protocol` {
        func combine(
            _ first: consuming Token,
            with second: consuming Token
        ) -> Int
    }
}

@Interface
struct Observation: Observation.`Protocol` {
    protocol `Protocol` {
        func inspect(_ value: borrowing Int) -> Int
    }
}

@Interface
struct Owned: Owned.`Protocol` {
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
struct `Domain Tests` {
    let greeting = Greeting(
        greet: { .init(value: "Hello, \($0.name.value)!") }
    )
    let counter = Counter(
        increment: { request throws(Counter.Error) in
            guard request.limit.value < 10 else { throw .exceeded }
            return .init(value: request.limit.value + 1)
        }
    )

    @Test
    func `operation application carries its input and dependent result family`() {
        let operation = Greeting.Operations.Greet.Application(
            .init(Greeting.Name(value: "Blob"))
        )
        let result = success(
            operation,
            Greeting.Message(value: "Hello, Blob!")
        )

        #expect(operation.input.name == .init(value: "Blob"))
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
            greet: { $0.input.name }
        )
        let name = eliminate(call)

        #expect(name == .init(value: "Blob"))
    }

    @Test
    func `call receives canonical coproduct prisms`() {
        let call = Greeting.Call.greet(.init(value: "Blob"))

        switch Greeting.Call.prisms.greet.match(call) {
        case let .right(application):
            let name: Greeting.Name = application.input.name
            #expect(name == Greeting.Name(value: "Blob"))
        case .left:
            Issue.record("Expected the greet prism to match")
        }
    }

    @Test
    func `call carries a noncopyable input through elimination and a prism`() {
        let eliminate = Linear.Call.Eliminator<Int>(
            consume: { $0.input.token.value }
        )
        let eliminated = Linear.Call.consume(.init(value: 41))

        #expect(eliminate(eliminated) == 41)

        let matched = Linear.Call.prisms.consume.match(
            .consume(.init(value: 42))
        )
        switch consume matched {
        case let .right(application):
            #expect(application.input.token.value == 42)
        case .left:
            Issue.record("Expected the consuming call prism to match")
        }
        requireEscapable(Linear.Call.consume(.init(value: 43)))
    }

    @Test
    func `composed call carries a noncopyable child call`() {
        let eliminateChild = Linear.Call.Eliminator<Int>(
            consume: { $0.input.token.value }
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
        let visited = Greeting.Call.folds.greet(greeting) { name = $0.input.name }
        #expect(visited)
        #expect(name == .init(value: "Blob"))

        let linear = Linear.Call.consume(.init(value: 41))
        var total = 0
        let first = Linear.Call.folds.consume(linear) { total += $0.input.token.value }
        let second = Linear.Call.folds.consume(linear) { total += $0.input.token.value }
        #expect(first)
        #expect(second)
        #expect(total == 82)

        let composed = LinearExample.Call.linear(.consume(.init(value: 2)))
        var seen = 0
        let composedVisited = LinearExample.Call.folds.linear(composed) { child in
            _ = Linear.Call.folds.consume(child) { seen = $0.input.token.value }
        }
        #expect(composedVisited)
        #expect(seen == 2)
    }

    @Test
    func `derived cases pair each prism with its fold`() {
        let call = Greeting.Call.greet(.init(value: "Blob"))
        var name: Greeting.Name? = nil
        let visited = Greeting.Call.cases.greet.visit(call) { name = $0.input.name }
        let embedded = Greeting.Call.cases.greet.embed(.init(.init(.init(value: "Blob"))))
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
    func `an owned input makes its request and call noncopyable`() {
        let call = Owned.Call.consume(7)
        let eliminate = Owned.Call.Eliminator<Int>(
            consume: { $0.input.value }
        )
        requireEscapable(Owned.Consume.Request(7))

        #expect(eliminate(call) == 7)
        requireEscapable(call)
    }

    @Test
    func `call snapshots a borrowed copyable input`() {
        let call = Observation.Call.inspect(42)
        let copy = call
        let eliminate = Observation.Call.Eliminator<Int>(
            inspect: { $0.input.value }
        )

        #expect(eliminate(copy) == 42)
        #expect(eliminate(call) == 42)
    }

    @Test
    func `a value type nested in the owner stays qualified`() throws {
        let application = Numerals.Operations.Digit.Application(.init(.init(value: 7)))
        let _: Numerals.Numeral = application.input.digit
        let _: Numerals.Operations.Digit.Input.Type = Numerals.Digit.Request.self
        let _: Numerals.Operations.Digit.Output.Type = Numerals.Numeral.self
        let _: Numerals.Operations.Digit.Failure.Type = Numerals.Failure.self
        let eliminate = Numerals.Call.Eliminator<Numerals.Numeral>(
            digit: { $0.input.digit }
        )

        #expect(eliminate(.digit(.init(value: 7))) == .init(value: 7))
    }

    @Test
    func `nested domain types remain qualified throughout syntax trees`() {
        let application = Nested.Operations.Transform.Application(.init([.init()]))
        let _: Nested.Operations.Transform.Input = application.input
        let _: Nested.Operations.Transform.Output.Type = Swift.Result<
            Nested.Output,
            Nested.Failure
        >.self
        let _: Nested.Operations.Transform.Failure.Type = Nested.Failure.self
    }

    @Test
    func `the interface struct is the semantic client interpretation`() async {
        let message = await use(greeting, name: .init(value: "Blob"))
        let _: any Greeting.`Protocol` = greeting

        #expect(message == .init(value: "Hello, Blob!"))
    }

    @Test
    func `root interface composes child algebras and child calls`() async throws {
        let client = Example(greeting: greeting, counter: counter)
        let values = try await use(
            client,
            name: .init(value: "Blob"),
            limit: .init(value: 2)
        )
        let call = Example.Call.greeting(.greet(.init(value: "Blob")))
        let eliminateGreeting = Greeting.Call.Eliminator<Greeting.Name>(
            greet: { $0.input.name }
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
        let client = Example(greeting: greeting, counter: counter)
        let call = Counter.Call.increment(limit: Counter.Limit(value: 2))
        let eliminate = Counter.Call.Eliminator<Counter.Limit>(
            increment: { $0.input.limit }
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
