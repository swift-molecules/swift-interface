import Interface_Macro
import Testing

private enum NestedOwner {
    @Interface struct Node: NestedOwner.Node.Interface {
        protocol Interface {
            var child: NestedOwner.Node.Node { get }
        }

        @Interface struct Node: NestedOwner.Node.Node.Interface {
            protocol Interface {
                func callAsFunction(_ value: Int) -> Int
            }
        }
    }
}

@Test func interfaceNestedOwnerPreservesParentWithSameNamedChild() {
    let owner = NestedOwner.Node(child: NestedOwner.Node.Node { $0.value + 1 })
    #expect(owner.child(41) == 42)
}

// Capabilities are declared using Swift protocols at the point of use.
extension NestedOwner.Node.Node.Run.Input: Hashable, Sendable {}
