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

public struct Value: ExtensionMacro {
    public static func expansion(
        of _: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo _: [TypeSyntax],
        in _: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        guard let structure = declaration.as(StructDeclSyntax.self) else {
            throw MacroExpansionErrorMessage(
                "@Value applies to a struct whose fields are its generic parameters."
            )
        }
        let parameters = structure.genericParameterClause?.parameters.map(\.name.text) ?? []
        let stored = structure.memberBlock.members.compactMap { member -> (name: String, type: String)? in
            guard
                let variable = member.decl.as(VariableDeclSyntax.self),
                variable.bindings.count == 1,
                let binding = variable.bindings.first,
                binding.accessorBlock == nil,
                let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text,
                let type = binding.typeAnnotation?.type.trimmedDescription
            else { return nil }
            return (name, type)
        }
        let fields = stored.map(\.name)
        let access = structure.modifiers.first { $0.name.tokenKind == .keyword(.public) || $0.name.tokenKind == .keyword(.package) }
            .map { "\($0.name.text) " } ?? ""
        func clause(_ conformance: String) -> String {
            parameters.isEmpty
                ? ""
                : " where \(parameters.map { "\($0): \(conformance)" }.joined(separator: ", "))"
        }
        let comparisons = fields.map { field in
            """
                if lhs.\(field) != rhs.\(field) {
                    return lhs.\(field) < rhs.\(field)
                }
            """
        }.joined(separator: "\n")
        let keys = fields.isEmpty ? "" : "case \(fields.joined(separator: ", "))"
        let encodes = stored.isEmpty
            ? "_ = encoder.container(keyedBy: CodingKeys.self)"
            : "var container = encoder.container(keyedBy: CodingKeys.self)\n"
                + stored.map { "try container.encode(self.\($0.name), forKey: .\($0.name))" }.joined(separator: "\n")
        let decodes = stored.isEmpty
            ? "_ = try decoder.container(keyedBy: CodingKeys.self)"
            : "let container = try decoder.container(keyedBy: CodingKeys.self)\n"
                + stored.map { "self.\($0.name) = try container.decode(\($0.type).self, forKey: .\($0.name))" }.joined(separator: "\n")
        let extensions: [String] = [
            "extension \(type.trimmed): Swift.Equatable\(clause("Swift.Equatable")) {}",
            "extension \(type.trimmed): Swift.Hashable\(clause("Swift.Hashable")) {}",
            "extension \(type.trimmed): Swift.Sendable\(clause("Swift.Sendable")) {}",
            """
            extension \(type.trimmed): Swift.Encodable\(clause("Swift.Encodable")) {
                \(access)enum CodingKeys: Swift.String, Swift.CodingKey {
                    \(keys)
                }

                \(access)func encode(to encoder: any Swift.Encoder) throws {
                    \(encodes)
                }
            }
            """,
            """
            extension \(type.trimmed): Swift.Decodable\(clause("Swift.Decodable")) {
                \(access)init(from decoder: any Swift.Decoder) throws {
                    \(decodes)
                }
            }
            """,
            """
            extension \(type.trimmed): Swift.Comparable\(clause("Swift.Comparable")) {
                \(access)static func < (lhs: Self, rhs: Self) -> Swift.Bool {
            \(comparisons)
                    return false
                }
            }
            """,
        ]
        return extensions.compactMap { DeclSyntax(stringLiteral: $0).as(ExtensionDeclSyntax.self) }
    }
}

public struct Macro: PeerMacro, MemberMacro, ExtensionMacro {
    public static func expansion(
        of _: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        if declaration.is(StructDeclSyntax.self) { return [] }
        guard let declaration = declaration.as(ProtocolDeclSyntax.self) else {
            throw MacroExpansionErrorMessage(
                "@Interface applies to a protocol named `Protocol`, or to the struct that nests it."
            )
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
        guard Self.isSemantic(declaration), let owner else {
            throw MacroExpansionErrorMessage(
                "@Interface requires a semantic protocol named `Protocol` nested in its domain namespace."
            )
        }
        return Interface.Derivation.peers(of: try Self.analysis(of: declaration, owner: owner))
    }

    public static func expansion(
        of _: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        in _: some MacroExpansionContext
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
        let name = TypeSyntax(IdentifierTypeSyntax(name: owner.name.trimmed))
        return Interface.Derivation.members(of: try Self.analysis(of: semantic, owner: name))
    }

    public static func expansion(
        of _: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo _: [TypeSyntax],
        in _: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        guard let owner = declaration.as(StructDeclSyntax.self), let semantic = Self.semantic(of: owner) else {
            return []
        }
        let extended = TypeSyntax(type.trimmed)
        return Interface.Derivation.extensions(
            of: try Self.analysis(of: semantic, owner: extended),
            extending: extended
        )
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
