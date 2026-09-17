@_exported import Operation
@_exported import Optic

@attached(peer, names: arbitrary)
public macro Interface() = #externalMacro(
    module: "Interface_Macro_Plugin",
    type: "Macro"
)

@attached(extension, conformances: Copyable)
public macro Structural() = #externalMacro(
    module: "Interface_Macro_Plugin",
    type: "Structural"
)
