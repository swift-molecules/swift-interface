/// A named coordinate of an interface's product of child capabilities.
/// The projection returns the original child; it owns no state or operation copies.
public protocol InterfaceMember {
    associatedtype Owner
    associatedtype Value
    static var path: KeyPath<Owner, Value> { get }
}
