import Foundation
import uniffi_fixture_swift_typed_throws

#if compiler(>=6.0)
func typecheck(_ source: String, succeeds: Bool = false) throws {
    let directory = FileManager.default.currentDirectoryPath
    let path = directory + "/negative.swift"
    try ("import uniffi_fixture_swift_typed_throws\n" + source).write(toFile: path, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(atPath: path) }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["swiftc", "-typecheck", "-I", directory, "-Xcc",
        "-fmodule-map-file=" + directory + "/uniffi_fixture_swift_typed_throwsFFI.modulemap", path]
    let diagnostics = Pipe()
    process.standardError = diagnostics
    try process.run()
    let output = diagnostics.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    assert((process.terminationStatus == 0) == succeeds, String(decoding: output, as: UTF8.self))
    if !succeeds { assert(String(decoding: output, as: UTF8.self).contains("error:")) }
}
try typecheck("let correct: (UInt64) throws(UniffiCallError<LookupError>) -> String = lookup", succeeds: true)
try typecheck("let wrong: (UInt64) throws(LookupError) -> String = lookup")
try typecheck("final class Wrong: Lookup { func lookup(id: UInt64) throws(LookupError) -> String { throw .Unavailable } }")
let exact: (UInt64) throws(UniffiCallError<LookupError>) -> String = lookup
let found = try exact(0)
assert(found == "found")
for id: UInt64 in [1, 2, 3] {
    do {
        _ = try exact(id)
        assertionFailure("expected failure")
    } catch {
        switch error {
        case .library(let failure):
            switch failure {
            case .Missing(let missing): assert(missing == 1 && id == 1)
            case .Unavailable: assert(id == 2)
            }
        case .binding(let failure):
            guard case .runtime(.rustPanic(let message)) = failure else {
                fatalError("wrong classification: \(failure)")
            }
            assert(id == 3 && message.contains("lookup panic"))
        }
    }
}
final class Callback: Lookup {
    func lookup(id: UInt64) throws(UniffiCallError<LookupError>) -> String {
        throw .library(.Unavailable)
    }
}
do {
    _ = try invoke(callback: Callback(), id: 0)
    assertionFailure("expected callback failure")
} catch .library(.Unavailable) {
} catch { fatalError("wrong callback classification: \(error)") }
do {
    _ = try name()
    assertionFailure("expected custom conversion failure")
} catch {
    guard case .binding(.unexpected(let original)) = error,
          let failure = original as? LookupError,
          case .Unavailable = failure else { fatalError("wrong custom conversion classification") }
}
let asyncExact: (UInt64) async throws(UniffiCallError<LookupError>) -> String = lookupAsync
let asyncFound = try await asyncExact(0)
assert(asyncFound == "found")
do {
    _ = try await asyncExact(2)
    assertionFailure("expected async failure")
} catch .library(.Unavailable) {
} catch { fatalError("wrong async classification: \(error)") }
do {
    try objectFailure()
    assertionFailure("expected object error")
} catch .library(let failure) {
    assert(failure.message() == "object failure")
} catch { fatalError("wrong object error: \(error)") }
final class AsyncCallback: AsyncLookup {
    func lookup() async throws(UniffiCallError<LookupError>) -> String {
        throw .library(.Unavailable)
    }
}
do {
    _ = try await invokeAsync(callback: AsyncCallback())
    assertionFailure("expected async callback error")
} catch .library(.Unavailable) {
} catch { fatalError("wrong async callback classification: \(error)") }
let store = try Store(id: 0)
let value = try store.get(id: 0)
assert(value == "found")
#else
let found = try lookup(id: 0)
assert(found == "found")
#endif
