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
        .library(name: "Interface Macro", targets: ["Interface Macro"]),
        .library(name: "Interface Macro Core", targets: ["Interface Macro Core"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swift-atoms/swift-optic.git", branch: "main"),
        .package(url: "https://github.com/swift-atoms/swift-operation.git", branch: "main"),
        .package(url: "https://github.com/swift-atoms/swift-coproduct.git", branch: "main"),
        .package(url: "https://github.com/swift-atoms/swift-product.git", branch: "main"),
        .package(url: "https://github.com/swiftlang/swift-syntax.git", "603.0.2"..<"604.0.0"),
    ],
    targets: [
        .target(
            name: "Interface Macro Core",
            dependencies: [
                .product(name: "Coproduct Macro Core", package: "swift-coproduct"),
                .product(name: "Eliminator Macro Core", package: "swift-coproduct"),
                .product(name: "Prism Macro Core", package: "swift-optic"),
                .product(name: "Fold Macro Core", package: "swift-optic"),
                .product(name: "Product Macro Core", package: "swift-product"),
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftSyntaxBuilder", package: "swift-syntax"),
            ]
        ),
        .macro(
            name: "Interface Macro Plugin",
            dependencies: [
                "Interface Macro Core",
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
                .product(name: "Operation", package: "swift-operation"),
                .product(name: "Optic", package: "swift-optic"),
            ]
        ),
        .testTarget(
            name: "Interface Macro Tests",
            dependencies: [
                "Interface Macro",
                "Interface Macro Core",
                .product(name: "Product Macro", package: "swift-product"),
                .product(name: "Product Macro Core", package: "swift-product"),
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
