{%- if config.experimental_typed_throws() %}
#if compiler(>=6.0)
{% call swift::runtime_error_decl("public", config.runtime_error_name(ci)) %}{% endcall %}
fileprivate typealias UniffiInternalError = {{ config.runtime_error_name(ci) }}
#else
{% call swift::runtime_error_decl("fileprivate", "UniffiInternalError") %}{% endcall %}
#endif
{%- else %}
{%- call swift::runtime_error_decl("fileprivate", "UniffiInternalError") %}{% endcall %}
{%- endif %}

fileprivate extension NSLock {
    func withLock<T>(f: () throws -> T) rethrows -> T {
        self.lock()
        defer { self.unlock() }
        return try f()
    }
}

fileprivate let CALL_SUCCESS: Int8 = 0
fileprivate let CALL_ERROR: Int8 = 1
fileprivate let CALL_UNEXPECTED_ERROR: Int8 = 2
fileprivate let CALL_CANCELLED: Int8 = 3

fileprivate extension RustCallStatus {
    init() {
        self.init(
            code: CALL_SUCCESS,
            errorBuf: RustBuffer.init(
                capacity: 0,
                len: 0,
                data: nil
            )
        )
    }
}

private func rustCall<T>(_ callback: (UnsafeMutablePointer<RustCallStatus>) -> T) throws -> T {
    let neverThrow: ((RustBuffer) throws -> Never)? = nil
    return try makeRustCall(callback, errorHandler: neverThrow)
}

private func rustCallWithError<T, E: Swift.Error>(
    _ errorHandler: @escaping (RustBuffer) throws -> E,
    _ callback: (UnsafeMutablePointer<RustCallStatus>) -> T) throws -> T {
    try makeRustCall(callback, errorHandler: errorHandler)
}

private func makeRustCall<T, E: Swift.Error>(
    _ callback: (UnsafeMutablePointer<RustCallStatus>) -> T,
    errorHandler: ((RustBuffer) throws -> E)?
) throws -> T {
    {{ ensure_init_fn_name }}()
    var callStatus = RustCallStatus.init()
    let returnedVal = callback(&callStatus)
    try uniffiCheckCallStatus(callStatus: callStatus, errorHandler: errorHandler)
    return returnedVal
}

private func uniffiCheckCallStatus<E: Swift.Error>(
    callStatus: RustCallStatus,
    errorHandler: ((RustBuffer) throws -> E)?
) throws {
    switch callStatus.code {
        case CALL_SUCCESS:
            return

        case CALL_ERROR:
            if let errorHandler = errorHandler {
                throw try errorHandler(callStatus.errorBuf)
            } else {
                callStatus.errorBuf.deallocate()
                throw UniffiInternalError.unexpectedRustCallError
            }

        case CALL_UNEXPECTED_ERROR:
            // When the rust code sees a panic, it tries to construct a RustBuffer
            // with the message.  But if that code panics, then it just sends back
            // an empty buffer.
            if callStatus.errorBuf.len > 0 {
                throw UniffiInternalError.rustPanic(try {{ Type::String.borrow()|lift_fn }}(callStatus.errorBuf))
            } else {
                callStatus.errorBuf.deallocate()
                throw UniffiInternalError.rustPanic("Rust panic")
            }

        case CALL_CANCELLED:
            fatalError("Cancellation not supported yet")

        default:
            throw UniffiInternalError.unexpectedRustCallStatusCode
    }
}

private func uniffiTraitInterfaceCall<T>(
    callStatus: UnsafeMutablePointer<RustCallStatus>,
    makeCall: () throws -> T,
    writeReturn: (T) -> ()
) {
    do {
        try writeReturn(makeCall())
    } catch let error {
        callStatus.pointee.code = CALL_UNEXPECTED_ERROR
        callStatus.pointee.errorBuf = {{ Type::String.borrow()|lower_fn }}(String(describing: error))
    }
}

private func uniffiTraitInterfaceCallWithError<T, E>(
    callStatus: UnsafeMutablePointer<RustCallStatus>,
    makeCall: () throws -> T,
    writeReturn: (T) -> (),
    lowerError: (E) -> RustBuffer
) {
    do {
        try writeReturn(makeCall())
    } catch let error as E {
        callStatus.pointee.code = CALL_ERROR
        callStatus.pointee.errorBuf = lowerError(error)
    } catch {
        callStatus.pointee.code = CALL_UNEXPECTED_ERROR
        callStatus.pointee.errorBuf = {{ Type::String.borrow()|lower_fn }}(String(describing: error))
    }
}

{%- if config.experimental_typed_throws() %}
#if compiler(>=6.0)
/// A declared Rust failure or a failure encountered crossing the binding.
public enum {{ config.call_error_name(ci) }}<Failure: Swift.Error>: Swift.Error {
    case library(Failure)
    case binding({{ config.binding_error_name(ci) }})
}

/// Binding failures retain the original Swift error when it is not recognized.
public enum {{ config.binding_error_name(ci) }}: Swift.Error {
    case runtime({{ config.runtime_error_name(ci) }})
    case unexpected(any Swift.Error)
}

fileprivate struct {{ config.decoded_library_error_name(ci) }}<Failure: Swift.Error>: Swift.Error {
    let failure: Failure
}

private func uniffiLibraryError<E: Swift.Error>(
    _ lift: @escaping (RustBuffer) throws -> E
) -> (RustBuffer) throws -> {{ config.decoded_library_error_name(ci) }}<E> {
    { {{ config.decoded_library_error_name(ci) }}(failure: try lift($0)) }
}

private func uniffiBindingError(_ error: any Swift.Error) -> {{ config.binding_error_name(ci) }} {
    guard let internalError = error as? UniffiInternalError else {
        return .unexpected(error)
    }
    return .runtime(internalError)
}

private func uniffiTypedCall<T, E: Swift.Error>(
    _ failure: E.Type, _ body: () throws -> T
) throws({{ config.call_error_name(ci) }}<E>) -> T {
    do { return try body() }
    catch let decoded as {{ config.decoded_library_error_name(ci) }}<E> { throw .library(decoded.failure) }
    catch { throw .binding(uniffiBindingError(error)) }
}

private func uniffiTypedCall<T, E: Swift.Error>(
    _ failure: E.Type, _ body: () async throws -> T
) async throws({{ config.call_error_name(ci) }}<E>) -> T {
    do { return try await body() }
    catch let decoded as {{ config.decoded_library_error_name(ci) }}<E> { throw .library(decoded.failure) }
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
