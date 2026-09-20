import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

// Canonical child injection and its postcomposition. The coproduct and embedding are
// sibling member declarations; these extensions each extend exactly their attached type.
struct Embeddings: ExtensionMacro {
    static func expansion(of node: AttributeSyntax, attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol, conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext) throws -> [ExtensionDeclSyntax] {
        func string(_ expression: ExprSyntax) throws -> String {
            guard let literal = expression.as(StringLiteralExprSyntax.self), literal.segments.count == 1,
                let segment = literal.segments.first?.as(StringSegmentSyntax.self) else {
                throw MacroExpansionErrorMessage("Interface child descriptors must be literal strings")
            }
            return segment.content.text
        }
        guard case let .argumentList(arguments) = node.arguments,
            let first = arguments.first, first.label?.text == "preserving",
            declaration.is(EnumDeclSyntax.self) || declaration.is(StructDeclSyntax.self) else {
            throw MacroExpansionErrorMessage("Interface child embeddings require a generated coproduct or embedding")
        }
        let preserving = try string(first.expression).split(separator: ",").map { "\($0): ~Swift::Copyable" }
        let access = declaration.modifiers.first { ["public", "package", "fileprivate"].contains($0.name.text) }.map { "\($0.name.text) " } ?? ""
        let embedding = declaration.is(StructDeclSyntax.self)
        let result = declaration.as(StructDeclSyntax.self)?.genericParameterClause?.parameters.first?.name.text ?? "Self"
        return try arguments.dropFirst().map { argument in
            guard let tuple = argument.expression.as(TupleExprSyntax.self), tuple.elements.count == 3 else {
                throw MacroExpansionErrorMessage("Interface child embeddings require (case, parameter, canonical call)")
            }
            let parts = try tuple.elements.map { try string($0.expression) }
            let name = parts[0], parameter = parts[1], call = parts[2]
            let constraints = (preserving + ["\(parameter) == \(call)"]).joined(separator: ", ")
            let body = embedding ? "embed(.\(name)($0))" : "Self.\(name)($0)"
            return try ExtensionDeclSyntax("""
                extension \(type) where \(raw: constraints) {
                    \(raw: access)\(raw: embedding ? "" : "static ")var \(raw: name): \(raw: call).Embedding<\(raw: result)> {
                        .init { \(raw: body) }
                    }
                }
                """)
        }
    }
}
