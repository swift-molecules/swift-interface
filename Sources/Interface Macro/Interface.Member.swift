/// A named coordinate of an interface's product of child capabilities.
/// The projection returns the original child; it owns no state or operation copies.
extension Interface {
    public protocol Member<Owner> {
        associatedtype Owner
        associatedtype Value
        /// The coordinate's name as declared, without backticks.
        static var name: String { get }
        static var path: WritableKeyPath<Owner, Value> { get }
    }
}
