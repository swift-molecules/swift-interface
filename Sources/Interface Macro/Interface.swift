@_exported import Eliminator_Macro
@_exported import Fold_Macro
@_exported import Operation
@_exported import Optic
@_exported import Prism_Macro
@_exported import Product_Macro

@attached(member, names: arbitrary)
@attached(extension, names: arbitrary)
public macro Interface() = #externalMacro(
    module: "Interface_Macro_Plugin",
    type: "Macro"
)

@attached(extension, conformances: Copyable)
public macro Structural() = #externalMacro(
    module: "Interface_Macro_Plugin",
    type: "Structural"
)
