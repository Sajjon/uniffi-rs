# Swift typed throws fixture

Explicitly opts in while the existing Swift fixtures retain their defaults.
Run with `cargo test -p uniffi-fixture-swift-typed-throws`, and repeat with
`UNIFFI_TEST_SWIFT_VERSION=6` to select Swift 6 language mode.

Covers exact typed synchronous/asynchronous function assignments, successful
calls, both domain variants, reported panic recovery, callback error transport,
constructors and methods, and a custom lift throwing the declared domain error
without being classified as a Rust failure.

The language-mode environment variable does not select a compiler. The old
compiler fallback still requires running this fixture with actual older Swift
toolchains. Broader compiler and cross-module validation remains outstanding.
