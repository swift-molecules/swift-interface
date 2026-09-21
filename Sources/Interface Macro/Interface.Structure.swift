public import Operation

/// What an interface is made of, readable at runtime: its operations whose sorts are values, and its children,
/// each in declaration order. A reader folds over an interface it has never seen — a questionnaire over a
/// statute, a menu over a service — by opening these existentials.
extension Interface {
    public protocol Structure {
        associatedtype Owner
        static var operations: [any Operation.Valued<Owner>.Type] { get }
        static var children: [any Interface.Member<Owner>.Type] { get }
    }

    /// An interface whose structure is derived: every `@Interface` owner.
    public protocol Structured {
        associatedtype Structure: Interface.Structure where Structure.Owner == Self
    }
}
