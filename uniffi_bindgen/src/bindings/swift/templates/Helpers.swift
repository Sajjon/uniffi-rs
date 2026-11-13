// An error type for FFI errors. These errors occur at the UniFFI level, not
// the library level.
fileprivate enum UniffiInternalError: LocalizedError {
    case bufferOverflow
    case incompleteData
    case unexpectedOptionalTag
    case unexpectedEnumCase
    case unexpectedNullPointer
    case unexpectedRustCallStatusCode
    case unexpectedRustCallError
    case unexpectedStaleHandle
    case rustPanic(_ message: String)

    public var errorDescription: String? {
        switch self {
        case .bufferOverflow: return "Reading the requested value would read past the end of the buffer"
        case .incompleteData: return "The buffer still has data after lifting its containing value"
        case .unexpectedOptionalTag: return "Unexpected optional tag; should be 0 or 1"
        case .unexpectedEnumCase: return "Raw enum value doesn't match any cases"
        case .unexpectedNullPointer: return "Raw pointer value was null"
        case .unexpectedRustCallStatusCode: return "Unexpected RustCallStatus code"
        case .unexpectedRustCallError: return "CALL_ERROR but no errorClass specified"
        case .unexpectedStaleHandle: return "The object in the handle map has been dropped already"
        case let .rustPanic(message): return message
        }
    }
}

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

/// Recognized runtime failures. A reported Rust panic can originate in library code.
public enum {{ config.runtime_error_name(ci) }}: LocalizedError {
    case bufferOverflow
    case incompleteData
    case unexpectedOptionalTag
    case unexpectedEnumCase
    case unexpectedNullPointer
    case unexpectedRustCallStatusCode
    case unexpectedRustCallError
    case unexpectedStaleHandle
    case rustPanic(String)

    public var errorDescription: String? {
        switch self {
        case .bufferOverflow: return UniffiInternalError.bufferOverflow.errorDescription
        case .incompleteData: return UniffiInternalError.incompleteData.errorDescription
        case .unexpectedOptionalTag: return UniffiInternalError.unexpectedOptionalTag.errorDescription
        case .unexpectedEnumCase: return UniffiInternalError.unexpectedEnumCase.errorDescription
        case .unexpectedNullPointer: return UniffiInternalError.unexpectedNullPointer.errorDescription
        case .unexpectedRustCallStatusCode: return UniffiInternalError.unexpectedRustCallStatusCode.errorDescription
        case .unexpectedRustCallError: return UniffiInternalError.unexpectedRustCallError.errorDescription
        case .unexpectedStaleHandle: return UniffiInternalError.unexpectedStaleHandle.errorDescription
        case .rustPanic(let message): return message
        }
    }
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
    switch internalError {
    case .bufferOverflow: return .runtime(.bufferOverflow)
    case .incompleteData: return .runtime(.incompleteData)
    case .unexpectedOptionalTag: return .runtime(.unexpectedOptionalTag)
    case .unexpectedEnumCase: return .runtime(.unexpectedEnumCase)
    case .unexpectedNullPointer: return .runtime(.unexpectedNullPointer)
    case .unexpectedRustCallStatusCode: return .runtime(.unexpectedRustCallStatusCode)
    case .unexpectedRustCallError: return .runtime(.unexpectedRustCallError)
    case .unexpectedStaleHandle: return .runtime(.unexpectedStaleHandle)
    case .rustPanic(let message): return .runtime(.rustPanic(message))
    }
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
