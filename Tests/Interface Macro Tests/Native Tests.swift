import Interface_Macro
import Testing

@Interface
private struct Local: Local.Interface {
    final class Reference { var touched = false }
    protocol Interface { func touch(_ reference: Reference) }
}

@Test private func inputsNeedNoUnrequestedCapabilities() {
    let reference = Local.Reference()
    let local = Local(touch: { $0.reference.touched = true })
    local.touch(reference)
    #expect(reference.touched)
}

@Interface
private struct Qualified: Qualified.Interface, Swift.Sendable {
    protocol Interface { func ping() -> Bool }
}

@Test private func qualifiedNativeSendableControlsClosureStorage() async {
    let value = Qualified(ping: { _ in true })
    #expect(await Task.detached { value.ping() }.value)
}
