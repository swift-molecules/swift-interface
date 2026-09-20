import Interface_Macro

@Interface
struct Native: Native.Interface, Sendable {
    final class Reference { var value = 0 }
    protocol Interface { func read() -> Int }
}
func invalid() {
    let reference = Native.Reference()
    _ = Native(read: { _ in reference.value })
}
