import Foundation
import Testing

@Suite
private struct `Compiler Tests` {
    @Test
    func `interface must model its own protocol`() throws {
        let diagnostic = try typecheckFailure(named: "Unmodelled Interface.swift")

        #expect(
            diagnostic.contains(
                "@Interface requires `Greeting` to declare conformance to its own `Interface`"
            )
        )
    }

    @Test
    func `one operation result cannot satisfy another result family`() throws {
        let diagnostic = try typecheckFailure(named: "Wrong Result.swift")

        #expect(
            diagnostic.contains(
                "cannot convert value of type 'Either<Counter.Increment.Failure, Counter.Increment.Output>'"
            )
        )
    }

    @Test
    func `application rejects another operation input`() throws {
        let diagnostic = try typecheckFailure(named: "Wrong Input.swift")

        #expect(diagnostic.contains("cannot convert value of type 'Counter.Limit'"))
    }

    @Test
    func `result rejects another operation output`() throws {
        let diagnostic = try typecheckFailure(named: "Wrong Output.swift")

        #expect(diagnostic.contains("cannot convert value of type 'Counter.Value'"))
    }

    @Test
    func `result rejects another operation failure`() throws {
        let diagnostic = try typecheckFailure(named: "Wrong Failure.swift")

        #expect(
            diagnostic.contains("cannot convert value of type 'Counter.Failure'")
        )
    }

    @Test
    func `elimination requires every leaf operation`() throws {
        let diagnostic = try typecheckFailure(named: "Incomplete Elimination.swift")

        #expect(diagnostic.contains("missing argument for parameter 'second' in call"))
    }

    @Test
    func `root elimination requires every child signature`() throws {
        let diagnostic = try typecheckFailure(named: "Incomplete Root Elimination.swift")

        #expect(diagnostic.contains("missing argument for parameter 'counter' in call"))
    }

    @Test
    func `product construction requires every operation`() throws {
        let diagnostic = try typecheckFailure(named: "Incomplete Product.swift")

        #expect(diagnostic.contains("missing argument for parameter 'second' in call"))
    }

    @Test
    func `call is noncopyable when an input is noncopyable`() throws {
        let diagnostic = try typecheckFailure(named: "Noncopyable Call.swift")

        #expect(diagnostic.contains("Call"))
        #expect(diagnostic.contains("conform to 'Copyable'"))
    }

    @Test
    func `call cannot carry nonescapable input while deriving stored prisms`() throws {
        let diagnostic = try typecheckFailure(
            named: "Nonescapable Call.swift"
        )

        #expect(diagnostic.contains("ScopedToken"))
        #expect(diagnostic.contains("Escapable"))
    }

    @Test
    func `signature rejects inout state transitions`() throws {
        let diagnostic = try typecheckFailure(named: "Inout Interface.swift")

        #expect(diagnostic.contains("owned value, not a state transition"))
    }

    @Test
    func `native Sendable rejects unsafe closure captures`() throws {
        let diagnostic = try typecheckFailure(named: "Non Sendable Capture.swift")
        #expect(diagnostic.contains("non-Sendable"))
        #expect(diagnostic.contains("reference"))
    }

    private func typecheckFailure(named name: String) throws -> String {
        var products = Bundle.module.bundleURL
        while !FileManager.default.fileExists(
            atPath: products.appendingPathComponent("Interface_Macro.swiftmodule").path
        ) {
            let parent = products.deletingLastPathComponent()
            products = try #require(parent != products ? parent : nil)
        }
        let fixture = Bundle.module.resourceURL!
            .appendingPathComponent("Fixtures")
            .appendingPathComponent(name)
        let process = Process()
        let standardError = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = [
            "swiftc",
            "-enable-upcoming-feature", "MemberImportVisibility",
            "-warnings-as-errors",
            "-typecheck",
            "-swift-version", "6",
            "-enable-experimental-feature", "Lifetimes",
            "-enable-experimental-feature", "MoveOnlyTuples",
            "-module-name", "Proof",
            "-I", products.path,
            "-I", products.appendingPathComponent("Modules").path,
            "-F", products.appendingPathComponent("PackageFrameworks").path,
        ] + [
            "Interface Macro Plugin#Interface_Macro_Plugin",
            "Product Macro Plugin#Product_Macro_Plugin",
            "Structural Macro Plugin#Structural_Macro_Plugin",
            "Operation Macro Plugin#Operation_Macro_Plugin",
            "Prism Macro Plugin#Prism_Macro_Plugin",
            "Fold Macro Plugin#Fold_Macro_Plugin",
            "Case Macro Plugin#Case_Macro_Plugin",
            "Eliminator Macro Plugin#Eliminator_Macro_Plugin",
        ].flatMap { plugin in
            [
                "-Xfrontend", "-load-plugin-executable",
                "-Xfrontend", products.appendingPathComponent(plugin).path,
            ]
        } + [
            fixture.path,
        ]
        process.standardError = standardError
        try process.run()
        process.waitUntilExit()
        let diagnostic = String(
            decoding: standardError.fileHandleForReading.readDataToEndOfFile(),
            as: UTF8.self
        )

        #expect(process.terminationStatus != 0, "Fixture unexpectedly typechecked")
        #expect(!diagnostic.contains("no such module"), "Compiler fixture could not load its modules")
        return diagnostic
    }
}
