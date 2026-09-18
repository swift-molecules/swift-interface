import Interface_Macro
import Synchronization
import Testing

enum Store {
    struct Item: Hashable {
        var value: String
    }

    enum Failure: Swift.Error, Equatable {
        case missing
    }

    @Interface
    struct Items: Items.`Protocol` {
        @Operations
        protocol `Protocol` {
            func add(_ item: Store.Item) throws(Store.Failure) -> Int
            func remove(_ item: Store.Item, replacement: Store.Item) throws
            func count() async -> Int
        }
    }

    @Interface
    struct Removal: Removal.Interface {
        @Operations
        protocol Interface {
            func callAsFunction(_ item: Store.Item) throws(Store.Failure)
            func callAsFunction(today: String) -> Int
            func completed(in bucket: String) -> Int
            func completed(matching prefix: String, limit: Int?) -> Int
        }
    }

    @Interface
    struct Root: Root.`Protocol` {
        @Operations
        protocol `Protocol` {
            associatedtype Items: Store.Items.`Protocol`

            var items: Items { get }
        }
    }
}

private func requireSendable<Value: Sendable>(_: Value) {}
private func requireHashable<Value: Hashable>(_: Value) {}

private func useGeneric<Items: Store.Items.`Protocol`>(_ items: Items) throws(Store.Failure) -> Int {
    try items.add(.init(value: "Blob"))
}

private func useGeneric<Root: Store.Root.`Protocol`>(_ root: Root) throws(Store.Failure) -> Int {
    try root.items.add(.init(value: "ab"))
}

private func useGeneric<Removal: Store.Removal.Interface>(_ removal: Removal) throws(Store.Failure) -> Int {
    try removal(.init(value: "x"))
    return removal.completed(in: "abc")
}

@Suite
private struct `Wrapper Tests` {
    let items = Store.Items(
        add: { request throws(Store.Failure) in
            guard !request.item.value.isEmpty else { throw .missing }
            return request.item.value.count
        },
        remove: { _ in },
        count: { _ in 3 }
    )

    @Test
    func `a wrapper exposes each operation as a callable property`() async throws {
        let added = try items.add(.init(value: "Blob"))
        let count = await items.count()
        try items.remove(.init(value: "Blob"), replacement: .init(value: "Other"))

        #expect(added == 4)
        #expect(count == 3)
        #expect(throws: Store.Failure.missing) {
            try items.add(.init(value: ""))
        }
    }

    @Test
    func `the model is the product of the request-typed operations`() throws {
        let product = Store.Items.Product(add: { $0.item.value.count }, remove: { _ in }, count: { _ in 3 })
        let items = Store.Items(product)
        let _: any Store.Items.Model = product

        #expect(try items.add(.init(value: "Blob")) == 4)
        #expect(try product.add(Store.Items.Add.Input(.init(value: "Blob"))) == 4)
    }

    @Test
    func `each operation carries its request as data and its result by name`() throws {
        let request = Store.Items.Add.Input(.init(value: "Blob"))
        let result: Store.Items.Add.Output = try items.add(request)

        #expect(request.item == .init(value: "Blob"))
        #expect(result == 4)
        #expect(Store.Items.Remove.Input(.init(value: "a"), replacement: .init(value: "b")).replacement == .init(value: "b"))
    }

    @Test
    func `an operation's input is its request`() {
        let _: Store.Items.Add.Input.Type = Store.Items.Add.Input.self
        let _: Store.Items.Remove.Input.Type = Store.Items.Remove.Input.self
        let _: Store.Removal.Item.Input.Type = Store.Removal.Item.Input.self
        var request = Store.Items.Add.Input(.init(value: "Blob"))
        request.item.value = "Other"

        #expect(request.item == .init(value: "Other"))
        #expect(Store.Items.Call.add(.init(value: "Blob")) == .add(.init(value: "Blob")))
        #expect(Store.Items.Call.add(.init(value: "Blob")) != .add(.init(value: "Other")))
        requireSendable(Store.Items.Call.add(.init(value: "Blob")))
        requireHashable(Store.Items.Call.add(.init(value: "Blob")))
        requireSendable(Store.Root.Call.items(.count()))
        requireHashable(Store.Root.Call.items(.count()))
    }

    @Test
    func `an interface interprets its calls against the stored arrows`() async throws {
        let removed = Mutex<[Store.Item]>([])
        let items = Store.Items(
            add: { $0.item.value.count },
            remove: { request in removed.withLock { $0 += [request.item, request.replacement] } },
            count: { _ in 3 }
        )
        let root = Store.Root(items: items)

        try await items(.remove(.init(value: "a"), replacement: .init(value: "b")))
        try await root(.items(.remove(.init(value: "c"), replacement: .init(value: "d"))))
        try await items(.add(.init(value: "")))

        #expect(removed.withLock { $0 } == [.init(value: "a"), .init(value: "b"), .init(value: "c"), .init(value: "d")])
        await #expect(throws: Store.Failure.missing) {
            try await Store.Items(
                add: { _ throws(Store.Failure) in throw .missing },
                remove: { _ in },
                count: { _ in 0 }
            )(.add(.init(value: "")))
        }
    }

    @Test
    func `untyped throws is the any Error sort`() {
        let _: Store.Items.Remove.Failure.Type = (any Swift.Error).self
        let _: Store.Items.Count.Failure.Type = Never.self
    }

    @Test
    func `a root stores its children and is a model of its own signature`() async throws {
        let root = Store.Root(items: items)
        let count = await root.items.count()

        #expect(count == 3)
        #expect(try root.items.add(.init(value: "ab")) == 2)
        #expect(try useGeneric(root) == 2)
    }

    @Test
    func `the struct witnesses its protocol through its stored callables`() throws {
        #expect(try useGeneric(items) == 4)
    }

    @Test
    func `an interface may be its own primary operation and overload a base name`() throws {
        let removal = Store.Removal(
            item: { request throws(Store.Failure) in
                guard !request.item.value.isEmpty else { throw .missing }
            },
            today: { $0.today.count * 10 },
            completedIn: { $0.bucket.count },
            completedMatching: { $0.prefix.count + ($0.limit ?? 0) }
        )

        try removal(.init(value: "x"))
        #expect(throws: Store.Failure.missing) { try removal(.init(value: "")) }
        #expect(removal.completed(in: "abc") == 3)
        #expect(removal.completed(matching: "ab", limit: 5) == 7)
        #expect(removal.completed(Store.Removal.CompletedIn.Input(in: "abcd")) == 4)
        #expect(Store.Removal.Item.Input(.init(value: "x")).item == .init(value: "x"))
        #expect(removal(today: "ab") == 20)
        #expect(removal(Store.Removal.Today.Input(today: "abc")) == 30)
        #expect(try useGeneric(removal) == 3)
    }
}
