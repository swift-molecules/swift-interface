public import Operation_Macro_Core
public import Product_Macro_Core
public import SwiftSyntax

extension Interface {
    // An interface read as its operations (Operation.Analysis, whose symbols @Operations declares beside the
    // protocol) and its children (the getters of the product). @Interface derives nothing about an operation
    // itself; it composes symbols into a model, a Call and an interpreter.
    public struct Analysis {
        public typealias Symbol = Operation.Analysis.Symbol

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
        public let operations: Operation.Analysis
        public let children: [Child]
        public let diagnostics: [String]

        public var symbols: [Symbol] { operations.symbols }

        /// The unlabelled primary operation, when there is one: the interface is then this operation's symbol.
        public var run: Symbol? { symbols.first { $0.isPrimary && $0.variant == nil } }

        public static let derived = [
            "Model",
            "Product",
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
            operations = Operation.Analysis(declaration: declaration, owner: owner, shadowed: Set(Self.derived))

            var reasons = product.diagnostics + operations.diagnostics
            if declaration.inheritanceClause != nil {
                reasons.append("inherited protocols are not a closed finite signature")
            }
            if !declaration.attributes.contains(where: { attribute in
                attribute.as(AttributeSyntax.self)?.attributeName.as(IdentifierTypeSyntax.self)?.name.text == "Operations"
            }) {
                reasons.append("the interface's protocol must carry @Operations, which declares the symbols the interface composes")
            }

            var domains: [String: TypeSyntax] = [:]
            for coordinate in product.associatedTypeCoordinates {
                guard let domain = Self.domain(of: coordinate) else {
                    reasons.append("`\(coordinate.declaration.trimmedDescription)` does not name a child semantic protocol")
                    continue
                }
                domains[coordinate.name.text] = domain
            }

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
                    recognizedChildren.append(Child(declaration: property.declaration, name: property.name, domain: domain))
                } else {
                    recognizedChildren.append(Child(declaration: property.declaration, name: property.name, domain: property.type.trimmed))
                }
            }
            for coordinate in product.associatedTypeCoordinates where !usedDomains.contains(coordinate.name.text) {
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
