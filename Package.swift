// swift-tools-version: 6.4

import CompilerPluginSupport
import PackageDescription

let package = Package(
    name: "swift-interface",
    platforms: [
        .macOS(.v27),
        .iOS(.v27),
        .tvOS(.v27),
        .watchOS(.v27),
        .visionOS(.v27),
    ],
    products: [
        .library(name: "Interface Dependencies", targets: ["Interface Dependencies"]),
        .library(name: "Interface Syntax", targets: ["Interface Syntax"]),
        .library(name: "Interface Macro", targets: ["Interface Macro"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swift-atoms/swift-algebra.git", branch: "main"),
        .package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.0.0"),
        .package(url: "https://github.com/pointfreeco/swift-issue-reporting", from: "2.1.0"),
        .package(url: "https://github.com/swift-atoms/swift-optic.git", branch: "main"),
        .package(url: "https://github.com/swift-atoms/swift-operation.git", branch: "main"),
        .package(url: "https://github.com/swift-atoms/swift-coproduct.git", branch: "main"),
        .package(url: "https://github.com/swift-atoms/swift-product.git", branch: "main"),
        .package(url: "https://github.com/swiftlang/swift-syntax.git", "603.0.2"..<"604.0.0"),
    ],
    targets: [
        .target(name: "Interface Dependencies", dependencies: ["Interface Macro", "Interface Macro Plugin", .product(name: "Dependencies", package: "swift-dependencies"), .product(name: "IssueReporting", package: "swift-issue-reporting")]),
        .target(name: "Interface Syntax", dependencies: [
                .product(name: "Type Algebra Syntax", package: "swift-algebra"),
            .product(name: "Operation Syntax", package: "swift-operation"),
            .product(name: "Product Syntax", package: "swift-product"),
            .product(name: "SwiftSyntax", package: "swift-syntax"),
        ]),
        .target(
            name: "Interface Macro Core",
            dependencies: [
                .product(name: "Type Algebra Syntax", package: "swift-algebra"),
                "Interface Syntax",
                .product(name: "Operation Syntax", package: "swift-operation"),
                .product(name: "Product Syntax", package: "swift-product"),
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftSyntaxBuilder", package: "swift-syntax"),
            ]
        ),
        .macro(
            name: "Interface Macro Plugin",
            dependencies: [
                "Interface Macro Core",
                .product(name: "Type Algebra Syntax", package: "swift-algebra"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftSyntaxBuilder", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
            ]
        ),
        .target(
            name: "Interface Macro",
            dependencies: [
                "Interface Macro Plugin",
                .product(name: "Case Macro", package: "swift-optic"),
                .product(name: "Eliminator Macro", package: "swift-coproduct"),
                .product(name: "Fold Macro", package: "swift-optic"),
                .product(name: "Operation Macro", package: "swift-operation"),
                .product(name: "Optic", package: "swift-optic"),
                .product(name: "Prism Macro", package: "swift-optic"),
                .product(name: "Product Macro", package: "swift-product"),
            ]
        ),
        .testTarget(
            name: "Interface Macro Tests",
            dependencies: [
                "Interface Macro",
                "Interface Macro Core",
                .product(name: "Operation Syntax", package: "swift-operation"),
                .product(name: "Product Macro", package: "swift-product"),
                .product(name: "Product Syntax", package: "swift-product"),
                .product(name: "SwiftParser", package: "swift-syntax"),
            ],
            resources: [.copy("Fixtures")]
        ),
    ],
    swiftLanguageModes: [.v6]
)

for target in package.targets where ![.system, .binary, .plugin, .macro].contains(target.type) {
    let ecosystem: [SwiftSetting] = [
        .strictMemorySafety(),
        .enableUpcomingFeature("ExistentialAny"),
        .enableUpcomingFeature("InternalImportsByDefault"),
        .enableUpcomingFeature("MemberImportVisibility"),
        .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
        .enableExperimentalFeature("Lifetimes"),
        .enableExperimentalFeature("MoveOnlyTuples"),
        .enableUpcomingFeature("InferIsolatedConformances"),
    ]
    let package: [SwiftSetting] = []

    target.swiftSettings = (target.swiftSettings ?? []) + ecosystem + package
}

// Consumer compilation must reject visibility regressions, even when other packages suppress warnings.
for target in package.targets where target.type == .test || target.name.hasSuffix("Consumer Fixtures") {
    target.swiftSettings = (target.swiftSettings ?? []) + [.treatAllWarnings(as: .error)]
}
