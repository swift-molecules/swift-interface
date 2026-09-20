import Interface_Macro
import Testing

@Interface(.sendable)
private struct SendingDomain: SendingDomain.Interface {
    protocol Interface { func callAsFunction(_ value: Int) async throws -> Int }
}

@Test private func checkedSendingInterfaceRunsInAnotherTask() async throws {
    let domain = SendingDomain { $0.value + 1 }
    let task = Task.detached { try await domain(41) }
    #expect(try await task.value == 42)
    let request: SendingDomain.Request = .init(7)
    #expect(SendingDomain.Primary.input(from: .run(request))?.fieldValue == 7)
}

@Interface
private struct Factory: Factory.Interface {
    protocol Interface { func callAsFunction() -> Int }
}

@Test private func factoryTypeNameDoesNotShadowTheDomain() {
    #expect(Factory { _ in 42 }() == 42)
}

@Interface(.sendable)
private struct Producer: Producer.Interface {
    struct Token: ~Copyable, Sendable { var value: Int }
    protocol Interface { func callAsFunction() -> Token }
}

@Test private func checkedSendingDoesNotRequireCopyableResults() {
    let domain = Producer { _ in Producer.Token(value: 42) }
    let token = domain()
    #expect(token.value == 42)
}
