import Interface_Macro_Core
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

public struct Structural: ExtensionMacro {
    public static func expansion(
        of _: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo _: [TypeSyntax],
        in _: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        guard
            let parameters = declaration.as(EnumDeclSyntax.self)?
                .genericParameterClause?.parameters,
            !parameters.isEmpty
        else {
            throw MacroExpansionErrorMessage(
                "@Structural applies to a generic enum whose summands are its generic parameters."
            )
        }
        let requirements = parameters.map { "\($0.name.text): Copyable" }
            .joined(separator: ", ")
        let declaration: DeclSyntax = DeclSyntax(
            stringLiteral: "extension \(type.trimmed): Copyable where \(requirements) {}"
        )
        return [declaration.cast(ExtensionDeclSyntax.self)]
    }
}

public struct Macro: PeerMacro {
    public static func expansion(
        of _: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let declaration = declaration.as(ProtocolDeclSyntax.self) else {
            throw MacroExpansionErrorMessage("@Interface applies to a protocol declaration only.")
        }
        let owner = context.lexicalContext.first.flatMap { syntax -> TypeSyntax? in
            if let declaration = syntax.as(EnumDeclSyntax.self) {
                return TypeSyntax(IdentifierTypeSyntax(name: declaration.name))
            }
            if let declaration = syntax.as(StructDeclSyntax.self) {
                return TypeSyntax(IdentifierTypeSyntax(name: declaration.name))
            }
            if let declaration = syntax.as(ExtensionDeclSyntax.self) {
                return declaration.extendedType.trimmed
            }
            return nil
        }
        let spelling = declaration.name.text
        let name = spelling.first == "`" && spelling.last == "`"
            ? String(spelling.dropFirst().dropLast())
            : spelling
        guard name == "Protocol", let owner else {
            throw MacroExpansionErrorMessage(
                "@Interface requires a semantic protocol named `Protocol` nested in its domain namespace."
            )
        }
        let signature = Interface.Analysis(declaration: declaration, owner: owner)
        guard signature.diagnostics.isEmpty else {
            throw MacroExpansionErrorMessage(
                "@Interface cannot derive this finite signature: \(signature.diagnostics.joined(separator: "; "))."
            )
        }
        return Interface.Derivation.peers(of: signature)
    }
}
