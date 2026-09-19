import Interface_Macro
import Testing

@Interface private struct SendingDomain: SendingDomain.Interface {
    protocol Interface {
        var update: SendingUpdate { get }
        var delete: SendingDelete { get }
    }
}
@Interface private struct SendingUpdate: SendingUpdate.Interface {
    protocol Interface {
        func callAsFunction(_ id: Int) async throws
        var complete: SendingComplete { get }
    }
}
@Interface private struct SendingComplete: SendingComplete.Interface {
    protocol Interface { func callAsFunction(_ id: Int, _ completed: Bool) async throws }
}
@Interface private struct SendingDelete: SendingDelete.Interface {
    protocol Interface { func callAsFunction(_ id: Int) async throws }
}

@Test func childEmbeddingsArePropertiesAndPreserveTheCanonicalCall() async throws {
    var calls: [SendingDomain.Call] = []
    let sender = SendingDomain.Call.sending { calls.append($0) }
    let update = sender[keyPath: \.update]
    update.complete(1, true)
    sender.delete(2)
    #expect(calls[0] == .update.complete(1, true))
    #expect(calls[1] == .delete(2))

    var completed = false
    var deleted = false
    let owner = SendingDomain(
        update: .init({ _ in }, complete: .init { completed = $0.id == 1 && $0.completed }),
        delete: .init { deleted = $0.id == 2 }
    )
    for call in calls { try await owner(call) }
    #expect(completed && deleted)
}

@Test func primaryImplementationNeedsNoRunLabelEvenBesideOtherOperations() async throws {
    var invoked = false
    let update = SendingUpdate({ invoked = $0.id == 3 }, complete: .init { _ in })
    try await update(3)
    #expect(invoked)
}

// Generic result parameters must not shadow a domain called Root.
private enum NamedDomain {
    @Interface struct Root: Root.Interface {
        protocol Interface { func callAsFunction(_ value: Int) }
    }
}

@Test private func rootNamedDomainPreservesItsInputType() async throws {
    var value = 0
    var calls: [NamedDomain.Root.Call] = []
    NamedDomain.Root.Call.sending { calls.append($0) }(7)
    try await NamedDomain.Root({ value = $0.value })(calls[0])
    #expect(value == 7)
}
