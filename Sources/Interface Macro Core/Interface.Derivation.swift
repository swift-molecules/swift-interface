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
                + Self.primary(of: signature, access: access)
                + [Self.interpreter(of: signature, access: access)]
                + Self.call(of: signature, access: access)
        }

        // Nothing is added to the owner by extension: the owner's inheritance clause names its own nested
        // protocol, and an extension macro declaring conformances there is a circular reference. Everything
        // generic about an interface goes through its symbols (`Operable`) and its Call (`Coproduct`).
        public static func extensions(
            of signature: Interface.Analysis,
            extending type: TypeSyntax
        ) -> [ExtensionDeclSyntax] {
            []
        }

        // The primary operation is the interface itself: `Reminders.Update.Input` is `Reminders.Update.Run.Input`.
        private static func primary(
            of signature: Interface.Analysis,
            access: String
        ) -> [DeclSyntax] {
            guard let run = signature.run else { return [] }
            return ["Input", "Output", "Failure", "Application"].map { sort in
                DeclSyntax(stringLiteral: "\(access)typealias \(sort) = \(run.name).\(sort)")
            }
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

        // The owner runs a Call by handing itself to the Call.
        private static func interpreter(
            of signature: Interface.Analysis,
            access: String
        ) -> DeclSyntax {
            DeclSyntax(stringLiteral: """
                \(access)func callAsFunction(_ call: consuming Call) async throws {
                    try await Call.run(self, call)
                }
                """)
        }

        // The Call is generic in its leaves so that the compiler, not this macro, decides its capabilities:
        // @Structural and @Copyable add each exactly when every leaf has it. A leaf is anything `Applying` the
        // operation's Input (its Application, in practice); a child's Call is bound concretely, so that the
        // child's builders can be static members (`.lists.delete(id)`) — a child whose inputs are not values
        // therefore cannot be composed into a Call that is one. Its algebra is attached, not derived here:
        // @Prisms, @Folds and @Cases from swift-optic, @Eliminator from swift-coproduct.
        //
        // `Embedding<Root>` names the operations again as functions building a Root from a Call: on the Call
        // itself (`.update.complete(id, done)`), or handed to a sender (`store.delete(id)` through `sending`).
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
                (symbol: symbol, parameter: "\(symbol.name)Application", bound: "\(owner).\(symbol.name).Application")
            }
            // With no leaves (a root of children only) the Call is concrete and a value outright.
            let generic = leaves.isEmpty
                ? ""
                : "<\(leaves.map { "\($0.parameter): ~Copyable" }.joined(separator: ", "))>"
            let conformances = leaves.isEmpty
                ? "Swift.Hashable, Swift.Sendable, Operation::Operation.Coproduct, Operation::Operation.Sending"
                : "~Copyable, Operation::Operation.Coproduct, Operation::Operation.Sending"
            let requirements = leaves.isEmpty
                ? ""
                : "\nwhere " + leaves.map { "\($0.parameter): Operation::Operation.Applying<\($0.symbol.inputPath(owner: owner))>" }.joined(separator: ", ")
            func applying(_ leaf: (symbol: Interface.Analysis.Symbol, parameter: String, bound: String)) -> String { "" }
            let capabilities = leaves.isEmpty ? "" : "@Structural\n@Copyable\n"
            let cases = leaves.map { "case \($0.symbol.caseName)(\($0.parameter))" }
                + signature.children.map { "case \($0.name.text)(\($0.call.trimmedDescription))" }
            let constructors = leaves.map { leaf in
                let symbol = leaf.symbol
                return """
                \(access)static func \(symbol.caseName)\(symbol.signature.declaration.signature.parameterClause.trimmedDescription) -> Self\(applying(leaf)) {
                    Self.\(symbol.caseName)(\(leaf.parameter)(\(symbol.inputPath(owner: owner))(\(symbol.construction))))
                }

                \(access)static func \(symbol.caseName)(_ input: \(symbol.inputParameter(owner: owner))) -> Self\(applying(leaf)) {
                    Self.\(symbol.caseName)(\(leaf.parameter)(input))
                }
                """
            }
            let builders = signature.children.map { child in
                """
                \(access)static var \(child.name.text): \(child.call.trimmedDescription).Embedding<Self> {
                    .init { Self.\(child.name.text)($0) }
                }
                """
            }
            // A one-operation Call reads as that operation's input: `request.id`.
            let forwarding = leaves.count == 1 && signature.children.isEmpty
                ? """
                \(access)subscript<Member>(dynamicMember keyPath: Swift.KeyPath<\(leaves[0].symbol.inputPath(owner: owner)), Member>) -> Member
                where \(leaves[0].parameter): Copyable {
                    switch self {
                    case let .\(leaves[0].symbol.caseName)(application):
                        application.consume()[keyPath: keyPath]
                    }
                }
                """
                : ""
            let arms = leaves.map { leaf -> String in
                """
                case let .\(leaf.symbol.caseName)(application):
                    _ = \(leaf.symbol.prefix)owner.product.\(leaf.symbol.caseName)(application.consume())
                """
            } + signature.children.map { child in
                """
                case let .\(child.name.text)(call):
                    try await owner.\(child.name.text)(call)
                """
            }
            // A primary is the embedding called; a named operation is a callable member (a property, so that a
            // store's dynamic member lookup reaches it: `store.create(draft)`); a child is the child's embedding.
            let embedded = leaves.flatMap { leaf -> [String] in
                let symbol = leaf.symbol
                let calls = [
                    """
                    \(access)func callAsFunction\(symbol.signature.declaration.signature.parameterClause.trimmedDescription) -> Root {
                        embed(.\(symbol.caseName)(\(symbol.inputPath(owner: owner))(\(symbol.construction))))
                    }
                    """,
                    """
                    \(access)func callAsFunction(_ input: \(symbol.inputParameter(owner: owner))) -> Root {
                        embed(.\(symbol.caseName)(input))
                    }
                    """,
                ]
                if symbol.isPrimary { return calls }
                return ["""
                    \(access)var \(symbol.caseName): \(symbol.name) { .init(embed: embed) }

                    \(access)struct \(symbol.name) {
                        \(access)let embed: (consuming Coproduct) -> Root

                    \(calls.joined(separator: "\n"))
                    }
                    """]
            } + signature.children.map { child in
                """
                \(access)var \(child.name.text): \(child.call.trimmedDescription).Embedding<Root> {
                    .init { embed(.\(child.name.text)($0)) }
                }
                """
            }
            return [
                DeclSyntax(stringLiteral: """
                    \(capabilities)@Prisms
                    @Folds
                    @Cases
                    @Eliminator
                    \(forwarding.isEmpty ? "" : "@dynamicMemberLookup")
                    \(access)enum Coproduct\(generic): \(conformances)\(requirements) {
                    \(cases.joined(separator: "\n"))

                    \(constructors.joined(separator: "\n"))

                    \(builders.joined(separator: "\n"))

                    \(forwarding)

                        \(access)struct Embedding<Root: ~Copyable> {
                            \(access)let embed: (consuming Coproduct) -> Root

                            \(access)init(_ embed: @escaping (consuming Coproduct) -> Root) {
                                self.embed = embed
                            }

                    \(embedded.joined(separator: "\n"))
                        }

                        \(access)static func sending(_ send: @escaping (consuming Self) -> Void) -> Embedding<Void> {
                            .init(send)
                        }

                        \(access)typealias Owner = \(owner)

                        // Effects policy: running a Call is always `async throws`, the widest of its arms.
                        \(access)static func run(_ owner: \(owner), _ call: consuming Self) async throws {
                            switch consume call {
                    \(arms.joined(separator: "\n"))
                            }
                        }
                    }
                    """),
                DeclSyntax(stringLiteral: leaves.isEmpty
                    ? "\(access)typealias Call = Coproduct"
                    : "\(access)typealias Call = Coproduct<\(leaves.map(\.bound).joined(separator: ", "))>"),
            ]
        }
    }
}
