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

// A reader of the table folds over its types: here, the children's names, in declaration order.
private protocol Named {
    static var names: [String] { get }
}

extension Interface.Empty: Named {
    static var names: [String] { [] }
}

extension Interface.Cons: Named where Head: Interface.Member, Tail: Named {
    static var names: [String] { [Head.name] + Tail.names }
}

private func names<Owner: Interface.Structured>(_: Owner.Type) -> [String] where Owner.Members: Named {
    Owner.Members.names
}

@Test func `the table lists the children in declaration order`() {
    #expect(names(StructureOwner.self) == ["differentlyNamed"])
    #expect(names(StructureLeaf.self).isEmpty)
}
