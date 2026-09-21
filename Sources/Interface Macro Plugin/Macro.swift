import Operation_Macro_Core
import Finite_Macro_Core
import Type_Algebra_Syntax
import Interface_Macro_Core
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

public struct Macro: MemberMacro, ExtensionMacro {
    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        guard let owner = declaration.as(StructDeclSyntax.self), let semantic = Self.semantic(of: owner) else { return [] }
        let signature = try Self.analysis(of: semantic, owner: TypeSyntax(type))
        var conformances: [String] = ["Interface_Macro.Constructible", "Interface_Macro.Interface.Evaluating"]
        if signature.run != nil { conformances.append("Interface_Macro.Interface.Primary") }
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
        let analysis = try Self.analysis(of: semantic, owner: name)
        let defaults: Bool
        if case let .argumentList(arguments) = node.arguments,
            let argument = arguments.first(where: { $0.label?.text == "defaults" }) {
            guard let literal = argument.expression.as(BooleanLiteralExprSyntax.self) else {
                throw MacroExpansionErrorMessage("@Interface defaults must be a Boolean literal")
            }
            defaults = literal.literal.text == "true"
        } else { defaults = false }
        guard !defaults || (analysis.symbols.isEmpty && !analysis.children.isEmpty) else {
            throw MacroExpansionErrorMessage("@Interface(defaults: true) requires a nonempty product of children with init()")
        }
        let members = Interface.Derivation.members(of: analysis, sendable: Type.Syntax.Conformance.contains("Sendable", in: owner), defaultChildren: defaults)
        // Explicit @Operations remains an override. Otherwise the composition
        // owns the capabilities of its generated input records.
        guard !Self.hasOperations(semantic) else { return members }
        return members + Operation.Derivation.peers(of: Operation.Analysis(declaration: semantic, owner: name, isComposed: true)).map(Self.decorateInputs)
    }

    private static func hasOperations(_ declaration: ProtocolDeclSyntax) -> Bool {
        declaration.attributes.contains {
            $0.as(AttributeSyntax.self)?.attributeName.trimmedDescription == "Operations"
        }
    }

    private static func decorateInputs(_ declaration: DeclSyntax) -> DeclSyntax {
        guard var symbol = declaration.as(EnumDeclSyntax.self) else { return declaration }
        symbol.memberBlock.members = MemberBlockItemListSyntax(symbol.memberBlock.members.map(Self.decorateInput))
        return DeclSyntax(symbol)
    }

    private static func decorateInput(_ member: MemberBlockItemSyntax) -> MemberBlockItemSyntax {
        guard var input = member.decl.as(StructDeclSyntax.self), input.name.text == "Input",
            !(input.inheritanceClause?.trimmedDescription.contains("~Copyable") ?? false) else { return member }
        let fields = Type.Syntax.Properties(input).fields
        if Finite_Macro_Core.Derivation.supportsAutomaticEnumeration(of: input) {
            input.attributes.append(.attribute(AttributeSyntax(stringLiteral: "@Finite")))
            var inherited = input.inheritanceClause?.inheritedTypes.map { $0.type.trimmedDescription } ?? []
            // Only the closed Bool/Optional/empty shapes recognized by Finite are
            // opted in automatically. Unknown nominal types keep explicit capabilities.
            inherited += ["Finite::Finite.Enumerable", "Swift.CaseIterable", "Swift.Hashable", "Swift.Sendable"]
            input.inheritanceClause = InheritanceClauseSyntax(inheritedTypes: InheritedTypeListSyntax(
                inherited.enumerated().map { offset, name in
                    InheritedTypeSyntax(type: TypeSyntax(stringLiteral: name), trailingComma: offset + 1 < inherited.count ? .commaToken() : nil)
                }
            ))
        }
        if !fields.contains(where: { ["values", "Index", "index", "tabulate"].contains(String($0.name.filter { $0 != "`" })) }),
            let first = fields.first, fields.allSatisfy({ $0.type.trimmedDescription == first.type.trimmedDescription }) {
            input.attributes.append(.attribute(AttributeSyntax(stringLiteral: "@Representable")))
        }
        var result = member
        result.decl = DeclSyntax(input)
        return result
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
