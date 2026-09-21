import Interface_Macro
import Testing

@Interface
private struct ConstructorNames: ConstructorNames.Interface {
    protocol Interface {
        func callAsFunction(_input: Int, _application: Int) -> Int
    }
}

@Test private func typedConstructorLocalsDoNotShadowParameters() throws {
    let call = ConstructorNames.Call.run(_input: 2, _application: 3)
    let input = try #require(ConstructorNames.Run.input(from: call))
    #expect(input._input == 2)
    #expect(input._application == 3)
}
