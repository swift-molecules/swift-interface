@_exported import Case_Macro
@_exported import Eliminator_Macro
@_exported import Fold_Macro
@_exported import Operation_Macro
@_exported import Optic
@_exported import Prism_Macro
@_exported import Product_Macro

// Composes the symbols that @Operations declares on the nested protocol (which must carry it) into a model,
// witnesses, a Call and an interpreter.
@attached(member, names: arbitrary)
@attached(extension, names: arbitrary)
public macro Interface() = #externalMacro(
    module: "Interface_Macro_Plugin",
    type: "Macro"
)
