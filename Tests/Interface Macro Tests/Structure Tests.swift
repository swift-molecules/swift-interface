import Interface_Macro
import Testing

@Interface private struct StructureLeaf: StructureLeaf.Interface {
    protocol Interface { func callAsFunction(_ value: Int) -> Int }
}

@Interface private struct StructureOwner: StructureOwner.Interface {
    protocol Interface { var differentlyNamed: StructureLeaf { get } }
}

@Test func interfaceCoordinatesPreserveLabelsAndProjectTheOriginalImplementation() {
    let domain = StructureOwner(differentlyNamed: StructureLeaf { $0.value + 1 })
    let child: StructureLeaf = domain[keyPath: StructureOwner.Structure.differentlyNamed.path]
    #expect(child(41) == 42)
}

private func invokePrimary<Domain: Interface.Primary>(
    _ domain: Domain, _ input: consuming Domain.Primary.Input
) async throws -> Domain.Primary.Output {
    try await Domain.Primary.run(domain, input)
}

@Test func primaryCoordinateUsesTheOriginalOperationAndImplementation() async throws {
    let domain = StructureLeaf { $0.value + 1 }
    let value = try await invokePrimary(domain, .init(41))
    #expect(value == 42)
}

// Capabilities are declared using Swift protocols at the point of use.
extension StructureLeaf.Run.Input: Hashable, Sendable {}

@Interface private struct StructureTransfer: StructureTransfer.Interface {
    struct Token: ~Copyable { let value: Int }
    protocol Interface {
        func keep(_ token: consuming Token) -> Int
        func count() -> Int
    }
}

private func operationNames<Owner: Interface.Structured>(_: Owner.Type) -> [String] {
    Owner.Structure.operations.map { name($0) }
}

private func name<Listed: Operation.Valued>(_: Listed.Type) -> String {
    "\(Listed.Symbol.self)".split(separator: ".").last.map(String.init) ?? ""
}

private func run<Listed: Operation.Valued>(_ listed: Listed.Type, on owner: Listed.Owner) async throws -> Listed.Symbol.Output? {
    guard let input = (Listed.Symbol.Input.self as? any Operation.Nullary.Type)?.init() as? Listed.Symbol.Input else { return nil }
    return try await Listed.Symbol.run(owner, input)
}

@Test func structureListsOperationsAndChildrenInDeclarationOrder() {
    #expect(StructureOwner.Structure.operations.isEmpty)
    #expect(StructureOwner.Structure.children.map { $0.name } == ["differentlyNamed"])
    #expect(operationNames(StructureLeaf.self) == ["Run"])
    #expect(StructureLeaf.Structure.children.isEmpty)
}

@Test func structureListsOnlyOperationsWhoseSortsAreValues() async throws {
    #expect(operationNames(StructureTransfer.self) == ["Count"])
    let domain = StructureTransfer(keep: { _ in 1 }, count: { _ in 7 })
    let count = try #require(StructureTransfer.Structure.operations.first)
    let counted = try await run(count, on: domain)
    #expect(counted as? Int == 7)
}
