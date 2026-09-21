import Type_Algebra_Syntax
import Operation_Syntax
public import Product_Syntax
public import SwiftSyntax
import SwiftSyntaxBuilder

// @Interface composes. The protocol's @Operations declares one symbol per operation (`Owner.Greet`, with its
// Input/Output/Failure); @Product, attached to the generated model protocol, derives the stored arrows and
// their initializer; conditional conformance helper, @Prisms/@Folds/@Cases and @Eliminator give the Call its
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
        public static func members(of signature: Interface.Analysis, sendable: Bool = false) -> [DeclSyntax] {
            do { return try derive(signature, sendable: sendable) }
            catch { return [DeclSyntax(stringLiteral: "#error(\(String(reflecting: String(describing: error))))")] }
        }

        private static func derive(_ signature: Interface.Analysis, sendable: Bool) throws -> [DeclSyntax] {
            let algebra = try signature.algebra
            let implementation = try algebra.implementation
            let requests = try algebra.requestRecord(children: Type.Record(signature.children.map {
                .init($0.name.text, .atom(.init($0.call.trimmedDescription, scope: ["Swift"])))
            }))

            let access = signature.product.access.map { "\($0.name.text) " } ?? ""
            let owner = signature.owner.trimmedDescription
            let model = try Self.model(of: signature, implementation: implementation, owner: owner, access: access, sendable: sendable)
            return [model.declaration]
                + (try Self.witnesses(of: signature, model: model, owner: owner, access: access, sendable: sendable))
                + Self.primary(of: signature, access: access)
                + [Self.construction(of: signature, access: access)]
                + [Self.structure(of: signature, access: access)]
                + [Self.interpreter(of: signature, access: access)]
                + Self.call(of: signature, requests: requests, access: access)
        }


        private static func construction(of signature: Interface.Analysis, access: String) -> DeclSyntax {
            let owner = signature.owner.trimmedDescription
            var factory = "Factory"
            while owner.split(separator: ".").contains(Substring(factory)) { factory = "_" + factory }
            let arguments = signature.symbols.map { symbol in
                let label = symbol.caseName == signature.run?.caseName ? "" : "\(symbol.caseName): "
                let attempt = symbol.failure.trimmedDescription == "Swift.Never" || symbol.failure.trimmedDescription == "Never" ? "" : "try "
                let asynchronous = symbol.signature.effects?.asyncSpecifier == nil ? "" : " async"
                return "\(label){ (_: \(symbol.inputParameter(owner: owner)))\(asynchronous) throws(\(owner).\(symbol.name).Failure) -> \(owner).\(symbol.name).Output in \(attempt)\(factory).value(output: \(owner).\(symbol.name).Output.self, failure: \(owner).\(symbol.name).Failure.self, operation: Swift.String(reflecting: \(owner).\(symbol.name).self)) }"
            } + signature.children.map { child in
                "\(child.name.text): \(child.domain.trimmedDescription)._makeInterface(factory)"
            }
            return DeclSyntax(stringLiteral: """
                \(access)static func _makeInterface<\(factory): Interface_Macro.Factory>(_ factory: \(factory).Type) -> Self {
                    Self(\(arguments.joined(separator: ",\n")))
                }
                """)
        }

        // A child coordinate is a typed projection of the existing owner, not another
        // model of its operations. Interpreters can select it without parsing imported syntax.
        private static func structure(of signature: Interface.Analysis, access: String) -> DeclSyntax {
            let owner = signature.owner.trimmedDescription
            let children = signature.children.map { child in
                """
                \(access)enum \(child.name.trimmedDescription): Interface_Macro.Interface.Member {
                    \(access)typealias Owner = \(owner)
                    \(access)typealias Value = \(child.domain.trimmedDescription)
                    \(access)static var path: Swift.KeyPath<Owner, Value> { \\.\(child.name.trimmedDescription) }
                }
                """
            }.joined(separator: "\n")
            return DeclSyntax(stringLiteral: """
                \(access)enum Structure {
                \(children)
                }
                """)
        }

        // The primary operation is the interface itself: `Reminders.Update.Input` is `Reminders.Update.Run.Input`.
        private static func primary(
            of signature: Interface.Analysis,
            access: String
        ) -> [DeclSyntax] {
            guard let run = signature.run else { return [] }
            return [DeclSyntax(stringLiteral: "\(access)typealias Primary = \(run.name)"), DeclSyntax(stringLiteral: "\(access)typealias Request = \(run.name).Input")] + ["Input", "Output", "Failure", "Application"].map { sort in
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
            implementation: Type.Record,
            owner: String,
            access: String,
            sendable: Bool
        ) throws -> Model {
            let requirements = try implementation.fields.map { coordinate in
                if let symbol = signature.symbols.first(where: { $0.caseName == coordinate.name }) {
                    return "func \(coordinate.name)(_ input: \(symbol.inputParameter(owner: owner)))\(symbol.effects) -> \(symbol.output.trimmedDescription)"
                }
                guard let child = signature.children.first(where: { $0.name.text == coordinate.name }) else {
                    throw Type.Failure("missing Swift representation for interface coordinate")
                }
                return "var \(coordinate.name): \(child.domain.trimmedDescription) { get }"
            }
            let source = """
                \(access)protocol Model\(sendable ? ": Swift.Sendable" : "") {
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
            access: String,
            sendable: Bool
        ) throws -> [DeclSyntax] {
            // The primary operation has no name at its call site (`reminders.read()`), so its closure has none in
            // the owner's initializer either: `run` is storage, never spelled by the reader.
            let record = try model.analysis.storage()
            let parameters = try model.analysis.storage(
                unlabelled: Set(signature.run.map { [$0.caseName] } ?? [])).parameters
            let construction = try record.constructing("Product", from: .product(record.fields.map { .value($0.binding) }))
            let stored: [String] = [
                "\(access)let product: Product",
                """
                \(access)init(_ product: Product) {
                    self.product = product
                }
                """,
                """
                \(access)init(\(parameters)) {
                    self.product = \(construction)
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
        // The conditional conformance helper add each exactly when every leaf has it. A leaf is anything `Applying` the
        // operation's Input (its Application, in practice). Child calls remain generic too; constrained
        // child inclusion maps expose property navigation on their canonical specialization. Its algebra is attached, not derived here:
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
            requests: Type.Record,
            access: String
        ) -> [DeclSyntax] {
            let owner = signature.owner.trimmedDescription
            let leaves = signature.symbols.enumerated().map { index, symbol in
                (symbol: symbol, parameter: "OperationApplication\(index)", bound: "\(owner).\(symbol.name).Application")
            }
            let childParameters = signature.children.enumerated().map { index, child in
                (child: child, parameter: "ChildCall\(index)")
            }
            let parameters = leaves.map(\.parameter) + childParameters.map(\.parameter)
            let generic = parameters.isEmpty ? "" : "<" + parameters.map { "\($0): ~Copyable" }.joined(separator: ", ") + ">"
            let conformances = parameters.isEmpty
                ? "Swift.Hashable, Swift.Sendable, Operation::Operation.Coproduct, Operation::Operation.Sending"
                : "~Copyable, Operation::Operation.Coproduct, Operation::Operation.Sending"
            let constraints = leaves.map { "\($0.parameter): Operation::Operation.Applying<\($0.symbol.inputPath(owner: owner))>" }
                + childParameters.flatMap { ["\($0.parameter): Operation::Operation.Coproduct", "\($0.parameter).Owner == \($0.child.domain.trimmedDescription)"] }
            let requirements = constraints.isEmpty ? "" : "\nwhere " + constraints.joined(separator: ", ")
            let capabilities = parameters.isEmpty ? "" : "@_Structural\n"
            let cases = zip(requests.fields, parameters).map { "case \($0.name)(\($1))" }
            let constructors = leaves.map { leaf in
                let symbol = leaf.symbol
                let used = Set(symbol.inputs.map { $0.parameter.localName.text })
                var inputName = "_input"
                while used.contains(inputName) || used.contains("`" + inputName + "`") { inputName = "_" + inputName }
                var applicationName = "_application"
                while used.contains(applicationName) || used.contains("`" + applicationName + "`") { applicationName = "_" + applicationName }
                return """
                \(access)static func \(symbol.caseName)\(symbol.signature.declaration.signature.parameterClause.trimmedDescription) -> Self {
                    let \(inputName): \(symbol.inputPath(owner: owner)) = \(symbol.inputPath(owner: owner))(\(symbol.construction))
                    let \(applicationName): \(leaf.parameter) = \(leaf.parameter)(\(inputName))
                    return Self.\(symbol.caseName)(\(applicationName))
                }

                \(access)static func \(symbol.caseName)(_ input: \(symbol.inputParameter(owner: owner))) -> Self {
                    let application: \(leaf.parameter) = \(leaf.parameter)(input)
                    return Self.\(symbol.caseName)(application)
                }
                """
            }
            var embeddingResult = "_Result"
            while owner.split(separator: ".").contains(Substring(embeddingResult)) || parameters.contains(embeddingResult) {
                embeddingResult = "_" + embeddingResult
            }
            func childEmbeddings(embedding: Bool) -> String {
                guard !childParameters.isEmpty else { return "" }
                let preserving = (parameters + (embedding ? [embeddingResult] : [])).joined(separator: ",")
                let bindings = childParameters.map { entry in
                    "(\(String(reflecting: entry.child.name.text)), \(String(reflecting: entry.parameter)), \(String(reflecting: entry.child.call.trimmedDescription)))"
                }.joined(separator: ", ")
                return "@_Embeddings(preserving: \(String(reflecting: preserving)), \(bindings))"
            }
            let source = "Coproduct" + (parameters.isEmpty ? "" : "<" + parameters.joined(separator: ", ") + ">")
            // A one-operation Call reads as that operation's input: `request.id`.
            let forwarding = leaves.count == 1 && !leaves[0].symbol.transfers && signature.children.isEmpty
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
                \(leaf.symbol.caseName): { (application: consuming \(leaf.parameter)) async throws -> Void in
                    \(leaf.symbol.signature.returnsVoid ? "" : "_ = ")\(leaf.symbol.prefix)owner.product.\(leaf.symbol.caseName)(application.consume())
                }
                """
            } + childParameters.map { entry in
                let child = entry.child
                return """
                \(child.name.text): { (call: consuming \(entry.parameter)) async throws -> Void in
                    try await \(entry.parameter).run(owner.\(child.name.text), call)
                }
                """
            }
            // A primary is the embedding called; a named operation is a callable member (a property, so that a
            // store's dynamic member lookup reaches it: `store.create(draft)`); a child is the child's embedding.
            let embedded = leaves.flatMap { leaf -> [String] in
                let symbol = leaf.symbol
                let calls = [
                    """
                    \(access)func callAsFunction\(symbol.signature.declaration.signature.parameterClause.trimmedDescription) -> \(embeddingResult) {
                        embed(.\(symbol.caseName)(\(symbol.inputPath(owner: owner))(\(symbol.construction))))
                    }
                    """,
                    """
                    \(access)func callAsFunction(_ input: \(symbol.inputParameter(owner: owner))) -> \(embeddingResult) {
                        embed(.\(symbol.caseName)(input))
                    }
                    """,
                ]
                if symbol.isPrimary { return calls }
                return ["""
                    \(access)var \(symbol.caseName): \(symbol.name) { .init(embed: embed) }

                    \(access)struct \(symbol.name) {
                        \(access)let embed: (consuming \(source)) -> \(embeddingResult)

                    \(calls.joined(separator: "\n"))
                    }
                    """]
            }
            let embedding = DeclSyntax(stringLiteral: """
                \(childEmbeddings(embedding: true))
                \(access)struct Embedding<\(embeddingResult): ~Copyable\(parameters.isEmpty ? "" : ", " + parameters.map { "\($0): ~Copyable" }.joined(separator: ", "))>\(requirements) {
                    \(access)let embed: (consuming \(source)) -> \(embeddingResult)
                    \(access)init(_ embed: @escaping (consuming \(source)) -> \(embeddingResult)) { self.embed = embed }
                    \(embedded.joined(separator: "\n"))
                }
                """)
            return [
                embedding,
                DeclSyntax(stringLiteral: """
                    \(childEmbeddings(embedding: false))
                    \(capabilities)@Prisms
                    @Folds
                    @Cases
                    @Eliminator(consuming: true, asynchronous: true, throwing: true)
                    @dynamicMemberLookup
                    \(access)enum Coproduct\(generic): \(conformances)\(requirements) {
                    \(cases.joined(separator: "\n"))

                    \(constructors.joined(separator: "\n"))

                    \(forwarding)

                        \(access)typealias Embedding<\(embeddingResult): ~Copyable> = \(owner).Embedding<\(embeddingResult)\(parameters.isEmpty ? "" : ", " + parameters.joined(separator: ", "))>
                        \(access)static func sending(_ send: @escaping (consuming Self) -> Void) -> Embedding<Void> { .init(send) }
                        \(access)typealias Owner = \(owner)

                        // Effects policy: running a Call is always `async throws`, the widest of its arms.
                        \(access)static func run(_ owner: \(owner), _ call: consuming Self) async throws {
                            let eliminate: Eliminator<Void> = Eliminator<Void>(
                    \(arms.joined(separator: ",\n"))
                            )
                            try await eliminate(call)
                        }
                    }
                    """),
                DeclSyntax(stringLiteral: parameters.isEmpty
                    ? "\(access)typealias Call = Coproduct"
                    : "\(access)typealias Call = Coproduct<\((leaves.map(\.bound) + childParameters.map { $0.child.call.trimmedDescription }).joined(separator: ", "))>"),
            ]
        }
    }
}
