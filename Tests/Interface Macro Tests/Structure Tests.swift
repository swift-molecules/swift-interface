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
