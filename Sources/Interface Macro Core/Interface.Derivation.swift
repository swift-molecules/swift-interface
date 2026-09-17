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

        public static func members(of signature: Interface.Analysis) -> [DeclSyntax] {
            let access = signature.product.access.map { "\($0.name.text) " } ?? ""
            let owner = signature.owner.trimmedDescription
            let stored = signature.coordinates.map { coordinate in
                "\(access)var \(coordinate.name.text): \(owner).\(coordinate.symbol.text)"
            } + signature.children.map { child in
                "\(access)var \(child.name.text): \(child.domain.trimmedDescription)"
            }
            let parameters = signature.coordinates.map { coordinate in
                "\(coordinate.name.text): @escaping \(coordinate.function.closureType.trimmedDescription)"
            } + signature.children.map { child in
                "\(child.name.text): \(child.domain.trimmedDescription)"
            }
            let assignments = signature.coordinates.map { coordinate in
                "self.\(coordinate.name.text) = \(owner).\(coordinate.symbol.text)(\(coordinate.name.text))"
            } + signature.children.map { child in
                "self.\(child.name.text) = \(child.name.text)"
            }
            return stored.map { DeclSyntax(stringLiteral: $0) } + [
                DeclSyntax(stringLiteral: """
                    \(access)init(\(parameters.joined(separator: ", "))) {
                    \(assignments.joined(separator: "\n"))
                    }
                    """),
            ]
        }

        public static func extensions(
            of signature: Interface.Analysis,
            extending type: TypeSyntax
        ) -> [ExtensionDeclSyntax] {
            let access = signature.product.access
            let spelling = access.map { "\($0.name.text) " } ?? ""
            let groups: [[DeclSyntax]] = [
                operations(of: signature, access: spelling),
                call(of: signature, access: access),
            ]
            + signature.coordinates.map {
                arrow($0, owner: signature.owner.trimmedDescription, access: spelling)
            }
            return groups.filter { !$0.isEmpty }.compactMap { members in
                let body = members.map(\.trimmedDescription).joined(separator: "\n\n")
                let declaration = DeclSyntax(stringLiteral: """
                    extension \(type.trimmedDescription) {
                    \(body)
                    }
                    """)
                return declaration.as(ExtensionDeclSyntax.self)
            }
        }

        private static func arrow(
            _ coordinate: Interface.Analysis.Coordinate,
            owner: String,
            access: String
        ) -> [DeclSyntax] {
            let function = coordinate.function
            let name = function.name.text
            let closure = function.closureType.trimmedDescription
            let arguments = function.parameters.map(\.forwardingExpression.trimmedDescription)
                .joined(separator: ", ")
            let effects = function.declaration.signature.effectSpecifiers
            let prefix = (effects?.throwsClause != nil ? "try " : "")
                + (effects?.asyncSpecifier != nil ? "await " : "")
            let statement = function.returnsVoid
                ? "\(prefix)run(\(arguments))"
                : "return \(prefix)run(\(arguments))"
            let witness = function.returnsVoid
                ? "\(prefix)self.\(name).run(\(arguments))"
                : "return \(prefix)self.\(name).run(\(arguments))"
            return [
                DeclSyntax(stringLiteral: """
                    \(access)struct \(coordinate.symbol.text) {
                        \(access)let run: \(closure)

                        \(access)init(_ run: @escaping \(closure)) {
                            self.run = run
                        }

                        \(access)func callAsFunction\(function.declaration.signature.trimmedDescription) {
                            \(statement)
                        }
                    }
                    """),
                DeclSyntax(stringLiteral: """
                    \(access)func \(name)\(function.declaration.signature.trimmedDescription) {
                        \(witness)
                    }
                    """),
            ]
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
