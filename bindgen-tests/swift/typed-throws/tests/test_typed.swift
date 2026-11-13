import Foundation
import uniffi_fixture_swift_typed_throws

#if compiler(>=6.0)
struct TypecheckFailure: Error { let message: String }

func typecheck(_ source: String, expectedDiagnostic: String? = nil) throws {
    let environment = ProcessInfo.processInfo.environment
    guard let compiler = environment["UNIFFI_TEST_SWIFTC"] else {
        fatalError("test runner must supply the compiler used to build the bindings")
    }
    let directory = FileManager.default.currentDirectoryPath
    let scratch = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: scratch) }
    let path = scratch.appendingPathComponent("client.swift")
    try ("import uniffi_fixture_swift_typed_throws\n" + source).write(to: path, atomically: true, encoding: .utf8)
    let process = Process()
    process.executableURL = URL(fileURLWithPath: compiler)
    process.arguments = ["-typecheck", "-swift-version", environment["UNIFFI_TEST_SWIFT_VERSION"] ?? "5",
        "-I", directory, "-Xcc",
        "-fmodule-map-file=" + directory + "/uniffi_fixture_swift_typed_throwsFFI.modulemap", path.path]
    let diagnostics = Pipe()
    process.standardError = diagnostics
    try process.run()
    let output = diagnostics.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    let message = String(decoding: output, as: UTF8.self)
    if let expectedDiagnostic {
        guard process.terminationStatus != 0 && message.contains(expectedDiagnostic) else {
            throw TypecheckFailure(message: message)
        }
    } else {
        guard process.terminationStatus == 0 else { throw TypecheckFailure(message: message) }
    }
}
try typecheck("let correct: (UInt64) throws(UniffiFixtureSwiftTypedThrowsErrors.CallError<LookupError>) -> String = lookup")
try typecheck("let wrong: (UInt64) throws(LookupError) -> String = lookup", expectedDiagnostic: "invalid conversion of thrown error type")
try typecheck("final class Wrong: Lookup { func lookup(id: UInt64) throws(LookupError) -> String { throw .Unavailable } }", expectedDiagnostic: "does not conform to protocol 'Lookup'")
let exact: (UInt64) throws(UniffiFixtureSwiftTypedThrowsErrors.CallError<LookupError>) -> String = lookup
let found = try exact(0)
assert(found == "found")
for id: UInt64 in [1, 2, 3] {
    do {
        _ = try exact(id)
        assertionFailure("expected failure")
    } catch {
        switch error {
        case .library(let failure):
            assert(error.localizedDescription == failure.localizedDescription)
            assert((error as any Error) as? LookupError == nil)
            switch failure {
            case .Missing(let missing): assert(missing == 1 && id == 1)
            case .Unavailable: assert(id == 2)
            }
        case .binding(let failure):
            guard case .runtime(.rustPanic(let message)) = failure else {
                fatalError("wrong classification: \(failure)")
            }
            assert(id == 3 && message.contains("lookup panic"))
            assert(error.localizedDescription == message)
        }
    }
}
final class Callback: Lookup {
    func lookup(id: UInt64) throws(UniffiFixtureSwiftTypedThrowsErrors.CallError<LookupError>) -> String {
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
struct LocalFailure: LocalizedError { var errorDescription: String? { "original Swift diagnostic" } }
let unexpected = UniffiFixtureSwiftTypedThrowsErrors.CallError<LookupError>.binding(.unexpected(LocalFailure()))
assert(unexpected.localizedDescription == "original Swift diagnostic")
let asyncExact: (UInt64) async throws(UniffiFixtureSwiftTypedThrowsErrors.CallError<LookupError>) -> String = lookupAsync
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
    func lookup() async throws(UniffiFixtureSwiftTypedThrowsErrors.CallError<LookupError>) -> String {
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
