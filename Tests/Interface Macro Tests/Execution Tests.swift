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
    let truth = try await Answers.Truth.Application(.init(false)).run(on: domain)
    expectNoDifference(truth, domain.truth(false))
    let eliminate = Answers.Call.Eliminator<String>(
        truth: { String(describing: try await $0.run(on: domain)) },
        text: { try await $0.run(on: domain) })
    let text = try await eliminate(.text("answer"))
    expectNoDifference(text, "ANSWER")
}

@Interface private struct Resource: Resource.Interface {
    struct Permit: ~Copyable { let value: Int }
    protocol Interface { func token(_ value: Int) -> Permit }
}
@Test private func `typed execution retains noncopyable results`() async throws {
    let owner = Resource(token: { .init(value: $0.value) })
    let answer = try await Resource.Token.Application(.init(42)).run(on: owner)
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
    enum Refusal: Error { case refused }
    protocol Interface { func callAsFunction(_ value: Bool) throws(Refusal) -> Bool }
}
@Test private func `direct invocation retains typed synchronous failure`() {
    let owner = Refusing { _ throws(Refusing.Refusal) in throw .refused }
    #expect(throws: Refusing.Refusal.refused) { try owner(true) }
}

@Interface private struct Recorded: Recorded.Interface {
    protocol Interface { func append(_ value: String) async }
}
@Interface private struct Branches: Branches.Interface {
    protocol Interface { var left: Recorded { get }; var right: Recorded { get } }
}

@Test private func `nested dispatch preserves injection and executes exactly one operation`() async throws {
    actor Recorder {
        var values: [String] = []
        func append(_ value: String) { values.append(value) }
    }
    let recorder = Recorder()
    let owner = Branches(
        left: .init(append: { await recorder.append("left:" + $0.value) }),
        right: .init(append: { await recorder.append("right:" + $0.value) }))
    try await owner(.right.append("one"))
    try await owner(.left.append("two"))
    let values = await recorder.values
    expectNoDifference(values, ["right:one", "left:two"])
}

@Interface private struct Empty: Empty.Interface { protocol Interface {} }
@Test private func `empty implementation is the product unit`() {
    _ = Empty()
    _ = Empty(Empty.Product())
}
