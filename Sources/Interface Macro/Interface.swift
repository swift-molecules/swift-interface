@_exported import Case_Macro
@_exported import Eliminator_Macro
@_exported import Fold_Macro
@_exported import Operation_Macro
@_exported import Optic
@_exported import Prism_Macro
@_exported import Product_Macro

// Attaches @Operations to the semantic protocol and @Product to the generated model,
// then connects their canonical output with one Call and its interpreter.
@attached(member, names: arbitrary)
@attached(memberAttribute)
public macro Interface() = #externalMacro(
    module: "Interface_Macro_Plugin",
    type: "Macro"
)
