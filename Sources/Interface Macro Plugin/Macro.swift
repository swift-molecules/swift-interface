import Interface_Macro_Core
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

public struct Macro: MemberMacro, MemberAttributeMacro, ExtensionMacro {
    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        guard let owner = declaration.as(StructDeclSyntax.self), let semantic = Self.semantic(of: owner) else { return [] }
        let signature = try Self.analysis(of: semantic, owner: TypeSyntax(type))
        var conformances: [String] = ["Interface_Macro.Constructible"]
        if signature.run != nil { conformances.append("Interface_Macro.Interface.Primary") }
        if isSendable(node) { conformances.append("Swift.Sendable") }
        guard !conformances.isEmpty else { return [] }
        return [try ExtensionDeclSyntax("extension \(type): \(raw: conformances.joined(separator: ", ")) {}")]
    }

    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo _: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let owner = declaration.as(StructDeclSyntax.self) else { return [] }
        guard Self.conformsToSemantic(owner) else {
            throw MacroExpansionErrorMessage(
                "@Interface requires `\(owner.name.text)` to declare conformance to its own `Interface`; it is the model of its signature."
            )
        }
        guard let semantic = Self.semantic(of: owner) else {
            throw MacroExpansionErrorMessage(
                "@Interface on a struct requires a nested semantic protocol named `Interface`."
            )
        }
        // Prefer the explicit semantic owner: a nested child may have the same
        // short name as its parent (for example Artikel.`1`.`1`).
        let name = owner.inheritanceClause?.inheritedTypes.lazy.compactMap { inherited -> TypeSyntax? in
            guard let member = inherited.type.as(MemberTypeSyntax.self),
                member.name.text == semantic.name.text
            else { return nil }
            return member.baseType.trimmed
        }.first ?? TypeSyntax(IdentifierTypeSyntax(name: owner.name.trimmed))
        return Interface.Derivation.members(of: try Self.analysis(of: semantic, owner: name), sendable: isSendable(node))
    }

    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingAttributesFor member: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [AttributeSyntax] {
        guard let semantic = member.as(ProtocolDeclSyntax.self), Self.isSemantic(semantic) else { return [] }
        let exists = semantic.attributes.contains {
            $0.as(AttributeSyntax.self)?.attributeName.trimmedDescription == "Operations"
        }
        return exists ? [] : [AttributeSyntax(stringLiteral: "@Operations(composed: true)")]
    }

    private static func isSendable(_ node: AttributeSyntax) -> Bool {
        node.arguments?.as(LabeledExprListSyntax.self)?.first?.expression.trimmedDescription == ".sendable"
    }

    private static func conformsToSemantic(_ owner: StructDeclSyntax) -> Bool {
        owner.inheritanceClause?.inheritedTypes.contains { inherited in
            let name = inherited.type.as(MemberTypeSyntax.self)?.name.text
                ?? inherited.type.as(IdentifierTypeSyntax.self)?.name.text
            return name.map { ["Interface", "`Interface`", "Protocol", "`Protocol`"].contains($0) } ?? false
        } ?? false
    }

    private static func semantic(of owner: StructDeclSyntax) -> ProtocolDeclSyntax? {
        owner.memberBlock.members.lazy.compactMap {
            $0.decl.as(ProtocolDeclSyntax.self)
        }.first(where: Self.isSemantic)
    }

    private static func isSemantic(_ declaration: ProtocolDeclSyntax) -> Bool {
        let spelling = declaration.name.text
        let name = spelling.first == "`" && spelling.last == "`"
            ? String(spelling.dropFirst().dropLast())
            : spelling
        return name == "Interface" || name == "Protocol"
    }

    private static func analysis(
        of declaration: ProtocolDeclSyntax,
        owner: TypeSyntax
    ) throws -> Interface.Analysis {
        let signature = Interface.Analysis(declaration: declaration, owner: owner)
        guard signature.diagnostics.isEmpty else {
            throw MacroExpansionErrorMessage(
                "@Interface cannot derive this finite signature: \(signature.diagnostics.joined(separator: "; "))."
            )
        }
        return signature
    }
}
