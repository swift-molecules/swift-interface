public import SwiftSyntax
import Coproduct_Macro_Core
import Eliminator_Macro_Core
import Fold_Macro_Core
import Prism_Macro_Core
import Product_Macro_Core
import SwiftSyntaxBuilder

extension Interface {
    public enum Derivation {
        public static func peers(of signature: Interface.Analysis) -> [DeclSyntax] {
            let access = signature.product.access
            let spelling = access.map { "\($0.name.text) " } ?? ""
            return Product.Derivation.peers(of: signature.product)
                + operations(of: signature, access: spelling)
                + call(of: signature, access: access)
        }

        private static func operations(
            of signature: Interface.Analysis,
            access: String
        ) -> [DeclSyntax] {
            guard !signature.coordinates.isEmpty else { return [] }
            let symbols = signature.coordinates.map {
                symbol($0, access: access)
            }.joined(separator: "\n\n")
            return [DeclSyntax(stringLiteral: """
                \(access)enum Operations {
                \(symbols)
                }
                """)]
        }

        private static func symbol(
            _ coordinate: Interface.Analysis.Coordinate,
            access: String
        ) -> String {
            """
                \(access)enum \(coordinate.symbol.trimmedDescription): Operation::Operation.Symbol {
                    \(access)typealias Input = \(coordinate.input.trimmedDescription)
                    \(access)typealias Output = \(coordinate.output.trimmedDescription)
                    \(access)typealias Failure = \(coordinate.failure.trimmedDescription)
                    \(access)typealias Application = Operation::Operation.Application<
                        Self
                    >
                }
                """
        }

        private static func call(
            of signature: Interface.Analysis,
            access: DeclModifierSyntax?
        ) -> [DeclSyntax] {
            let accessSpelling = access.map { "\($0.name.text) " } ?? ""
            // The coproduct is generic in its summands so that the compiler, not a
            // syntax macro, decides whether a Call is Copyable: @Structural adds
            // `Copyable` exactly when every summand is. Leaves bind the parameter to
            // the operation's Application, children to the child's Call.
            //
            // Call remains Escapable because its canonical generated prisms return
            // both Call and Application from stored escaping arrows. Swift 6.4
            // cannot express those result lifetime dependencies; the focused Optic
            // and Interface compiler fixtures lock down that boundary.
            let owner = signature.owner.trimmedDescription
            let leaves = signature.coordinates.map { coordinate in
                (
                    parameter: "\(coordinate.symbol.text)Application",
                    name: coordinate.name,
                    bound: "\(owner).Operations.\(coordinate.symbol.trimmedDescription).Application"
                )
            }
            let children = signature.children.map { child in
                let name = child.name.text
                return (
                    parameter: "\(name.prefix(1).uppercased())\(name.dropFirst())Call",
                    name: child.name,
                    bound: child.call.trimmedDescription
                )
            }
            let summands = leaves + children
            let parameters = summands.map { "\($0.parameter): ~Copyable" }
                .joined(separator: ", ")
            let arguments = summands.map(\.bound).joined(separator: ", ")
            let cases = summands.map { summand in
                EnumCaseElementSyntax(
                    name: summand.name,
                    parameterClause: EnumCaseParameterClauseSyntax(
                        parameters: EnumCaseParameterListSyntax([
                            EnumCaseParameterSyntax(
                                type: TypeSyntax(
                                    IdentifierTypeSyntax(name: .identifier(summand.parameter))
                                )
                            )
                        ])
                    )
                )
            }
            let caseDeclarations = cases.map {
                "case \($0.trimmedDescription)"
            }.joined(separator: "\n")
            let constructors = zip(signature.coordinates, leaves).map { coordinate, leaf in
                """
                    \(accessSpelling)static func \(coordinate.name.text)\(coordinate.declaration.signature.parameterClause.trimmedDescription) -> Self
                    where \(leaf.parameter) == \(leaf.bound) {
                        let application: \(leaf.bound) = .init(
                            \(coordinate.inputExpression.trimmedDescription)
                        )
                        return Self.\(coordinate.name.text)(application)
                    }
                    """
            }.joined(separator: "\n")

            let coproduct = Coproduct.Analysis(
                whole: TypeSyntax(IdentifierTypeSyntax(name: .identifier("Coproduct"))),
                access: access,
                cases: cases,
                genericParameter: nil,
                isCopyableSuppressed: true
            )
            let algebra = Prism.Derivation.expansion(coproduct)
                + Fold.Derivation.expansion(coproduct)
                + Eliminator.Derivation.expansion(coproduct)
            let members = algebra.map {
                $0.trimmedDescription
            }.joined(separator: "\n\n")
            let caseProperties = summands.map { summand in
                """
                    \(accessSpelling)var \(summand.name.text): Optic<Coproduct, Coproduct, \(summand.parameter), \(summand.parameter)>.Case {
                        .init(prism: Coproduct.prisms.\(summand.name.text), fold: Coproduct.folds.\(summand.name.text))
                    }
                    """
            }.joined(separator: "\n")
            let caseNamespace = """
                \(accessSpelling)struct Cases {
                \(caseProperties)
                }

                \(accessSpelling)static var cases: Cases {
                    Cases()
                }
                """
            return [
                DeclSyntax(stringLiteral: """
                    @Structural
                    \(accessSpelling)enum Coproduct<\(parameters)>: ~Copyable, Operation::Operation.Coproduct {
                    \(caseDeclarations)

                    \(constructors)

                    \(members)

                    \(caseNamespace)
                    }
                    """),
                DeclSyntax(stringLiteral: """
                    \(accessSpelling)typealias Call = Coproduct<\(arguments)>
                    """),
            ]
        }
    }
}
