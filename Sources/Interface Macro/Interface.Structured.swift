/// What an interface declares, as types: its children in declaration order, each by its coordinate. A reader folds
/// over an interface it has never seen by extending these types, so the compiler checks every step of the fold.
extension Interface {
    public protocol Structured {
        /// The children in declaration order: `Cons<Structure.first, Cons<Structure.second, Empty<Self>>>`.
        associatedtype Members
    }

    /// A table's first entry, and the rest of the table.
    public enum Cons<Head, Tail> {}

    /// The end of the table of `Owner`.
    public enum Empty<Owner> {}
}
