import Interface_Macro
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
        protocol `Protocol` {
            func add(_ item: Store.Item) throws(Store.Failure) -> Int
            func remove(_ item: Store.Item, replacement: Store.Item) throws
            func count() async -> Int
        }
    }

    @Interface
    struct Root: Root.`Protocol` {
        protocol `Protocol` {
            associatedtype Items: Store.Items.`Protocol`

            var items: Items { get }
        }
    }
}

private func useGeneric<Items: Store.Items.`Protocol`>(_ items: Items) throws(Store.Failure) -> Int {
    try items.add(.init(value: "Blob"))
}

private func useGeneric<Root: Store.Root.`Protocol`>(_ root: Root) throws(Store.Failure) -> Int {
    try root.items.add(.init(value: "ab"))
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
    func `operations are reachable by property key path`() throws {
        let add = items[keyPath: \.add]

        #expect(try add(.init(value: "Blob")) == 4)
    }

    @Test
    func `each operation carries its request as data and its result by name`() throws {
        let request = Store.Items.Add.Request(.init(value: "Blob"))
        let result: Store.Items.Add.Result = try items.add(request)

        #expect(request.item == .init(value: "Blob"))
        #expect(result == 4)
        #expect(Store.Items.Remove.Request(.init(value: "a"), replacement: .init(value: "b")).replacement == .init(value: "b"))
    }

    @Test
    func `untyped throws is the any Error sort`() {
        let _: Store.Items.Operations.Remove.Failure.Type = (any Swift.Error).self
        let _: Store.Items.Operations.Count.Failure.Type = Never.self
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
}
