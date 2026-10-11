import Foundation
import CoreNFC

enum NFCEditorError: LocalizedError, Equatable {
    case nfcUnavailable
    case cancelled
    case timeout
    case tagLost
    case multipleTags
    case unsupportedTag(String)
    case notNDEFFormatted
    case readOnly
    case capacityExceeded(needed: Int, capacity: Int)
    case nak(UInt8?)
    case authenticationFailed
    case invalidInput(String)
    case notSupportedOnChip(String)
    case commandFailed(String)
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .nfcUnavailable:
            return "NFC is not available on this device."
        case .cancelled:
            return "Cancelled."
        case .timeout:
            return "The session timed out. Try again."
        case .tagLost:
            return "The tag was lost. Hold it steady and try again."
        case .multipleTags:
            return "More than one tag found. Present only one tag."
        case .unsupportedTag(let reason):
            return "This tag is not supported. " + NFCEditorError.sentence(reason)
        case .notNDEFFormatted:
            return "This tag is not NDEF formatted. Use Format memory in Tools first."
        case .readOnly:
            return "This tag is read only."
        case .capacityExceeded(let needed, let capacity):
            if needed <= 0 || capacity <= 0 {
                return "The data does not fit on this tag."
            }
            return "The data needs \(needed) bytes but the tag holds \(capacity) bytes."
        case .nak(let code):
            if let code = code {
                return "The tag refused the command (NAK 0x\(code.hex))."
            }
            return "The tag refused the command."
        case .authenticationFailed:
            return "The password was not accepted."
        case .invalidInput(let message):
            return NFCEditorError.sentence(message)
        case .notSupportedOnChip(let reason):
            return "This chip does not support that. " + NFCEditorError.sentence(reason)
        case .commandFailed(let message):
            return NFCEditorError.sentence(message)
        case .failed(let message):
            return NFCEditorError.sentence(message)
        }
    }

    var isCancellation: Bool {
        if case .cancelled = self {
            return true
        }
        return false
    }

    /// Maps any Error (NFCReaderError codes, NFCEditorError passthrough, others) to NFCEditorError.
    static func map(_ error: Error) -> NFCEditorError {
        if let own = error as? NFCEditorError {
            return own
        }
        if error is CancellationError {
            return .cancelled
        }
        if let reader = error as? NFCReaderError {
            return map(code: reader.code, fallback: reader.localizedDescription)
        }
        let nsError = error as NSError
        if nsError.domain == NFCErrorDomain, let code = NFCReaderError.Code(rawValue: nsError.code) {
            return map(code: code, fallback: nsError.localizedDescription)
        }
        return .failed(error.localizedDescription)
    }

    private static func map(code: NFCReaderError.Code, fallback: String) -> NFCEditorError {
        switch code {
        case .readerSessionInvalidationErrorUserCanceled:
            return .cancelled
        case .readerSessionInvalidationErrorSessionTimeout:
            return .timeout
        case .readerTransceiveErrorTagConnectionLost,
             .readerTransceiveErrorRetryExceeded,
             .readerTransceiveErrorSessionInvalidated,
             .readerTransceiveErrorTagNotConnected,
             .readerSessionInvalidationErrorSessionTerminatedUnexpectedly:
            return .tagLost
        case .readerTransceiveErrorTagResponseError:
            return .nak(nil)
        case .ndefReaderSessionErrorTagNotWritable:
            return .readOnly
        case .ndefReaderSessionErrorTagSizeTooSmall:
            return .capacityExceeded(needed: 0, capacity: 0)
        case .ndefReaderSessionErrorZeroLengthMessage:
            return .invalidInput("Nothing to write.")
        case .readerErrorUnsupportedFeature,
             .readerSessionInvalidationErrorSystemIsBusy,
             .readerErrorRadioDisabled:
            return .nfcUnavailable
        case .readerErrorSecurityViolation:
            return .failed("NFC entitlement is missing.")
        default:
            return .failed(fallback)
        }
    }

    /// Trims and makes sure a message ends with a period so every alert reads the same way.
    private static func sentence(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "Something went wrong."
        }
        if let last = trimmed.last, ".!?".contains(last) {
            return trimmed
        }
        return trimmed + "."
    }
}
