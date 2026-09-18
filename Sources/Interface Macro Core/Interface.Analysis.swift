public import SwiftSyntax
public import Product_Macro_Core
import SwiftSyntaxBuilder

extension Interface {
    public struct Analysis {
        public struct Coordinate {
            public struct Input {
                public let parameter: Product.Analysis.Parameter
                public let label: TokenSyntax
                public let type: TypeSyntax
                public let expression: ExprSyntax
            }

            public let function: Product.Analysis.Function
            public let symbol: TokenSyntax
            public let inputs: [Input]
            public let output: TypeSyntax
            public let failure: TypeSyntax

            public var declaration: FunctionDeclSyntax { function.declaration }
            public var name: TokenSyntax { function.name }

            fileprivate init(
                _ function: Product.Analysis.Function,
                owner: TypeSyntax,
                shadowed: Set<String>
            ) {
                self.function = function
                symbol = .identifier(Self.symbolName(function.name.text))
                let qualify = DomainQualifier(owner: owner, names: shadowed)
                inputs = function.parameters.map { parameter in
                    let declaration = parameter.declaration
                    let source = declaration.firstName.tokenKind == .wildcard
                        ? parameter.localName
                        : declaration.firstName
                    return Input(
                        parameter: parameter,
                        label: .identifier(source.text),
                        type: qualify.rewrite(parameter.valueType),
                        expression: parameter.ownedExpression
                    )
                }
                output = qualify.rewrite(function.output)
                failure = function.thrownError.map(qualify.rewrite)
                    ?? TypeSyntax(
                        stringLiteral: function.isUntypedThrows ? "any Swift.Error" : "Never"
                    )
            }

            static func symbolName(_ operation: String) -> String {
                guard let first = operation.first else { return operation }
                return String(first).uppercased() + String(operation.dropFirst())
            }
        }

        public struct Child {
            public let declaration: VariableDeclSyntax
            public let name: TokenSyntax
            public let domain: TypeSyntax

            public var call: TypeSyntax {
                TypeSyntax(MemberTypeSyntax(baseType: domain, name: .identifier("Call")))
            }
        }

        public let declaration: ProtocolDeclSyntax
        public let owner: TypeSyntax
        public let product: Product.Analysis
        public let coordinates: [Coordinate]
        public let children: [Child]
        public let bindings: [TypeSyntax]
        public let diagnostics: [String]

        public static let derived = [
            "Input",
            "Output",
            "Failure",
            "Operations",
            "Product",
            "Model",
            "Client",
            "Coproduct",
            "Call",
            "Cases",
            "Prisms",
            "Folds",
            "Eliminator",
        ]

        public init(
            declaration: ProtocolDeclSyntax,
            owner: TypeSyntax
        ) {
            self.declaration = declaration
            self.owner = owner
            let product = Product.Analysis(declaration)
            self.product = product
            let shadowed = Set(
                Self.derived + product.functionCoordinates.map {
                    Coordinate.symbolName($0.name.text)
                }
            )
            coordinates = product.functionCoordinates.map {
                Coordinate($0, owner: owner, shadowed: shadowed)
            }

            var reasons = product.diagnostics
            if declaration.inheritanceClause != nil {
                reasons.append("inherited protocols are not a closed finite signature")
            }
            for function in product.functionCoordinates {
                for parameter in function.parameters where parameter.isInout {
                    reasons.append(
                        "`\(function.name.text)` has an inout parameter; a signature Call is an owned snapshot, not a state transition"
                    )
                }
            }

            var domains: [String: TypeSyntax] = [:]
            var bindings: [TypeSyntax] = []
            for coordinate in product.associatedTypeCoordinates {
                guard let domain = Self.domain(of: coordinate) else {
                    reasons.append(
                        "`\(coordinate.declaration.trimmedDescription)` does not name a child semantic protocol"
                    )
                    continue
                }
                domains[coordinate.name.text] = domain
                bindings.append(
                    TypeSyntax(MemberTypeSyntax(baseType: domain, name: .identifier("Product")))
                )
            }
            self.bindings = bindings

            var usedDomains: Set<String> = []
            var recognizedChildren: [Child] = []
            for property in product.propertyCoordinates {
                if
                    let associated = property.type.as(IdentifierTypeSyntax.self),
                    associated.moduleSelector == nil,
                    associated.genericArgumentClause == nil,
                    let domain = domains[associated.name.text]
                {
                    usedDomains.insert(associated.name.text)
                    recognizedChildren.append(
                        Child(declaration: property.declaration, name: property.name, domain: domain)
                    )
                } else {
                    recognizedChildren.append(
                        Child(declaration: property.declaration, name: property.name, domain: property.type.trimmed)
                    )
                }
            }
            for coordinate in product.associatedTypeCoordinates
            where !usedDomains.contains(coordinate.name.text) {
                reasons.append("`\(coordinate.name.text)` has no getter coordinate")
            }
            children = recognizedChildren
            diagnostics = reasons
        }

        fileprivate static func domain(
            of associated: Product.Analysis.AssociatedType
        ) -> TypeSyntax? {
            guard
                associated.declaration.inheritanceClause?.inheritedTypes.count == 1,
                let inherited = associated.constraint,
                let semantic = inherited.as(MemberTypeSyntax.self),
                ["Interface", "`Interface`", "Protocol", "`Protocol`"].contains(semantic.name.text),
                semantic.genericArgumentClause == nil
            else { return nil }
            return semantic.baseType
        }
    }
}


private final class DomainQualifier: SyntaxRewriter {
    let owner: TypeSyntax
    let names: Set<String>

    init(owner: TypeSyntax, names: Set<String>) {
        self.owner = owner
        self.names = names
    }

    func rewrite(_ type: TypeSyntax) -> TypeSyntax {
        TypeSyntax(visit(type))
    }

    override func visit(_ node: IdentifierTypeSyntax) -> TypeSyntax {
        guard
            node.moduleSelector == nil,
            node.genericArgumentClause == nil,
            names.contains(node.name.text)
        else { return super.visit(node) }
        return TypeSyntax(
            MemberTypeSyntax(
                baseType: owner.trimmed,
                name: .identifier(node.name.text)
            )
        )
    }
}
