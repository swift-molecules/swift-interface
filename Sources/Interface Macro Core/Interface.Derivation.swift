public import Operation_Macro_Core
public import Product_Macro_Core
public import SwiftSyntax
import SwiftSyntaxBuilder

// @Interface composes. The protocol's @Operations declares one symbol per operation (`Owner.Greet`, with its
// Input/Output/Failure); @Product, attached to the generated model protocol, derives the stored arrows and
// their initializer; @Structural/@Copyable, @Prisms/@Folds/@Cases and @Eliminator give the Call its
// capabilities and algebra. What is derived here is what no atom models: the model's requirements, the
// label-preserving witnesses, the Call's constructors, and the interpreter.
//
// Every derived declaration is a member, never an extension: an extension macro attached inside another macro's
// extension output is typechecked but never lowered (Swift 6.4), so the attached atoms only work among members.
//
// | derived                           | spelling                                                             |
// |-----------------------------------|----------------------------------------------------------------------|
// | model requirement / product label | the symbol's case name (`greet`, `run`, `id`, `completedIn`)         |
// | witness                           | the declaration's own signature; `callAsFunction` for a primary; and |
// |                                   | one overload per symbol taking its Input                             |
// | Call case / constructor           | the symbol's case name; the constructor takes the declaration's      |
// |                                   | parameter clause                                                     |
// | leaf Call parameter               | symbol name + `Application`; child: capitalised name + `Call`        |
extension Interface {
    public enum Derivation {
        public static func members(of signature: Interface.Analysis) -> [DeclSyntax] {
            let access = signature.product.access.map { "\($0.name.text) " } ?? ""
            let owner = signature.owner.trimmedDescription
            let model = Self.model(of: signature, owner: owner, access: access)
            return [model.declaration]
                + Self.witnesses(of: signature, model: model, owner: owner, access: access)
                + [Self.interpreter(of: signature, access: access)]
                + Self.call(of: signature, access: access)
        }

        public static func extensions(
            of signature: Interface.Analysis,
            extending type: TypeSyntax
        ) -> [ExtensionDeclSyntax] {
            []
        }

        // The model of an interface is @Product's: a protocol with one Input-typed arrow per symbol and one
        // getter per child, whose `Product` the owner stores. Its analysis is read back through Product.Analysis
        // so that the owner's forwarding initializer takes exactly the product's parameters.
        struct Model {
            let declaration: DeclSyntax
            let analysis: Product.Analysis
        }

        private static func model(
            of signature: Interface.Analysis,
            owner: String,
            access: String
        ) -> Model {
            let requirements = signature.symbols.map { symbol in
                "func \(symbol.caseName)(_ input: \(symbol.inputParameter(owner: owner)))\(symbol.effects) -> \(symbol.output.trimmedDescription)"
            } + signature.children.map { child in
                "var \(child.name.text): \(child.domain.trimmedDescription) { get }"
            }
            let source = """
                \(access)protocol Model {
                \(requirements.joined(separator: "\n"))
                }
                """
            let declaration = DeclSyntax(stringLiteral: source)
            let analysis = Product.Analysis(declaration.cast(ProtocolDeclSyntax.self))
            return Model(declaration: DeclSyntax(stringLiteral: "@Product\n\(source)"), analysis: analysis)
        }

