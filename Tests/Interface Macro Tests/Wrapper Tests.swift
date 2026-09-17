import Interface_Macro
import Testing

private enum Store {
    struct Item: Equatable {
        var value: String
    }

    enum Failure: Swift.Error, Equatable {
        case missing
    }

    @Interface
    struct Items {
        protocol `Protocol` {
            func add(_ item: Item) throws(Failure) -> Int
            func remove(_ item: Item, replacement: Item) throws
            func count() async -> Int
        }
    }

    @Interface
    struct Root {
        protocol `Protocol` {
            associatedtype Items: Store.Items.`Protocol`

            var items: Items { get }
        }
    }
}

@Suite
private struct `Wrapper Tests` {
    let items = Store.Items(
        product: .init(
            add: { item throws(Store.Failure) in
                guard !item.value.isEmpty else { throw .missing }
                return item.value.count
            },
            remove: { _, _ in },
            count: { 3 }
        )
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
    func `untyped throws is the any Error sort`() {
        let _: Store.Items.Operations.Remove.Failure.Type = (any Swift.Error).self
        let _: Store.Items.Operations.Count.Failure.Type = Never.self
    }

    @Test
    func `a root wrapper binds its children to their products and re-wraps them`() async throws {
        let root = Store.Root(product: .init(items: items.product))
        let count = await root.items.count()

        #expect(count == 3)
        #expect(try root.items.add(.init(value: "ab")) == 2)
    }
}
