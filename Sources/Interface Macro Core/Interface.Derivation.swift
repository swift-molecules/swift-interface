public import SwiftSyntax
public import Product_Macro_Core
import SwiftSyntaxBuilder

// @Interface composes: it reads a signature as operations, spells the names below, and attaches the atom macros
// that own each derivation — @Product for the model (the stored arrows and their initializer), @Structural and
// @Copyable for the Call's capabilities, @Prisms/@Folds/@Cases/@Eliminator for the Call's algebra. What it derives
// itself is what no atom models: the requests, the operation symbols, the label-preserving witnesses, the Call's
// constructors, and the interpreter.
//
// Every derived declaration is a member, never an extension: an extension macro attached inside another macro's
// extension output is typechecked but never lowered (Swift 6.4), so the attached atoms only work among members.
extension Interface {
    public enum Derivation {
        public static func members(of signature: Interface.Analysis) -> [DeclSyntax] {
            let access = signature.product.access.map { "\($0.name.text) " } ?? ""
            let owner = signature.owner.trimmedDescription
            let operations = Self.operations(of: signature)
            let groups = Self.groups(of: operations)
            let model = Self.model(of: signature, operations: operations, owner: owner, access: access)
            return [model.declaration]
                + Self.witnesses(of: signature, model: model, operations: operations, owner: owner, access: access)
                + [Self.interpreter(of: signature, operations: operations, access: access)]
                + Self.symbols(of: operations, owner: owner, access: access)
                + Self.call(of: signature, operations: operations, access: access)
                + operations.filter(\.isPrimary).map { primaryRequest($0, access: access) }
                + groups.map { namespace($0.operations, access: access) }
        }

        public static func extensions(
            of signature: Interface.Analysis,
            extending type: TypeSyntax
        ) -> [ExtensionDeclSyntax] {
            []
        }

        // The model of an interface is @Product's: a protocol with one request-typed arrow per operation and one
        // getter per child, whose `Product` the owner stores. Its analysis is read back through Product.Analysis
        // so that the owner's forwarding initializer takes exactly the product's parameters.
        struct Model {
            let declaration: DeclSyntax
            let analysis: Product.Analysis
        }