        // The owner stores the product and witnesses its own protocol by forwarding to it, keeping the
        // declaration's labels; each operation is also callable with its Input.
        private static func witnesses(
            of signature: Interface.Analysis,
            model: Model,
            owner: String,
            access: String
        ) -> [DeclSyntax] {
            let parameters = model.analysis.functionCoordinates.map { function in
                "\(function.storage): @escaping \(function.closureType.trimmedDescription)"
            } + model.analysis.propertyCoordinates.map { property in
                "\(property.name.text): \(property.type.trimmedDescription)"
            }
            let arguments = model.analysis.functionCoordinates.map { "\($0.storage): \($0.storage)" }
                + model.analysis.propertyCoordinates.map { "\($0.name.text): \($0.name.text)" }
            let stored: [String] = [
                "\(access)let product: Product",
                """
                \(access)init(_ product: Product) {
                    self.product = product
                }
                """,
                """
                \(access)init(\(parameters.joined(separator: ", "))) {
                    self.product = Product(\(arguments.joined(separator: ", ")))
                }
                """,
            ]
            let children = signature.children.map { child in
                "\(access)var \(child.name.text): \(child.domain.trimmedDescription) { product.\(child.name.text) }"
            }
            let calls = signature.symbols.flatMap { symbol -> [String] in
                let input = symbol.inputPath(owner: owner)
                let name = symbol.isPrimary ? "callAsFunction" : symbol.signature.name.text
                let output = symbol.output.trimmedDescription
                let direct = "\(symbol.prefix)product.\(symbol.caseName)(\(input)(\(symbol.construction)))"
                let forwarding = "\(symbol.prefix)product.\(symbol.caseName)(input)"
                return [
                    """
                    \(access)func \(name)\(symbol.signature.declaration.signature.trimmedDescription) {
                        \(symbol.signature.returnsVoid ? direct : "return \(direct)")
                    }
                    """,
                    """
                    \(access)func \(name)(_ input: \(symbol.inputParameter(owner: owner)))\(symbol.effects) -> \(output) {
                        \(symbol.signature.returnsVoid ? forwarding : "return \(forwarding)")
                    }
                    """,
                ]
            }
            return (stored + children + calls).map { DeclSyntax(stringLiteral: $0) }
        }

        // Effects policy: the interpreter is always `async throws`, the widest of its arms; each symbol's typed
        // Failure is available but not narrowed here.
        private static func interpreter(
            of signature: Interface.Analysis,
            access: String
        ) -> DeclSyntax {
            let arms = signature.symbols.map { symbol -> String in
                """
                case let .\(symbol.caseName)(application):
                    _ = \(symbol.prefix)product.\(symbol.caseName)(application.consume())
                """
            } + signature.children.map { child in
                """
                case let .\(child.name.text)(call):
                    try await product.\(child.name.text)(call)
                """
            }
            return DeclSyntax(stringLiteral: """
                \(access)func callAsFunction(_ call: consuming Call) async throws {
                    switch consume call {
                \(arms.joined(separator: "\n"))
                    }
                }
                """)
        }

        // The Call is generic in its summands so that the compiler, not this macro, decides its capabilities:
        // @Structural and @Copyable (the stand-ins for a variadic `Coproduct<each Application>`) add each exactly
        // when every summand has it. Leaves bind a parameter to the symbol's Application, children to the
        // child's Call. Its algebra is attached, not derived here: @Prisms, @Folds and @Cases from swift-optic,
        // @Eliminator from swift-coproduct.
        //
        // Call remains Escapable because its canonical generated prisms return both Call and Application from
        // stored escaping arrows. Swift 6.4 cannot express those result lifetime dependencies; the focused Optic
        // and Interface compiler fixtures lock down that boundary.
        private static func call(
            of signature: Interface.Analysis,
            access: String
        ) -> [DeclSyntax] {
            let owner = signature.owner.trimmedDescription
            let leaves = signature.symbols.map { symbol in
                (
                    parameter: "\(symbol.name)Application",
                    name: TokenSyntax.identifier(symbol.caseName),
                    bound: "\(owner).\(symbol.name).Application"
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
            let parameters = summands.map { "\($0.parameter): ~Copyable" }.joined(separator: ", ")
            let arguments = summands.map(\.bound).joined(separator: ", ")
            let caseDeclarations = summands.map { "case \($0.name.text)(\($0.parameter))" }.joined(separator: "\n")
            let constructors = zip(signature.symbols, leaves).map { symbol, leaf in
                """
                \(access)static func \(symbol.caseName)\(symbol.signature.declaration.signature.parameterClause.trimmedDescription) -> Self
                where \(leaf.parameter) == \(leaf.bound) {
                    let application: \(leaf.bound) = .init(
                        \(symbol.inputPath(owner: owner))(\(symbol.construction))
                    )
                    return Self.\(symbol.caseName)(application)
                }
                """
            }.joined(separator: "\n")
            return [
                DeclSyntax(stringLiteral: """
                    @Structural
                    @Copyable
                    @Prisms
                    @Folds
                    @Cases
                    @Eliminator
                    \(access)enum Coproduct<\(parameters)>: ~Copyable, Operation::Operation.Coproduct {
                    \(caseDeclarations)

                    \(constructors)
                    }
                    """),
                DeclSyntax(stringLiteral: """
                    \(access)typealias Call = Coproduct<\(arguments)>
                    """),
            ]
        }
    }
}
