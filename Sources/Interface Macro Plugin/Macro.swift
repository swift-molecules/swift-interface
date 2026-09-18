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
            let enumeration = declaration.as(EnumDeclSyntax.self),
            let parameters = enumeration.genericParameterClause?.parameters,
            !parameters.isEmpty
        else {
            throw MacroExpansionErrorMessage(
                "@Structural applies to a generic enum whose summands are its generic parameters."
            )
        }
        let access = enumeration.modifiers.first {
            $0.name.tokenKind == .keyword(.public) || $0.name.tokenKind == .keyword(.package)
        }.map { "\($0.name.text) " } ?? ""
        let cases = enumeration.memberBlock.members.flatMap { member in
            member.decl.as(EnumCaseDeclSyntax.self)?.elements.map(\.name.text) ?? []
        }
        func requirements(_ capability: String) -> String {
            parameters.map { "\($0.name.text): \(capability)" }.joined(separator: ", ")
        }
        // Each capability holds exactly when every summand has it; the compiler,
        // not this macro, decides per instantiation. Equatable and Hashable are
        // spelled out: synthesis inside a conditional extension of a ~Copyable
        // enum is typechecked but never emitted (undefined conformance descriptor).
        let equality = cases.map { name in
            "case let (.\(name)(lhs), .\(name)(rhs)): return lhs == rhs"
        } + (cases.count > 1 ? ["default: return false"] : [])
        let hashing = cases.enumerated().map { offset, name in
            "case let .\(name)(value): hasher.combine(\(offset)); hasher.combine(value)"
        }
        let declarations: [DeclSyntax] = [
            "extension \(raw: type.trimmed): Copyable where \(raw: requirements("Copyable")) {}",
            "extension \(raw: type.trimmed): Swift.Sendable where \(raw: requirements("Swift.Sendable")) {}",
            """
            extension \(raw: type.trimmed): Swift.Equatable where \(raw: requirements("Swift.Equatable")) {
                \(raw: access)static func == (lhs: Self, rhs: Self) -> Swift.Bool {
                    switch (lhs, rhs) {
                    \(raw: equality.joined(separator: "\n"))
                    }
                }
            }
            """,
            """
            extension \(raw: type.trimmed): Swift.Hashable where \(raw: requirements("Swift.Hashable")) {
                \(raw: access)func hash(into hasher: inout Swift.Hasher) {
                    switch self {
                    \(raw: hashing.joined(separator: "\n"))
                    }
                }
            }
            """,
        ]
        return declarations.map { $0.cast(ExtensionDeclSyntax.self) }
    }
}

public struct Macro: MemberMacro, ExtensionMacro {
    public static func expansion(
        of _: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo _: [TypeSyntax],
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
