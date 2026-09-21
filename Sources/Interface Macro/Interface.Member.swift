/// A named coordinate of an interface's product of child capabilities.
/// The projection returns the original child; it owns no state or operation copies.
extension Interface {
    public protocol Member {
        associatedtype Owner
        associatedtype Value
        static var path: KeyPath<Owner, Value> { get }
    }
}
