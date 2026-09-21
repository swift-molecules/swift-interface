/// Evaluation preserves an operation's answer. Dispatch through Call.run remains
/// available for callers that intentionally discard results.
extension Interface {
    public protocol Evaluating {
        associatedtype Call: ~Copyable
        associatedtype Evaluation: ~Copyable
        func evaluate(_ call: consuming Call) async throws -> Evaluation
    }

    /// The common effects boundary used when composing independently declared children.
    /// A leaf's concrete evaluate method retains its own synchronous/throwing signature.
    public static func evaluate<Domain: Evaluating>(
        _ domain: Domain, _ call: consuming Domain.Call
    ) async throws -> Domain.Evaluation {
        try await domain.evaluate(call)
    }
}
