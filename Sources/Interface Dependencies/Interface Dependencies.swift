import Dependencies
public import Interface_Macro
import IssueReporting

@attached(member, names: named(testValue))
public macro Unimplemented(streams: Unimplemented.Streams) = #externalMacro(module: "Interface_Macro_Plugin", type: "Unimplemented")

/// Every use reports an issue. Only explicitly supported output shapes have
/// fallback values; arbitrary domain values and typed errors are never invented.
public enum Unimplemented: Factory {
    public enum Streams { case finished }
    private struct Failure: Error {}

    public static func value<Output: ~Copyable, Failure: Error>(
        output: Output.Type, failure: Failure.Type, operation: String
    ) throws(Failure) -> Output {
        reportIssue("Unimplemented interface operation: \(operation)")
        if let error = Unimplemented.Failure() as? Failure { throw error }
        fatalError("Provide an explicit test implementation for \(operation); no lawful fallback exists")
    }

    public static func value<Failure: Error>(output: Void.Type, failure: Failure.Type, operation: String) throws(Failure) {
        reportIssue("Unimplemented interface operation: \(operation)")
    }

    public static func value<Element>(
        output: AsyncThrowingStream<Element, any Error>.Type, failure: Never.Type, operation: String
    ) -> AsyncThrowingStream<Element, any Error> {
        reportIssue("Unimplemented interface operation: \(operation)")
        return AsyncThrowingStream { $0.finish() }
    }

    public static func value<Element>(
        output: AsyncStream<Element>.Type, failure: Never.Type, operation: String
    ) -> AsyncStream<Element> {
        reportIssue("Unimplemented interface operation: \(operation)")
        return AsyncStream { $0.finish() }
    }
}
