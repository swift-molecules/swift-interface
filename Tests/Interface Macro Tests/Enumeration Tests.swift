import Finite_Macro
import Interface_Macro
import Testing

@Interface
struct FiniteAssessment: FiniteAssessment.Interface, Sendable {
    protocol Interface {
        func `het bezit rechtspersoonlijkheid`(
            `betreft het de staat`: Bool?,
            `betreft het een provincie`: Bool?,
            `betreft het een gemeente`: Bool?,
            `betreft het een waterschap`: Bool?,
            `heeft het verordenende bevoegdheid`: Bool?
        ) -> Bool?
    }
}


@Test private func generatedInputsHaveExhaustiveFiniteEnumeration() {
    typealias Input = FiniteAssessment.`het bezit rechtspersoonlijkheid`.Input
    #expect(Input.count.rawValue == 243)
    #expect(Input.allCases.allSatisfy { $0.values.count == 5 })
    #expect(Set(Input.allCases.map(\.ordinal.rawValue)).count == 243)
    #expect(Input.allCases.allSatisfy { Input($0.ordinal)?.ordinal == $0.ordinal })
}

private typealias AssessmentInput = FiniteAssessment.`het bezit rechtspersoonlijkheid`.Input

@Test(arguments: AssessmentInput.allCases)
private func finiteInputsComposeWithInterfaceAndTesting(
    input: FiniteAssessment.`het bezit rechtspersoonlijkheid`.Input
) {
    #expect(FiniteAssessment { $0.`betreft het de staat` }.`het bezit rechtspersoonlijkheid`(input)
        == input.`betreft het de staat`)
}

private enum FiniteOperations {
    @Operations(inputConformances: ["Finite::Finite.Enumerable", "CaseIterable"], inputAttributes: "@Finite")
    protocol Signature {
        func evaluate(_ flag: Bool?) -> Bool?
        func empty() -> Bool
    }
}

@Test private func zeroAndUnaryInputsUseTheSameFiniteDerivation() {
    #expect(FiniteOperations.Empty.Input.count.rawValue == 1)
    #expect(FiniteOperations.Evaluate.Input.count.rawValue == 3)
    #expect(Array(FiniteOperations.Evaluate.Input.allCases.map(\.flag)) == [nil, false, true])
}

@Interface
private struct AutomaticInputs: AutomaticInputs.Interface {
    protocol Interface {
        func mixed(_ flag: Bool, possible: Swift.Optional<Swift.Bool>) -> Bool
        func text(_ first: String, second: String) -> String
        func empty() -> Bool
        func reserved(values: String) -> String
    }
}

@Test private func automaticCapabilitiesFollowEachInputShape() {
    #expect(AutomaticInputs.Mixed.Input.count.rawValue == 6)
    #expect(AutomaticInputs.Empty.Input.count.rawValue == 1)
    #expect(Array(AutomaticInputs.Text.Input("first", second: "second").values) == ["first", "second"])
    #expect(AutomaticInputs.Reserved.Input(values: "kept").values == "kept")
}
