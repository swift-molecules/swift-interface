import Interface_Syntax
import Interface_Macro_Core
import Operation_Syntax
import Product_Syntax
import SwiftParser
import SwiftSyntax
import Testing

// An interface's analysis is the operations' analysis (its symbols) plus the product's (its children).
@Test
func `an interface reads its operations as symbols and its getters as children`() throws {
    let source = Parser.parse(source: """
        @Operations(composed: true)
        protocol `Protocol` {
            associatedtype Greeting: Greeting.`Protocol`
            var greeting: Greeting { get }
            func transform(_ values: [Input]) throws(Failure) -> Result<Output, Failure>
            func combine(_ input: borrowing Input, with output: consuming Output)
        }
        """)
    let declaration = try #require(
        source.statements.first?.item.as(ProtocolDeclSyntax.self)
    )
    let signature = Interface.Analysis(
        declaration: declaration,
        owner: TypeSyntax(IdentifierTypeSyntax(name: .identifier("Domain")))
    )
    let transform = try #require(signature.symbols.first)
    let combine = try #require(signature.symbols.last)

    #expect(signature.diagnostics.isEmpty)
    #expect(signature.symbols.map(\.name) == ["Transform", "Combine"])
    #expect(signature.product.functionCoordinates.map(\.name.text) == ["transform", "combine"])
    #expect(transform.inputs.map(\.type.trimmedDescription) == ["[Domain.Input]"])
    #expect(transform.output.trimmedDescription == "Result<Domain.Output, Domain.Failure>")
    #expect(transform.failure.trimmedDescription == "Domain.Failure")
    #expect(combine.inputs.map(\.type.trimmedDescription) == ["Domain.Input", "Domain.Output"])
    #expect(combine.construction == "copy input, with: output")
    #expect(combine.transfers)
    #expect(combine.inputParameter(owner: "Domain") == "consuming Domain.Combine.Input")
    #expect(signature.children.map(\.name.text) == ["greeting"])
    #expect(signature.children.map(\.domain.trimmedDescription) == ["Greeting"])
}

@Test
func `interface analysis is independent of installed macro attributes`() throws {
    let source = Parser.parse(source: """
        protocol `Protocol` {
            func greet(_ name: String) -> String
        }
        """)
    let declaration = try #require(
        source.statements.first?.item.as(ProtocolDeclSyntax.self)
    )
    let signature = Interface.Analysis(
        declaration: declaration,
        owner: TypeSyntax(IdentifierTypeSyntax(name: .identifier("Domain")))
    )

    #expect(signature.diagnostics.isEmpty)
}