        private static func model(
            of signature: Interface.Analysis,
            operations: [Operation],
            owner: String,
            access: String
        ) -> Model {
            let requirements = operations.map { operation in
                "func \(operation.storage)(_ request: \(operation.arrowParameter(owner: owner)))\(operation.effects) -> \(operation.output)"
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
        // declaration's labels; each operation is also callable with its request.
        private static func witnesses(
            of signature: Interface.Analysis,
            model: Model,
            operations: [Operation],
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
            let calls = operations.flatMap { operation -> [String] in
                let request = operation.requestPath(owner: owner)
                let name = operation.isPrimary ? "callAsFunction" : operation.name
                let direct = "\(operation.prefix)product.\(operation.storage)(\(request)(\(operation.construction)))"
                let forwarding = "\(operation.prefix)product.\(operation.storage)(request)"
                return [
                    """
                    \(access)func \(name)\(operation.function.declaration.signature.trimmedDescription) {
                        \(operation.function.returnsVoid ? direct : "return \(direct)")
                    }
                    """,
                    """
                    \(access)func \(name)(_ request: \(operation.arrowParameter(owner: owner)))\(operation.effects) -> \(operation.output) {
                        \(operation.function.returnsVoid ? forwarding : "return \(forwarding)")
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
            operations: [Operation],
            access: String
        ) -> DeclSyntax {
            let arms = operations.map { operation -> String in
                """
                case let .\(operation.caseName)(application):
                    _ = \(operation.prefix)product.\(operation.storage)(application.consume())
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

        // A request is the product of an operation's parameters, with the declaration's labels on its
        // initializer. Its capabilities are whatever the compiler synthesizes from its fields: Hashable (a
        // request is a value) and Sendable (declared for convenience — a public type gets no implicit Sendable,
        // and a request crosses into storage tasks; nothing in the interface itself relies on it) are declared
        // and checked; Copyable is suppressed when a parameter is transferred.
        private static func request(
            _ operation: Operation,
            access: String
        ) -> String {
            let coordinate = operation.coordinate
            let header = operation.transfers
                ? "\(access)struct Request: ~Copyable, Swift.Sendable {"
                : "\(access)struct Request: Swift.Hashable, Swift.Sendable {"
            let fields = coordinate.inputs.map { input in
                "\(access)var \(input.parameter.localName.text): \(input.type.trimmedDescription)"
            }.joined(separator: "\n")
            let parameters = coordinate.inputs.map { input in
                let declaration = input.parameter.declaration
                let label = declaration.firstName.tokenKind == .wildcard ? "_" : declaration.firstName.text
                let local = input.parameter.localName.text
                let type = input.type.trimmedDescription
                let spelled = input.parameter.transfersOwnership ? "consuming \(type)" : type
                return label == local ? "\(local): \(spelled)" : "\(label) \(local): \(spelled)"
            }.joined(separator: ", ")
            let assignments = coordinate.inputs.map { input in
                "self.\(input.parameter.localName.text) = \(input.parameter.localName.text)"
            }.joined(separator: "\n")
            return """
                \(header)
                \(fields)

                    \(access)init(\(parameters)) {
                    \(assignments)
                    }
                }

                \(access)typealias Result = \(operation.output)
                """
        }

        // A primary operation's request lives on the owner, under its variant when overloaded.
        private static func primaryRequest(_ operation: Operation, access: String) -> DeclSyntax {
            let body = request(operation, access: access)
            guard let variant = operation.variant else { return DeclSyntax(stringLiteral: body) }
            return DeclSyntax(stringLiteral: """
                \(access)enum \(variant) {
                \(body)
                }
                """)
        }

        // A named operation's requests live in a namespace under its symbol, one per variant when overloaded.
        private static func namespace(_ operations: [Operation], access: String) -> DeclSyntax {
            let requests = operations.map { operation -> String in
                let body = request(operation, access: access)
                guard let variant = operation.variant else { return body }
                return """
                    \(access)enum \(variant) {
                    \(body)
                    }
                    """
            }.joined(separator: "\n\n")
            return DeclSyntax(stringLiteral: """
                \(access)enum \(operations[0].symbol) {
                \(requests)
                }
                """)
        }

        private static func symbols(
            of operations: [Operation],
            owner: String,
            access: String
        ) -> [DeclSyntax] {
            guard !operations.isEmpty else { return [] }
            let symbols = operations.map {
                symbol($0, owner: owner, access: access)
            }.joined(separator: "\n\n")
            return [DeclSyntax(stringLiteral: """
                \(access)enum Operations {
                \(symbols)
                }
                """)]
        }

        private static func symbol(
            _ operation: Operation,
            owner: String,
            access: String
        ) -> String {
            let coordinate = operation.coordinate
            return """
                \(access)enum \(operation.symbolName): Operation::Operation.Symbol {
                    \(access)typealias Input = \(operation.requestPath(owner: owner))
                    \(access)typealias Output = \(coordinate.output.trimmedDescription)
                    \(access)typealias Failure = \(coordinate.failure.trimmedDescription)
                    \(access)typealias Application = Operation::Operation.Application<
                        Self
                    >
                }
                """
        }

        // The Call is generic in its summands so that the compiler, not this macro, decides its capabilities:
        // @Structural and @Copyable (the stand-ins for a variadic `Coproduct<each Application>`) add each exactly
        // when every summand has it. Leaves bind a parameter to the operation's Application, children to the
        // child's Call. Its algebra is attached, not derived here: @Prisms, @Folds and @Cases from swift-optic,
        // @Eliminator from swift-coproduct.
        //
        // Call remains Escapable because its canonical generated prisms return both Call and Application from
        // stored escaping arrows. Swift 6.4 cannot express those result lifetime dependencies; the focused Optic
        // and Interface compiler fixtures lock down that boundary.
        private static func call(
            of signature: Interface.Analysis,
            operations: [Operation],
            access: String
        ) -> [DeclSyntax] {
            let owner = signature.owner.trimmedDescription
            let leaves = operations.map { operation in
                (
                    parameter: "\(operation.symbolName)Application",
                    name: TokenSyntax.identifier(operation.caseName),
                    bound: "\(owner).Operations.\(operation.symbolName).Application"
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
            let constructors = zip(operations, leaves).map { operation, leaf in
                let coordinate = operation.coordinate
                return """
                    \(access)static func \(operation.constructor)\(coordinate.declaration.signature.parameterClause.trimmedDescription) -> Self
                    where \(leaf.parameter) == \(leaf.bound) {
                        let application: \(leaf.bound) = .init(
                            \(operation.requestPath(owner: owner))(\(operation.construction))
                        )
                        return Self.\(operation.caseName)(application)
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

extension Interface.Derivation {
    // The naming table. Every spelling @Interface derives comes from here; consumers of the derivation (the
    // Client macro) read the same table rather than re-deriving a name.
    //
    // | derived                          | spelling                                                       |
    // |----------------------------------|----------------------------------------------------------------|
    // | operation symbol (`Operations.X`) | capitalised base name; `Call` for the primary; a variant suffix |
    // |                                  | (capitalised first label, or local name when unlabelled) when  |
    // |                                  | the base name is overloaded                                    |
    // | model requirement / product label | the stored arrow's key for a primary (`run`, or the lower-camel |
    // |                                  | variant), the Call case name otherwise                         |
    // | request namespace (`Owner.X`)     | the symbol name of a non-primary group                         |
    // | request (`…Request`)              | `Owner.Request` (primary) or `Owner.X.Request`; under a         |
    // |                                  | `Variant` enum when the base name is overloaded                |
    // | Call case                         | the base name, `call` for the primary; variant appended        |
    // |                                  | (`nameVariant` / lower-camel variant for a primary)            |
    // | Call constructor                  | `call` for every primary, the base name otherwise; the         |
    // |                                  | declaration's parameter clause                                 |
    // | child Call parameter              | capitalised child name + `Call`                                |
    // | leaf Call parameter               | symbol name + `Application`                                    |
    public struct Operation {
        public let coordinate: Interface.Analysis.Coordinate
        public let group: String
        public let variant: String?
        public let isPrimary: Bool

        public var function: Product.Analysis.Function { coordinate.function }
        public var name: String { function.name.text }
        public var symbol: String { isPrimary ? "Call" : coordinate.symbol.text }
        public var caseName: String {
            if isPrimary { return variant.map { "\($0.prefix(1).lowercased())\($0.dropFirst())" } ?? "call" }
            return variant.map { "\(name)\($0)" } ?? name
        }
        public var constructor: String { isPrimary ? "call" : name }
        public var symbolName: String {
            if isPrimary { return variant ?? "Call" }
            return variant.map { "\(symbol)\($0)" } ?? symbol
        }
        public var key: String {
            guard let variant else { return "run" }
            return "\(variant.prefix(1).lowercased())\(variant.dropFirst())"
        }
        // The model's requirement for this operation: its key for a primary, its case name otherwise.
        public var storage: String { isPrimary ? key : caseName }
        public func arrowParameter(owner: String) -> String {
            "\(transfers ? "consuming " : "")\(requestPath(owner: owner))"
        }
        public func requestPath(owner: String) -> String {
            let base = isPrimary ? owner : "\(owner).\(symbol)"
            guard let variant else { return "\(base).Request" }
            return "\(base).\(variant).Request"
        }
        public var output: String { coordinate.output.trimmedDescription }
        public var effects: String {
            function.declaration.signature.effectSpecifiers.map { " \($0.trimmedDescription)" } ?? ""
        }
        public var prefix: String {
            let effects = function.declaration.signature.effectSpecifiers
            return (effects?.throwsClause != nil ? "try " : "") + (effects?.asyncSpecifier != nil ? "await " : "")
        }
        public var transfers: Bool { coordinate.inputs.contains { $0.parameter.transfersOwnership } }
        // The request built from the declaration's parameters, labelled as declared.
        public var construction: String {
            coordinate.inputs.map { input in
                let declaration = input.parameter.declaration
                let label = declaration.firstName.tokenKind == .wildcard ? "" : "\(declaration.firstName.text): "
                return "\(label)\(input.expression.trimmedDescription)"
            }.joined(separator: ", ")
        }
    }

    public static func operations(of signature: Interface.Analysis) -> [Operation] {
        let counts = Dictionary(grouping: signature.coordinates, by: \.name.text).mapValues(\.count)
        return signature.coordinates.map { coordinate in
            let name = coordinate.name.text
            let isPrimary = name == "callAsFunction"
            var variant: String?
            if counts[name, default: 0] > 1, let first = coordinate.function.parameters.first {
                let label = first.declaration.firstName.tokenKind == .wildcard
                    ? first.localName.text
                    : first.declaration.firstName.text
                variant = "\(label.prefix(1).uppercased())\(label.dropFirst())"
            }
            return Operation(coordinate: coordinate, group: name, variant: variant, isPrimary: isPrimary)
        }
    }

    public static func groups(of operations: [Operation]) -> [(name: String, operations: [Operation])] {
        var order: [String] = []
        var grouped: [String: [Operation]] = [:]
        for operation in operations where !operation.isPrimary {
            if grouped[operation.group] == nil { order.append(operation.group) }
            grouped[operation.group, default: []].append(operation)
        }
        return order.map { ($0, grouped[$0] ?? []) }
    }
}
