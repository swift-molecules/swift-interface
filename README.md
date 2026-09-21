# Interface

`@Interface` assembles a finite operation signature and its child interfaces into an
implementation product and a call coproduct. It derives the connections between
those representations; it does not define assessment, persistence, UI, defaults,
or test-fallback policy.

## Ownership

- Operation derives named symbols with Input, Output, Failure, and Application.
- Product derives implementation storage and construction. Child coordinates are
  mutable value coordinates in pure-child and mixed products alike.
- Coproduct derives elimination; Optic derives projections and injections.
- Interface connects symbols to implementation coordinates and call cases. Direct
  calls and dispatched calls share the symbol's execution witness.
- Finite and Representable derive explicitly selected input capabilities.
- Interface Dependencies owns optional unimplemented fallback functions. No core
  construction protocol knows Void or stream fallback policies.

## Execution

Call a declared operation directly for its precise output and effects. A typed
Application can run on an implementation through Operation.Operable; that generic
boundary is async throws. A heterogeneous Call is eliminated into a result chosen
by its consumer. Its standard run interpreter discards results deliberately.
There is no generated Evaluation family or second evaluation dispatcher.

## Explicit input capabilities

```swift
@Interface(inputConformances: ["Swift.Hashable", "Swift.Sendable"])
struct Service: Service.Interface {
    protocol Interface { func lookup(_ id: Int) -> String }
}
```

`inputAttributes` forwards explicitly requested leaf derivations, for example
`"@Finite"` or `"@Representable"`. Their implementation and eligibility checks stay
with their owners. Equivalent spellings of an input type do not activate different
Interface policies. Swift checks declared conformances. A separately used
`@Operations` remains independent of Interface and has no composed mode.

Child defaults belong in an explicit initializer selecting child implementations.
A product's existence does not imply a preferred element of each factor.

## Migration

Replace leaf evaluate calls with direct operations or typed Application.run(on:).
For arbitrary calls, use Call.Eliminator with a consumer-selected result. Replace
Interface.WritableMember and writablePath with Interface.Member and path. Remove
nested @Operations from Interface declarations and forward capabilities through
Interface's explicit input arguments. Replace @Interface(defaults: true) with
explicit domain assembly. Unimplemented test dependencies explicitly construct
implementations in their integration layer; the core emits no factory hook.

The representation preserves existing Call case identities, primary Input/Output/
Failure aliases, and explicit generic dispatch effect widening. Compiler-specific
macro placement remains a Swift representation constraint, not domain semantics.
