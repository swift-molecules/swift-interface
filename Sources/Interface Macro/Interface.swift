@_exported import Finite_Macro
@_exported import Representable_Macro
@_exported import Case_Macro
@_exported import Eliminator_Macro
@_exported import Fold_Macro
@_exported import Operation_Macro
@_exported import Optic
@_exported import Prism_Macro
@_exported import Product_Macro

// Composes operation derivation and @Product on the generated model,
// then connects their canonical output with one Call and its interpreter.
// Copyable calls expose their derived prisms through dynamic member lookup, so
// optional key paths compose case extraction with input access: `\.delete?.id`.
@attached(member, names: arbitrary)
@attached(extension, conformances: Interface.Primary)
/// Compose operations, their implementation product, and their call coproduct.
/// Input capabilities are explicitly forwarded to the operation derivation.
public macro Interface(inputConformances: [String] = [], inputAttributes: String...) = #externalMacro(
    module: "Interface_Macro_Plugin",
    type: "Macro"
)

/// Compiler-facing hook for canonical child injections and their postcomposition.
/// Interface supplies the descriptors; domain declarations need only @Interface.
@attached(extension, names: arbitrary)
public macro _Embeddings(preserving: String, _ children: (String, String, String)...) = #externalMacro(
    module: "Interface_Macro_Plugin", type: "Embeddings"
)

public enum Interface {}
