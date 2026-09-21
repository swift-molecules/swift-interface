import CustomDump
import Interface_Macro
import Testing

@Interface private struct Answers: Answers.Interface {
    protocol Interface {
        func truth(_ value: Bool?) -> Bool?
        func text(_ value: String) -> String
    }
}

@Test private func `typed execution and coproduct elimination agree with direct invocation`() async throws {
    let domain = Answers(truth: { $0.value }, text: { $0.value.uppercased() })
    expectNoDifference(try await Answers.Truth.Application(.init(false)).run(on: domain), domain.truth(false))
    let eliminate = Answers.Call.Eliminator<String>(
        truth: { String(describing: try await $0.run(on: domain)) },
        text: { try await $0.run(on: domain) })
    expectNoDifference(try await eliminate(.text("answer")), "ANSWER")
}

@Interface private struct Linear: Linear.Interface {
    struct Permit: ~Copyable { let value: Int }
    protocol Interface { func token(_ value: Int) -> Permit }
}
@Test private func `typed execution retains noncopyable results`() async throws {
    let owner = Linear(token: { .init(value: $0.value) })
    let answer = try await Linear.Token.Application(.init(42)).run(on: owner)
    #expect(answer.value == 42)
}

@Interface private struct Leaf: Leaf.Interface {
    protocol Interface { func callAsFunction(_ value: Bool?) -> Bool? }
}
@Interface private struct Group: Group.Interface {
    protocol Interface { var first: Leaf { get }; var second: Leaf { get } }
}
@Interface private struct Mixed: Mixed.Interface {
    protocol Interface { var first: Leaf { get }; func text(_ value: String) -> String }
}
@Test private func `coordinate replacement preserves siblings for pure and mixed products`() {
    var group = Group(first: .init { $0.value }, second: .init { _ in false })
    let original = group
    group[keyPath: Group.Structure.first.path] = .init { _ in nil }
    expectNoDifference(original.first(true), true)
    expectNoDifference(group.first(true), nil)
    expectNoDifference(Group(group.product).second(true), false)
    var mixed = Mixed(text: { $0.value }, first: .init { $0.value })
    mixed[keyPath: Mixed.Structure.first.path] = .init { _ in nil }
    expectNoDifference(mixed.first(true), nil)
    expectNoDifference(mixed.text("retained"), "retained")
}

@Interface private struct Refusing: Refusing.Interface {
    enum Failure: Error { case refused }
    protocol Interface { func callAsFunction(_ value: Bool) throws(Failure) -> Bool }
}
@Test private func `direct invocation retains typed synchronous failure`() {
    let owner = Refusing { _ throws(Refusing.Failure) in throw .refused }
    #expect(throws: Refusing.Failure.refused) { try owner(true) }
}
