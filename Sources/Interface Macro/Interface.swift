@_exported import Case_Macro
@_exported import Eliminator_Macro
@_exported import Fold_Macro
@_exported import Operation_Macro
@_exported import Optic
@_exported import Prism_Macro
@_exported import Product_Macro

// Attaches @Operations to the semantic protocol and @Product to the generated model,
// then connects their canonical output with one Call and its interpreter.
// Copyable calls expose their derived prisms through dynamic member lookup, so
// optional key paths compose case extraction with input access: `\.delete?.id`.
@attached(member, names: arbitrary)
@attached(memberAttribute)
@attached(extension, conformances: Interface.Primary, Constructible, Swift.Sendable)
public macro Interface(_ option: Interface.Option? = nil) = #externalMacro(
    module: "Interface_Macro_Plugin",
    type: "Macro"
)

/// Compiler-facing hook for canonical child injections and their postcomposition.
/// Interface supplies the descriptors; domain declarations need only @Interface.
@attached(extension, names: arbitrary)
public macro _Embeddings(preserving: String, _ children: (String, String, String)...) = #externalMacro(
    module: "Interface_Macro_Plugin", type: "Embeddings"
)

public enum Interface {
    public enum Option: Sendable { case sendable }
}
