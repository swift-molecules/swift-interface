import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

public struct Unimplemented: MemberMacro {
    public static func expansion(of node: AttributeSyntax, providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax], in context: some MacroExpansionContext) throws -> [DeclSyntax] {
        guard declaration.is(ExtensionDeclSyntax.self),
            node.arguments?.as(LabeledExprListSyntax.self)?.first?.expression.trimmedDescription == ".finished" else {
            throw MacroExpansionErrorMessage("Apply @Unimplemented(streams: .finished) to the explicit TestDependencyKey extension.")
        }
        return ["public static var testValue: Self { Self._makeInterface(Interface_Dependencies.Unimplemented.self) }"]
    }
}
