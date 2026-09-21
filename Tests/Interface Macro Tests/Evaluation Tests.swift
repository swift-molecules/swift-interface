import CustomDump
import Interface_Macro
import Testing

@Interface private struct Assessment: Assessment.Interface {
    protocol Interface {
        func truth(_ value: Bool?) -> Bool?
        func text(_ value: String) -> String
    }
}

@Interface private struct AssessmentGroup: AssessmentGroup.Interface {
    protocol Interface { var assessment: Assessment { get } }
}

@Test private func `evaluation preserves heterogeneous answers and nested case identity`() async throws {
    let domain = Assessment(truth: { $0.value }, text: { $0.value.uppercased() })
    expectNoDifference(domain.evaluate(.truth(nil)), .truth(nil))
    expectNoDifference(domain.evaluate(.text("answer")), .text("ANSWER"))
    let group = AssessmentGroup(assessment: domain)
    let answer = try await group.evaluate(.assessment.truth(false))
    expectNoDifference(answer, .assessment(.truth(false)))
}

@Interface private struct ThrowingAssessment: ThrowingAssessment.Interface {
    enum Refusal: Error { case refused }
    protocol Interface { func callAsFunction(_ value: Bool) throws(Refusal) -> Bool }
}

@Test private func `evaluation propagates a typed failure without requiring async`() {
    let domain = ThrowingAssessment { _ throws(ThrowingAssessment.Refusal) in throw .refused }
    #expect(throws: ThrowingAssessment.Refusal.refused) { try domain.evaluate(.run(true)) }
}

@Interface private struct LinearAssessment: LinearAssessment.Interface {
    struct Permit: ~Copyable { let value: Int }
    protocol Interface {
        func token(_ value: Int) -> Permit
        func number(_ value: Int) -> Int
    }
}

@Test private func `evaluation retains noncopyable results`() {
    let domain = LinearAssessment(token: { .init(value: $0.value) }, number: { $0.value })
    let answer = domain.evaluate(.token(42))
    switch consume answer {
    case .token(let token): expectNoDifference(token.value, 42)
    case .number: Issue.record("Expected the token operation")
    }
}

@Interface private struct AsyncAssessment: AsyncAssessment.Interface {
    protocol Interface { func callAsFunction(_ value: Bool?) async -> Bool? }
}

@Test private func `evaluation preserves an async operation without adding throws`() async {
    let domain = AsyncAssessment { $0.value }
    let answer = await domain.evaluate(.run(nil))
    expectNoDifference(answer, nil)
}

@Interface private struct DefaultAssessment: DefaultAssessment.Interface {
    protocol Interface { func callAsFunction(_ value: Bool?) -> Bool? }
}
extension DefaultAssessment { init() { self.init { $0.value } } }

@Interface(defaults: true) private struct DefaultGroup: DefaultGroup.Interface {
    protocol Interface {
        var first: DefaultAssessment { get }
        var second: DefaultAssessment { get }
    }
}

@Test private func `default children remain independent values`() {
    var domain = DefaultGroup(second: .init { _ in false })
    let original = domain
    domain[keyPath: DefaultGroup.Structure.first.writablePath] = .init { _ in nil }
    expectNoDifference(original.first(true), true)
    expectNoDifference(domain.first(true), nil)
    expectNoDifference(domain.second(true), false)
    expectNoDifference(DefaultGroup(domain.product).second(true), false)
}
