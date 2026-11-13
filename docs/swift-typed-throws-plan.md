# Plan: opt-in typed throws for Swift bindings

Status: proposed; implementation is not part of this change.

Researched on 2026-11-13 against local commit
`482095c1ba1b76a1393b582e0589e2fdc9c64b14`.

## Requirements

- Typed throws must require explicit configuration. Omitting the option or setting
  it to `false` must preserve existing generated Swift source and behavior.
- Do not increase UniFFI's minimum Swift compiler, language mode, or OS deployment
  target. Existing users must not need to change their build configuration.
- Even opted-in generated source should compile on older supported compilers,
  falling back to today's untyped declarations and behavior.
- Keep Rust metadata, UDL, scaffolding, C ABI, and other language bindings unchanged.
- Do not silently turn currently catchable failures into process termination.

## Earlier discussions and current language support

The directly relevant discussion is [issue #2179](https://github.com/mozilla/uniffi-rs/issues/2179),
opened July 5, 2024 and closed July 9 over then-current Swift support. It did not
result in a typed-throws implementation. Subsequently,
[Sajjon proposed an opt-in `experimental_typed_throws` setting and conditional declarations](https://github.com/mozilla/uniffi-rs/issues/2179#issuecomment-2248787712),
and [linabutler responded positively](https://github.com/mozilla/uniffi-rs/issues/2179#issuecomment-2249203443).
This is useful precedent, not approval of the error semantics proposed below.

[PR #2045](https://github.com/mozilla/uniffi-rs/pull/2045) is the merged historical
precedent for opt-in Swift Sendable generation mentioned in that discussion.
[PR #2452](https://github.com/mozilla/uniffi-rs/pull/2452), closed without merging,
discusses Swift version guards and uncertainty over the historical minimum
compiler. Establish the actual supported baseline before selecting CI versions.

Searches across issues and open/closed PRs for `"typed throws"`, `"typed" Swift`,
and PRs for `Swift throws` found no dedicated typed-throws implementation PR.
This is a bounded search result, not proof that no related work exists.
The broader search also found cancellation proposals
[#1768](https://github.com/mozilla/uniffi-rs/pull/1768),
[#2887](https://github.com/mozilla/uniffi-rs/pull/2887), and
[#3057](https://github.com/mozilla/uniffi-rs/pull/3057): cancellation can add an error
outside the declared Rust error type. Recheck their status when implementing;
their proposed behavior is not present in the inspected checkout.

[SE-0413](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0413-typed-throws.md)
records typed throws as implemented in Swift 6.0. The historical concern about
`FullTypedThrows` concerns additional inference work, not the availability of
explicit `throws(E)` declarations. No experimental compiler flag should be needed.

## Configuration and compatibility

Proposed configuration, following the issue's naming:

```toml
[bindings.swift]
experimental_typed_throws = true # default: false
```

Add a default-false field and accessor to
`uniffi_bindgen/src/bindings/swift/gen_swift/mod.rs::Config`. Do not detect the
generator host's Swift installation: generated code may be compiled elsewhere.

When disabled, render the current templates without new guards or support types.
When enabled, use `#if compiler(>=6.0)` around complete declarations containing
typed-throws syntax, with complete legacy declarations in `#else`. Guard typed
helper declarations too. Do not insert directives between pieces of a signature.
Share the rendering logic in Askama macros to limit drift between branches.

Use compiler capability rather than `#if swift(>=6.0)`: the latter selects the
language mode and would unnecessarily disable this feature for Swift 6 compilers
building in Swift 5 mode. Verify both modes and inactive-branch parsing on real
old compilers. `@available` cannot protect an older parser from new syntax.

| Setting | Compiler | Expected behavior |
| --- | --- | --- |
| omitted / false | every currently supported compiler | Existing untyped source and behavior |
| true | supported compiler older than 6.0 | Legacy declarations and behavior |
| true | 6.0 or newer, language mode 5 | Typed declarations |
| true | 6.0 or newer, language mode 6 | Typed declarations |

An opted-in library's public Swift API differs between compiler branches. Explain
this to library authors, including callback conformances, generated-source
distribution, and rebuilding Swift modules after changing the setting. No new
promise of Swift binary compatibility across the two modes is made.

## Resolve the error contract before implementing signatures

The current `Helpers.swift` templates can throw `UniffiInternalError`, including
Rust panics and invalid call status. Error decoding and successful return-value
lifting can throw too; custom conversion expressions may introduce other errors.
`Async.swift` has the same status/lifting paths. Simply replacing `throws` with
`throws(MyError)` is therefore unsound. An unconditional `as! MyError` is not a fix.

Recommended starting design: preserve recoverability using a generated public,
module-qualified wrapper, with a final name chosen to avoid user-type collisions:

```swift
// Illustrative API, not an implemented declaration.
public enum UniffiCallError<Failure: Swift.Error>: Swift.Error {
    case library(Failure)
    case uniffi(UniffiRuntimeError)
    case unexpected(any Swift.Error)
}
// Rust Result<Value, MyError>:
public func operation() throws(UniffiCallError<MyError>) -> Value
```

The three cases distinguish the declared library error, recognized UniFFI runtime
failures, and other propagated Swift errors. `Failure` is the library's declared
Rust error type; it does not mean every error written by application developers.
For example, a user-supplied Swift custom conversion can throw a validation error
without that error being part of the Rust `Result` contract.

| Origin | Classification |
| --- | --- |
| Successfully decoded Rust `CALL_ERROR` | `.library(decodedError)` |
| UniFFI buffer overflow, incomplete data, invalid tag/handle/status | `.uniffi(...)` |
| Rust panic reported through `CALL_UNEXPECTED_ERROR` | `.uniffi(...)`, preserving the available message |
| Custom Swift lift expression throws its own validation or SDK error | `.unexpected(originalError)` |
| External converter throws an error this module cannot recognize | `.unexpected(originalError)` |

`unexpected` means outside the declared library error and the recognized UniFFI
runtime errors, not an unknowable error. A configured lift expression such as
`try ValidatedValue(raw: {})` runs inside an untyped throwing converter and can
throw an arbitrary Swift error. The caller can still inspect or downcast the
stored error. Keep the actual error value and diagnostics, not just a string.
This escape hatch is needed by existing extension points, not merely hypothetical
future failures. No catchable error wrapper can capture `fatalError`, process
abort, or memory corruption; this feature does not promise to do so.

Classify failures where they originate: decode a Rust `CALL_ERROR` first, mapping
any decoding failure to `.uniffi` or `.unexpected`, then wrap the decoded value
as `.library`. Do not classify every error matching `Failure` as a Rust domain
failure: a custom conversion could throw the same Swift type. Successful result
lifting has the same UniFFI-versus-other distinction. Keep this wrapper entirely
on the Swift side; never serialize it as the Rust error enum.

The existing `UniffiInternalError` is `fileprivate`, so it cannot simply be used
as an associated value in this public API. Introduce an opt-in public
`UniffiRuntimeError` representation with explicit cases corresponding to the
current internal failures, and a deliberate mapping at the typed boundary.
Preserve available diagnostics and document that a reported Rust panic is not
necessarily a UniFFI bug. Keep default output and internal converter signatures
unchanged. Public case names and their evolution policy require review; do not
mark this enum `@frozen` merely to enable exhaustive client switches.

Generated modules have distinct error types. Plan explicit mappings for external
modules where their public runtime errors are available. An older or opted-out
module's private internal error cannot be reliably identified by another module;
preserve it as `.unexpected` rather than guessing from its description. Test this
mixed-configuration limitation and document it.

Prefer these three direct cases to nesting `knownUniffiFailure` and `unknown`
inside another enum. That nesting adds handling steps without additional
information, and would misleadingly label custom-conversion errors as UniFFI
failures. A two-case model remains possible if consumers need only domain versus
everything else, but it gives up a useful typed distinction already supported by
the current runtime.

This provides a concrete thrown type but differs from the original request for
exactly `throws(MyError)`. It also changes catch patterns for users who opt in.
Settle this tradeoff with maintainers before the implementation phase:

| Alternative | Consequence |
| --- | --- |
| Wrapper (recommended) | Preserves catchable failures; requires `.library(...)` handling |
| Exactly `throws(MyError)` | Requires an explicit policy for every non-domain failure; trapping changes recoverability |
| Add an unexpected case to each domain error | Changes enum shape and cannot generally extend imported/object error types |
| Keep plain `throws` | Preserves current semantics, but provides no additional static error information |

Do not add a second trap-policy flag in the first version. If maintainers require
exact domain errors, revise this plan with an explicit, documented policy and
tests before coding; do not quietly introduce traps. Existing nonthrowing APIs
remain nonthrowing with their existing behavior. Existing cancellation handling
(`CALL_CANCELLED` currently traps) is outside this feature; coordinate any future
`CancellationError` support so it cannot invalidate the chosen thrown type.

## Implementation sequence

1. **Capture the baseline and settle the API.** Generate representative fixtures
   before changing templates. Confirm wrapper naming, the three-way error mapping,
   public runtime-error cases and their evolution policy,
   callback semantics, supported compiler baseline, and the config name. Record
   these decisions in the implementation PR.
2. **Add configuration and rendering tests.** Cover omitted, false, true, and
   invalid TOML types. Require omitted/false output to match the baseline, and
   verify unchanged C headers/module maps and other language output. Confirm both
   CLI generation routes honor the same setting.
3. **Implement synchronous boundaries.** Update `templates/macros.swift`
   (`throws`, `func_decl`, `ctor_decl`, `call_body`, `to_ffi_call`) and
   `templates/Helpers.swift`. Cover free functions, methods, primary and named
   constructors, void/value returns, and borrowed byte arguments. Wrap the full
   status/decode/lift path. Retain buffer and object-handle cleanup on every exit.
4. **Implement asynchronous boundaries.** Update `templates/Async.swift` and
   `macros.swift::call_async`. Preserve future freeing through `defer`, continuation
   ownership, and exactly-once completion. Do not rely on typed throwing
   continuations or implicit closure inference; explicitly annotate typed
   closures where necessary and test with the minimum Swift 6 toolchain.
5. **Keep protocols and implementations consistent.** Audit `Protocol.swift`,
   `ObjectTemplate.swift`, `CallbackInterfaceTemplate.swift`, and
   `CallbackInterfaceImpl.swift`. Rust-facing objects and Swift implementations of
   the same generated protocol must satisfy identical signatures. Under the
   wrapper design, unwrap `.library` to `CALL_ERROR` and map both `.uniffi` and
   `.unexpected` to `CALL_UNEXPECTED_ERROR` on the callback boundary, preserving current transport
   behavior. Argument-lifting errors remain transport-level unexpected failures;
   their local Swift classification can be `.uniffi` or `.unexpected`. The existing
   unexpected-error wire format carries a diagnostic string, so arbitrary Swift
   error identity and the three-way classification do not survive a Rust round
   trip. Do not claim otherwise or change the ABI in this feature. Cover sync and
   async callbacks, foreign-implementable traits, and mocks; document the migration for
   opted-in Swift implementations. Do not alter low-level converter `throws`
   signatures unnecessarily.
6. **Document and validate.** Update `docs/manual/src/swift/configuration.md`, add
   a catching/migration example and an unreleased `CHANGELOG.md` entry. Explain
   fallback behavior, compiler versus language mode, runtime failures, and
   source compatibility. Run the matrix below before calling the feature ready.

Use existing name/type filters rather than constructing error names manually.
Include flat errors, associated-data errors, object errors, renamed/escaped
types, and errors imported from another generated module. Test modules using
different opt-in settings together; do not assume external error modules also
enable typed throws.

## Validation and acceptance criteria

Extend `bindgen-tests/swift` with an isolated opt-in fixture and retain existing
default fixtures. Reuse coverage in `fixtures/error-types`, `fixtures/callbacks`,
`fixtures/trait-methods`, and `fixtures/futures` where appropriate. Both
`bindgen-tests/swift/src/lib.rs` and `uniffi_bindgen/src/bindings/swift/test.rs`
read `UNIFFI_TEST_SWIFT_VERSION`, which selects a language mode, not a compiler.
The current Docker test image starts from Swift 6.3; it cannot alone prove
compatibility with Swift 5 compilers.

- Run on the confirmed oldest supported compiler and a real Swift 5.10 compiler
  (if distinct), with both default and enabled configuration. Verify the fallback
  API, runtime behavior, and absence of parser errors.
- Run on Swift 6.0 and a current supported Swift 6 compiler, each in language
  modes 5 and 6, with default, false, and enabled settings. Isolate and report
  pre-existing strict-concurrency failures rather than weakening checks.
- Compile a client assigning a generated function to its exact typed throwing
  function type and switching exhaustively over the error wrapper. Add a compile
  failure test for an incompatible thrown type and a callback throwing the wrong
  error. Ordinary `catch is MyError` tests do not prove typed signatures.
- Exercise success and every domain variant, malformed buffers, invalid status,
  a caught Rust panic, and a throwing custom lift. Inject malformed status/buffer
  cases at a Swift helper seam where necessary. Verify values, classification,
  and cleanup; no new crash should replace a currently catchable error.
- Specifically assert `.library` for decoded domain errors, `.uniffi` for each
  recognized internal failure, and `.unexpected` for a custom conversion's error.
  Include a custom converter throwing the same type as `Failure` to prove it does
  not become `.library`. Verify unexpected error payload preservation and the
  documented fallback for private errors from external modules.
- Cover constructors, sync/async methods and functions, callbacks and traits,
  object/external errors, and mixed-config modules. Check asynchronous resource
  release and callback completion exactly once on success and failure.
- Run Rust generator tests, the Swift bindgen suite and affected fixtures, then
  the repository's full multi-language suite in its supported environment.
  Representative commands are `cargo test -p uniffi_bindgen`,
  `cargo test -p uniffi-bindgen-tests-swift`, and
  `UNIFFI_TEST_SWIFT_VERSION=6 cargo test -p uniffi-bindgen-tests-swift`.
  Run `cargo fmt --all -- --check` and `git diff --check` before delivery.

Release gates: explicit opt-in only; unchanged default output; real old-compiler
fallback verified; typed signatures and error semantics verified on Swift 6;
unchanged FFI contract; no resource-lifetime regressions. The compiler matrix
and runtime tests above are planned work, not results claimed by this document.
