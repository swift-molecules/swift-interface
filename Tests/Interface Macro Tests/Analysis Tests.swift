import Product_Macro_Core
import Interface_Macro_Core
import SwiftParser
import SwiftSyntax
import Testing

@Test
func `signature coordinates are reusable syntax backed derivation input`() throws {
    let source = Parser.parse(source: """
        protocol `Protocol` {
            func transform(_ values: [Input]) throws(Failure) -> Result<Output, Failure>
        }
        """)
    let declaration = try #require(
        source.statements.first?.item.as(ProtocolDeclSyntax.self)
    )
    let signature = Interface.Analysis(
        declaration: declaration,
        owner: TypeSyntax(IdentifierTypeSyntax(name: .identifier("Domain")))
    )
    let coordinate = try #require(signature.coordinates.first)
    let productFunction = try #require(signature.product.functionCoordinates.first)

    #expect(coordinate.declaration.name.text == "transform")
    #expect(coordinate.function.name.text == productFunction.name.text)
    #expect(coordinate.input.trimmedDescription == "[Domain.Input]")
    #expect(coordinate.inputExpression.trimmedDescription == "values")
    #expect(
        coordinate.output.trimmedDescription
            == "Result<Domain.Output, Domain.Failure>"
    )
    #expect(coordinate.failure.trimmedDescription == "Domain.Failure")
}

@Test
func `signature input type and value are rendered from one parameter analysis`() throws {
    let source = Parser.parse(source: """
        protocol `Protocol` {
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
    let coordinate = try #require(signature.coordinates.first)

    #expect(coordinate.input.trimmedDescription == "(input: Domain.Input, with: Domain.Output)")
    #expect(
        coordinate.inputExpression.trimmedDescription
            == "(input: copy input, with: output)"
    )
    #expect(coordinate.inputs.map(\.label.text) == ["input", "with"])
    #expect(coordinate.function.parameters.map(\.closureType.trimmedDescription) == [
        "borrowing Input",
        "consuming Output",
    ])
    #expect(coordinate.function.parameters.map(\.valueType.trimmedDescription) == [
        "Input",
        "Output",
    ])
}

@Test
func `signature rejects inout state transitions`() throws {
    let source = Parser.parse(source: """
        protocol `Protocol` {
            func mutate(_ value: inout Int)
        }
        """)
    let declaration = try #require(
        source.statements.first?.item.as(ProtocolDeclSyntax.self)
    )
    let signature = Interface.Analysis(
        declaration: declaration,
        owner: TypeSyntax(IdentifierTypeSyntax(name: .identifier("Domain")))
    )

    #expect(signature.diagnostics.contains { $0.contains("owned snapshot") })
}
