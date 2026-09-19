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
