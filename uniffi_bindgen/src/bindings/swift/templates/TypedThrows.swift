{%- if config.experimental_typed_throws() %}
#if compiler(>=6.0)
/// A declared Rust failure or a failure encountered crossing the binding.
extension {{ config.error_namespace() }} {
public enum {{ config.call_error_base_name() }}<Failure: Swift.Error>: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .library(let failure): return failure.localizedDescription
        case .binding(let failure): return failure.localizedDescription
        }
    }
    case library(Failure)
    case binding({{ config.binding_error_name() }})
}

/// Binding failures retain the original Swift error when it is not recognized.
public enum {{ config.binding_error_base_name() }}: LocalizedError, CustomStringConvertible {
    public var errorDescription: String? {
        switch self {
        case .runtime(let failure): return failure.localizedDescription
        case .unexpected(let failure): return failure.localizedDescription
        }
    }
    public var description: String {
        switch self {
        case .runtime(let failure): return String(describing: failure)
        case .unexpected(let failure): return String(describing: failure)
        }
    }
    case runtime({{ config.runtime_error_name() }})
    case unexpected(any Swift.Error)
}

fileprivate struct {{ config.decoded_library_error_base_name() }}<Failure: Swift.Error>: Swift.Error {
    let failure: Failure
}
}

private func uniffiLibraryError<E: Swift.Error>(
    _ lift: @escaping (RustBuffer) throws -> E
) -> (RustBuffer) throws -> {{ config.decoded_library_error_name() }}<E> {
    { {{ config.decoded_library_error_name() }}(failure: try lift($0)) }
}

private func uniffiBindingError(_ error: any Swift.Error) -> {{ config.binding_error_name() }} {
    guard let internalError = error as? UniffiInternalError else {
        return .unexpected(error)
    }
    return .runtime(internalError)
}

private func uniffiTypedCall<T, E: Swift.Error>(
    _ failure: E.Type, _ body: () throws -> T
) throws({{ config.call_error_name() }}<E>) -> T {
    do { return try body() }
    catch let decoded as {{ config.decoded_library_error_name() }}<E> { throw .library(decoded.failure) }
    catch { throw .binding(uniffiBindingError(error)) }
}

private func uniffiTypedCall<T, E: Swift.Error>(
    _ failure: E.Type, _ body: () async throws -> T
) async throws({{ config.call_error_name() }}<E>) -> T {
    do { return try await body() }
    catch let decoded as {{ config.decoded_library_error_name() }}<E> { throw .library(decoded.failure) }
    catch { throw .binding(uniffiBindingError(error)) }
}
private func uniffiCallbackLift<T>(_ body: () throws -> T) throws -> T {
    do { return try body() }
    catch { throw uniffiBindingError(error) }
}
#else
private func uniffiCallbackLift<T>(_ body: () throws -> T) throws -> T { try body() }
private func uniffiLibraryError<E: Swift.Error>(
    _ lift: @escaping (RustBuffer) throws -> E
) -> (RustBuffer) throws -> E { lift }
#endif
{%- endif %}
