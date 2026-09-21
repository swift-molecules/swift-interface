public import Operation

/// The distinguished operation of an interface, selected by its declaration's
/// primary call signature. This is a coordinate into the canonical operation
/// algebra, not a second operation or a UI interpretation.
extension Interface {
    public protocol Primary {
        associatedtype Primary: Operation.Composed where Primary.Owner == Self
    }
}
