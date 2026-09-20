/// Interpret a canonical operation product with a family of implementations.
/// The overloads let the compiler select known result shapes without reflecting
/// values, fabricating domain records, or requiring operation results to copy.
public protocol Factory: SendableMetatype {
    static func value<Output: ~Copyable, Failure: Error>(
        output: Output.Type, failure: Failure.Type, operation: String
    ) throws(Failure) -> Output
    static func value<Failure: Error>(
        output: Void.Type, failure: Failure.Type, operation: String
    ) throws(Failure)
    static func value<Element>(
        output: AsyncThrowingStream<Element, any Error>.Type, failure: Never.Type, operation: String
    ) -> AsyncThrowingStream<Element, any Error>
    static func value<Element>(
        output: AsyncStream<Element>.Type, failure: Never.Type, operation: String
    ) -> AsyncStream<Element>
}

public protocol Constructible {
    static func _makeInterface<Implementation: Factory>(_ factory: Implementation.Type) -> Self
}
