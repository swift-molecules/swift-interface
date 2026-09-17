public import SwiftSyntax
import Product_Macro_Core
import SwiftSyntaxBuilder

extension Interface {
    public enum Derivation {
        public static func members(of signature: Interface.Analysis) -> [DeclSyntax] {
            let access = signature.product.access.map { "\($0.name.text) " } ?? ""
            let owner = signature.owner.trimmedDescription
            let operations = Self.operations(of: signature)
            let primaries = operations.filter(\.isPrimary)
            let groups = Self.groups(of: operations)
            let stored = primaries.map { "\(access)let `\($0.key)`: \($0.arrow(owner: owner))" }
                + groups.map { group in
                    "\(access)var \(group.name): \(owner).\(group.operations[0].symbol)"
                }
                + signature.children.map { child in
                    "\(access)var \(child.name.text): \(child.domain.trimmedDescription)"
                }
            let parameters = primaries.map {
                    "\($0.variant == nil ? "_ run" : $0.key): @escaping \($0.arrow(owner: owner))"
                }
                + groups.map { group in
                    group.operations.count == 1
                        ? "\(group.name): @escaping \(group.operations[0].arrow(owner: owner))"
                        : "\(group.name): \(owner).\(group.operations[0].symbol)"
                }
                + signature.children.map { child in
                    "\(child.name.text): \(child.domain.trimmedDescription)"
                }
            let assignments = primaries.map { "self.`\($0.key)` = \($0.variant == nil ? "run" : "`\($0.key)`")" }
                + groups.map { group in
                    group.operations.count == 1
                        ? "self.\(group.name) = \(owner).\(group.operations[0].symbol)(\(group.name))"
                        : "self.\(group.name) = \(group.name)"
                }
                + signature.children.map { child in
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
            let owner = signature.owner.trimmedDescription
            let operations = Self.operations(of: signature)
            let primaries = operations.filter(\.isPrimary)
            let groups: [[DeclSyntax]] = [
                symbols(of: operations, access: spelling),
                call(of: signature, operations: operations, access: access),
            ]
            + (primaries.isEmpty ? [] : [Self.primary(primaries, owner: owner, access: spelling)])
            + Self.groups(of: operations).map {
                callable($0.operations, owner: owner, access: spelling)
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

        private static func request(
            _ operation: Operation,
            access: String
        ) -> String {
            let coordinate = operation.coordinate
            let function = operation.function
            let isGeneric = function.declaration.genericParameterClause != nil
            let transfers = operation.transfers
            let generics = isGeneric
                ? coordinate.inputs.map { input in
                    let local = input.parameter.localName.text
                    return "\(local.prefix(1).uppercased())\(local.dropFirst())"
                }
                : coordinate.inputs.map(\.type.trimmedDescription)
            let clause = isGeneric && !generics.isEmpty ? "<\(generics.joined(separator: ", "))>" : ""
            let binding = isGeneric && !generics.isEmpty
                ? "<\(coordinate.inputs.map(\.type.trimmedDescription).joined(separator: ", "))>"
                : ""
            let header = isGeneric
                ? "@Value\n\(access)struct Product\(clause) {"
                : transfers
                    ? "\(access)struct Request: ~Copyable {"
                    : "\(access)struct Request: Swift.Hashable, Swift.Sendable {"
            let alias = isGeneric ? "\(access)typealias Request = Product\(binding)" : ""
            let fields = zip(coordinate.inputs, generics).map { input, generic in
                "\(access)let \(input.parameter.localName.text): \(generic)"
            }.joined(separator: "\n")
            let parameters = zip(coordinate.inputs, generics).map { input, generic in
                let declaration = input.parameter.declaration
                let label = declaration.firstName.tokenKind == .wildcard ? "_" : declaration.firstName.text
                let local = input.parameter.localName.text
                let type = input.parameter.transfersOwnership ? "consuming \(generic)" : generic
                return label == local ? "\(local): \(type)" : "\(label) \(local): \(type)"
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

                \(alias)

                \(access)typealias Result = \(operation.output)
                """
        }

        private static func primary(
            _ operations: [Operation],
            owner: String,
            access: String
        ) -> [DeclSyntax] {
            operations.flatMap { operation -> [DeclSyntax] in
                let request = operation.requestPath(owner: owner)
                let requestParameter = operation.transfers ? "consuming \(request)" : request
                let signature = operation.function.declaration.signature.trimmedDescription
                let call = operation.function.returnsVoid
                    ? "\(operation.prefix)self.`\(operation.key)`(\(request)(\(operation.construction)))"
                    : "return \(operation.prefix)self.`\(operation.key)`(\(request)(\(operation.construction)))"
                let forwarding = operation.function.returnsVoid
                    ? "\(operation.prefix)self.`\(operation.key)`(request)"
                    : "return \(operation.prefix)self.`\(operation.key)`(request)"
                let body = self.request(operation, access: access)
                let requestDeclaration = operation.variant.map { variant in
                    """
                    \(access)enum \(variant) {
                    \(body)
                    }
                    """
                } ?? body
                return [
                    DeclSyntax(stringLiteral: requestDeclaration),
                    DeclSyntax(stringLiteral: """
                        \(access)func callAsFunction\(signature) {
                            \(call)
                        }
                        """),
                    DeclSyntax(stringLiteral: """
                        \(access)func callAsFunction(_ request: \(requestParameter))\(operation.effects) -> \(operation.output) {
                            \(forwarding)
                        }
                        """),
                ]
            }
        }

        private static func callable(
            _ operations: [Operation],
            owner: String,
            access: String
        ) -> [DeclSyntax] {
            let symbol = operations[0].symbol
            let name = operations[0].name
            let overloaded = operations.count > 1
            let requests = operations.map { operation -> String in
                let body = request(operation, access: access)
                guard let variant = operation.variant else { return body }
                return """
                    \(access)enum \(variant) {
                    \(body)
                    }
                    """
            }.joined(separator: "\n\n")
            let arrows = operations.map { operation in
                "\(access)let `\(operation.key)`: \(operation.arrow(owner: owner))"
            }.joined(separator: "\n")
            let parameters = operations.map { operation in
                overloaded
                    ? "\(operation.key): @escaping \(operation.arrow(owner: owner))"
                    : "_ run: @escaping \(operation.arrow(owner: owner))"
            }.joined(separator: ", ")
            let assignments = operations.map { operation in
                "self.`\(operation.key)` = \(overloaded ? "`\(operation.key)`" : "run")"
            }.joined(separator: "\n")
            let calls = operations.map { operation -> String in
                let request = operation.requestPath(owner: owner)
                let requestParameter = operation.transfers ? "consuming \(request)" : request
                let direct = operation.function.returnsVoid
                    ? "\(operation.prefix)`\(operation.key)`(\(request)(\(operation.construction)))"
                    : "return \(operation.prefix)`\(operation.key)`(\(request)(\(operation.construction)))"
                let forwarding = operation.function.returnsVoid
                    ? "\(operation.prefix)`\(operation.key)`(request)"
                    : "return \(operation.prefix)`\(operation.key)`(request)"
                return """
                    \(access)func callAsFunction\(operation.function.declaration.signature.trimmedDescription) {
                        \(direct)
                    }

                    \(access)func callAsFunction(_ request: \(requestParameter))\(operation.effects) -> \(operation.output) {
                        \(forwarding)
                    }
                    """
            }.joined(separator: "\n\n")
            let witnesses = operations.map { operation -> DeclSyntax in
                let request = operation.requestPath(owner: owner)
                let body = operation.function.returnsVoid
                    ? "\(operation.prefix)self.\(name).`\(operation.key)`(\(request)(\(operation.construction)))"
                    : "return \(operation.prefix)self.\(name).`\(operation.key)`(\(request)(\(operation.construction)))"
                return DeclSyntax(stringLiteral: """
                    \(access)func \(name)\(operation.function.declaration.signature.trimmedDescription) {
                        \(body)
                    }
                    """)
            }
            return [
                DeclSyntax(stringLiteral: """
                    \(access)struct \(symbol) {
                    \(requests)

                    \(arrows)

                        \(access)init(\(parameters)) {
                        \(assignments)
                        }

                    \(calls)
                    }
                    """),
            ] + witnesses
        }

        private static func symbols(
            of operations: [Operation],
            access: String
        ) -> [DeclSyntax] {
            guard !operations.isEmpty else { return [] }
            let symbols = operations.map {
                symbol($0, access: access)
            }.joined(separator: "\n\n")
            return [DeclSyntax(stringLiteral: """
                \(access)enum Operations {
                \(symbols)
                }
                """)]
        }

        private static func symbol(
            _ operation: Operation,
            access: String
        ) -> String {
            let coordinate = operation.coordinate
            return """
                \(access)enum \(operation.symbolName): Operation::Operation.Symbol {
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
            operations: [Operation],
            access: DeclModifierSyntax?
        ) -> [DeclSyntax] {
            let accessSpelling = access.map { "\($0.name.text) " } ?? ""
            // The coproduct is generic in its summands so that the compiler, not a
            // syntax macro, decides whether a Call is Copyable: @Structural adds
            // `Copyable` exactly when every summand is. Leaves bind the parameter to
            // the operation's Application, children to the child's Call. Its
            // algebra (prisms, folds, eliminator) is not derived here: the enum
            // carries the atom macros that own those derivations.
            //
            // Call remains Escapable because its canonical generated prisms return
            // both Call and Application from stored escaping arrows. Swift 6.4
            // cannot express those result lifetime dependencies; the focused Optic
            // and Interface compiler fixtures lock down that boundary.
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
                let constructor = operation.isPrimary ? "call" : operation.name
                return """
                    \(accessSpelling)static func \(constructor)\(coordinate.declaration.signature.parameterClause.trimmedDescription) -> Self
                    where \(leaf.parameter) == \(leaf.bound) {
                        let application: \(leaf.bound) = .init(
                            \(coordinate.inputExpression.trimmedDescription)
                        )
                        return Self.\(operation.caseName)(application)
                    }
                    """
            }.joined(separator: "\n")

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
                    @Prisms
                    @Folds
                    @Eliminator
                    \(accessSpelling)enum Coproduct<\(parameters)>: ~Copyable, Operation::Operation.Coproduct {
                    \(caseDeclarations)

                    \(constructors)

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

extension Interface.Derivation {
    struct Operation {
        let coordinate: Interface.Analysis.Coordinate
        let group: String
        let variant: String?
        let isPrimary: Bool

        var function: Product.Analysis.Function { coordinate.function }
        var name: String { function.name.text }
        var symbol: String { isPrimary ? "Call" : coordinate.symbol.text }
        var caseName: String {
            if isPrimary { return variant.map { "\($0.prefix(1).lowercased())\($0.dropFirst())" } ?? "call" }
            return variant.map { "\(name)\($0)" } ?? name
        }
        var symbolName: String {
            if isPrimary { return variant ?? "Call" }
            return variant.map { "\(symbol)\($0)" } ?? symbol
        }
        var key: String {
            guard let variant else { return "run" }
            return "\(variant.prefix(1).lowercased())\(variant.dropFirst())"
        }
        func requestPath(owner: String) -> String {
            let base = isPrimary ? owner : "\(owner).\(symbol)"
            guard let variant else { return "\(base).Request" }
            return "\(base).\(variant).Request"
        }
        var output: String { coordinate.output.trimmedDescription }
        var effects: String {
            function.declaration.signature.effectSpecifiers.map { " \($0.trimmedDescription)" } ?? ""
        }
        var prefix: String {
            let effects = function.declaration.signature.effectSpecifiers
            return (effects?.throwsClause != nil ? "try " : "") + (effects?.asyncSpecifier != nil ? "await " : "")
        }
        var transfers: Bool { coordinate.inputs.contains { $0.parameter.transfersOwnership } }
        func arrow(owner: String) -> String {
            let request = requestPath(owner: owner)
            return "(\(transfers ? "consuming " : "")\(request))\(effects) -> \(output)"
        }
        var construction: String {
            coordinate.inputs.map { input in
                let declaration = input.parameter.declaration
                let label = declaration.firstName.tokenKind == .wildcard ? "" : "\(declaration.firstName.text): "
                return "\(label)\(input.expression.trimmedDescription)"
            }.joined(separator: ", ")
        }
    }

    static func operations(of signature: Interface.Analysis) -> [Operation] {
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

    static func groups(of operations: [Operation]) -> [(name: String, operations: [Operation])] {
        var order: [String] = []
        var grouped: [String: [Operation]] = [:]
        for operation in operations where !operation.isPrimary {
            if grouped[operation.group] == nil { order.append(operation.group) }
            grouped[operation.group, default: []].append(operation)
        }
        return order.map { ($0, grouped[$0] ?? []) }
    }
}
