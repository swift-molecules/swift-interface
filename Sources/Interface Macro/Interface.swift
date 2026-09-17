@_exported import Operation
@_exported import Optic

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

@attached(extension, conformances: Equatable, Hashable, Comparable, Encodable, Decodable, Sendable, names: named(<), named(CodingKeys), named(encode(to:)), named(init(from:)))
public macro Value() = #externalMacro(
    module: "Interface_Macro_Plugin",
    type: "Value"
)
