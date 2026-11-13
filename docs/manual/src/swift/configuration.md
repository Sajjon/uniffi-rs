# Configuration

The generated Swift module can be configured using a `uniffi.toml` configuration file.

## Available options

The configurations prefixed with `experimental_` should be regarded as unstable and
more likely to change than other configurations.

| Configuration name                   | Default                  | Description                                                                                                                                                                                                 |
| ------------------------------------ | ------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `cdylib_name`                        | `uniffi_{namespace}`[^1] | The name of the compiled Rust library containing the FFI implementation (not needed when using `generate --library`).                                                                                       |
| `module_name`                        | `{namespace}`[^1]        | The name of the Swift module containing the high-level foreign-language bindings.                                                                                                                           |
| `ffi_module_name`                    | `{module_name}FFI`       | The name of the lower-level C module containing the FFI declarations.                                                                                                                                       |
| `ffi_module_filename`                | `{ffi_module_name}`      | The filename stem for the lower-level C module containing the FFI declarations.                                                                                                                             |
| `generate_module_map`                | `true`                   | Whether to generate a `.modulemap` file for the lower-level C module with FFI declarations. (ignored by `uniffi-bindgen-swift`)                                                                             |
| `experimental_typed_throws`          | `false`                  | Generate typed throwing APIs in a crate-specific error namespace on Swift 6 compilers. See [experimental typed throws](#experimental-typed-throws). |
| `omit_argument_labels`               | `false`                  | Whether to omit argument labels in Swift function definitions.                                                                                                                                              |
| `generate_immutable_records`         | `false`                  | Whether to generate records with immutable fields (`let` instead of `var`).                                                                                                                                 |
| `mutable_records`                    | `[]`                     | A list of record names that should remain mutable (`var`) even when `generate_immutable_records` is `true`.                                                                                                 |
| `custom_types`                       |                          | A map which controls how custom types are exposed to Swift. See the [custom types section of the manual](../types/custom_types.md#custom-types-in-the-bindings-code)                                        |
| `rename`                             |                          | A map to rename types, functions, methods, and their members in the generated Swift bindings. See the [renaming section](../renaming.md).                                                                   |
| `omit_localized_error_conformance`   | `false`                  | Whether to make generated error types conform to `LocalizedError`.                                                                                                                                          |
| `generate_case_iterable_conformance` | `false`                  | Whether to make simple generated enum and error types conform to `CaseIterable`.                                                                                                                            |
| `generate_codable_conformance`       | `false`                  | Whether to make generated record, enum and error types conform to `Codable`.                                                                                                                                |
| `omit_checksums`                     | `false`                  | Whether to omit checking the library checksums as the library is initialized. Changing this will shoot yourself in the foot if you mixup your build pipeline in any way, but might speed up initialization. |
| `link_frameworks`                    | `[]`                     | The extra frameworks to link this binary against, such as `CoreBluetooth` or `CoreAudio`. Usually only used for interacting with native platform libraries.                                                 |

[^1]: `namespace` is the top-level namespace from your UDL file.

## Example

```toml
[bindings.swift]
cdylib_name = "mycrate_ffi"
omit_argument_labels = true
```

### Experimental typed throws

Set `experimental_typed_throws = true` in `[bindings.swift]` to generate
`throws(MyCrateErrors.CallError<YourError>)` for Rust APIs returning `Result`.
The default is `false`. Nonthrowing APIs remain nonthrowing. The namespace is
derived from the Rust crate name: `my_crate` becomes `MyCrateErrors`.

The generated source uses complete declarations guarded by `#if compiler(>=6.0)`.
Swift 6 compilers enable typed throws in both Swift 5 and Swift 6 language modes;
older compilers use the legacy untyped API. This does not raise deployment targets.

On the typed branch, migrate domain-error catches to the wrapper. Casting the
outer error directly to the Rust domain error no longer succeeds; extract its
`.library` value instead. `localizedDescription` forwards to the underlying
library, runtime, or unexpected error. For a Rust crate named `my_crate`:

```swift
do {
    let result = try lookup()
    print(result)
} catch .library(let failure) {
    print("Rust library failure: \(failure)")
} catch {
    switch error {
    case .library(let failure): print(failure)
    case .binding(let failure): reportBindingFailure(failure)
    }
}

func reportBindingFailure(_ failure: MyCrateErrors.BindingError) {
    switch failure {
    case .runtime(let runtime): print(runtime)
    case .unexpected(let underlying): print(underlying)
    }
}
```

`library` contains only a successfully decoded Rust error. `binding.runtime`
contains recognized buffer, handle, status, and reported Rust panic failures;
a panic can originate in library code. `binding.unexpected` preserves the original
Swift error, including errors thrown by custom conversions, even when their type
matches the declared Rust error. These enums are not frozen. The wrapper types
live in a namespace derived from the Rust crate name (`MyCrateErrors` here). Generation fails if that namespace conflicts with a
generated user type; rename that type using the `rename` configuration.

Opted-in callback and trait implementations must use the same typed signature.
Throw `.library(yourError)` for a Rust domain failure or `.binding(...)` for a
binding failure. Only the library case is serialized as the declared Rust error;
binding failures cross the callback transport as diagnostic strings. Swift error
identity and classification do not survive that round trip.

Each crate owns distinct wrapper types in its own namespace, including when
generated files share a Swift module. Private errors from external
converters are preserved as unexpected errors rather than identified by their
text. Changing this setting requires regenerating source, migrating callback
conformances, and rebuilding Swift modules. Libraries distributing generated
source expose different APIs depending on compiler capability; clients supporting
both branches must guard their catch patterns accordingly. Compiler version alone
does not reveal whether a library opted in. No cross-mode Swift binary
compatibility is promised. Cancellation behavior is unchanged.

Trait objects exported with `with_foreign` are not supported as error types by
the existing Swift error converter. Enabling typed throws reports a generation
error for this case rather than producing an invalid generic error signature.
