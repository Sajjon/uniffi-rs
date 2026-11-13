# Swift typed throws implementation and validation

The implementation follows the selected two-level error design in
[the plan](swift-typed-throws-plan.md). The feature remains experimental; the
complete release acceptance matrix has not been established.

## Implementation decisions

- `experimental_typed_throws` is a default-false boolean. Both Swift generation
  routes use the shared configuration and templates.
- Complete callable declarations and protocol requirements select typed throws
  using `compiler(>=6.0)`. Converter signatures stay untyped.
- Public support types are nonfrozen. Their names gain trailing underscores if
  they collide with a generated user type, using the Swift type oracle.
- Successfully decoded Rust errors receive a private provenance marker. The
  public boundary catches that marker, rather than guessing from the error's
  Swift type. All other errors map through the nongeneric binding error.
- Recognized internal failures map explicitly to public runtime cases, retaining
  panic messages and localized descriptions. Other errors retain their values.
- Constructors wrap handle acquisition before delegating to initialization.
  Async calls retain the existing future-freeing `defer` and continuation logic.
- Callback library errors are unwrapped before the existing error transport;
  binding errors use unexpected-error transport. Argument conversion errors are
  classified separately. The wire format and its diagnostic-only limitation are
  unchanged.
- External converter errors that cannot be recognized locally remain unexpected.
  There is no new shared cross-module runtime package.

## Local evidence (2026-11-13)

The machine has Apple Swift 6.4 in both installed Xcode toolchains. Rust 1.96.0
was selected explicitly because the repository-pinned Rust 1.99.0 was not
installed. Dependency downloads and Swift's module cache required execution
outside the filesystem sandbox.

- Generator suite with `--include-ignored`: 144 unit tests and 17 doc tests
  passed, including the Swift-dependent helper test.
- The isolated opt-in fixture passed on Swift 6.4 in language modes 5 and 6.
  It checks exact typed function assignments, negative compilation for an
  incompatible error and callback signature, sync/async success and failure,
  associated-data and unit domain variants, caught panic, object errors,
  sync/async callback transport, constructors/methods, and a custom lift throwing
  the declared domain-error type without being treated as a Rust failure.
- The helper seam checks all internal runtime cases, successful calls, domain
  provenance, and unexpected error identity preservation.
- Omitted and false configuration produce identical output; invalid boolean
  types are rejected; enabling the flag leaves the tested C header unchanged.
  A temporary renderer probe compared representative default Swift output
  (functions, error enum, callback protocol) against the original committed
  templates byte-for-byte: identical. The original templates and probe were
  restored/removed after comparison.
- The default Swift suite reached generated-source compilation, then all 21
  tests failed at linking with unresolved Rust FFI symbols. No claim is made that
  these tests pass or that this linker problem predates the change.
- The Docker executable is present, but its daemon socket is absent. The full
  multi-language Docker suite could not run.

## Remaining release gates

Run the original plan's matrix on real older supported Swift compilers, Swift
5.10, and Swift 6.0. Establish the actual oldest supported compiler. A language
mode switch is not a substitute. Resolve or baseline the default-suite linker
failure and run the complete multi-language suite. Broaden the disabled-output baseline comparison to additional fixtures and C
headers/module maps and other languages. Broaden coverage for mixed-config
external modules, flat/renamed errors, borrowed bytes, named constructors,
foreign-implementable traits and mocks, injected malformed wire data/status,
and measured exactly-once async cleanup. Explicit mapping of externally exposed
runtime errors, where available, also remains to be covered.

This change is not evidence that those remaining acceptance gates have passed.
