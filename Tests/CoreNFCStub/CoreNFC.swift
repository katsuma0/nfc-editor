// Stub of the parts of Core NFC this app uses, for type-checking on Linux only.
import Foundation

public let NFCErrorDomain = "NFCError"

public struct NFCReaderError: Error, Hashable {
    public enum Code: Int {
        case readerErrorUnsupportedFeature = 1
        case readerErrorSecurityViolation = 2
        case readerErrorInvalidParameter = 3
        case readerErrorInvalidParameterLength = 4
        case readerErrorParameterOutOfBound = 5
        case readerErrorRadioDisabled = 6
        case readerTransceiveErrorTagConnectionLost = 100
        case readerTransceiveErrorRetryExceeded = 101
        case readerTransceiveErrorTagResponseError = 102
        case readerTransceiveErrorSessionInvalidated = 103
        case readerTransceiveErrorTagNotConnected = 104
        case readerTransceiveErrorPacketTooLong = 105
        case readerSessionInvalidationErrorUserCanceled = 200
        case readerSessionInvalidationErrorSessionTimeout = 201
        case readerSessionInvalidationErrorSessionTerminatedUnexpectedly = 202
        case readerSessionInvalidationErrorSystemIsBusy = 203
        case readerSessionInvalidationErrorFirstNDEFTagRead = 204
        case tagCommandConfigurationErrorInvalidParameters = 300
        case ndefReaderSessionErrorTagNotWritable = 400
        case ndefReaderSessionErrorTagUpdateFailure = 401
        case ndefReaderSessionErrorTagSizeTooSmall = 402
        case ndefReaderSessionErrorZeroLengthMessage = 403
    }
    public var code: Code
    public var localizedDescription: String { "NFCReaderError \(code.rawValue)" }
    public init(_ code: Code) { self.code = code }
    public static var readerSessionInvalidationErrorUserCanceled: Code { .readerSessionInvalidationErrorUserCanceled }
    public static var readerSessionInvalidationErrorSessionTimeout: Code { .readerSessionInvalidationErrorSessionTimeout }
    public static var readerTransceiveErrorTagResponseError: Code { .readerTransceiveErrorTagResponseError }
    public static var readerTransceiveErrorTagConnectionLost: Code { .readerTransceiveErrorTagConnectionLost }
}

public enum NFCTypeNameFormat: UInt8 {
    case empty = 0, nfcWellKnown = 1, media = 2, absoluteURI = 3, nfcExternal = 4, unknown = 5, unchanged = 6
}

public enum NFCNDEFStatus: UInt {
    case notSupported = 1, readWrite = 2, readOnly = 3
}

public enum NFCMiFareFamily: UInt {
    case unknown = 1, ultralight = 2, plus = 3, desfire = 4
}

public enum NFCFeliCaPollingRequestCode: Int {
    case noRequest = 0, systemCode = 1, communicationPerformance = 2
}

public enum NFCFeliCaPollingTimeSlot: Int {
    case max1 = 0, max2 = 1, max4 = 3, max8 = 7, max16 = 15
}

public struct NFCISO15693RequestFlag: OptionSet {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }
    public static let dualSubCarriers = NFCISO15693RequestFlag(rawValue: 1 << 0)
    public static let highDataRate = NFCISO15693RequestFlag(rawValue: 1 << 1)
    public static let protocolExtension = NFCISO15693RequestFlag(rawValue: 1 << 3)
    public static let select = NFCISO15693RequestFlag(rawValue: 1 << 4)
    public static let address = NFCISO15693RequestFlag(rawValue: 1 << 5)
    public static let option = NFCISO15693RequestFlag(rawValue: 1 << 6)
    public static let commandSpecificBit8 = NFCISO15693RequestFlag(rawValue: 1 << 7)
}

public final class NFCNDEFPayload {
    public var typeNameFormat: NFCTypeNameFormat
    public var type: Data
    public var identifier: Data
    public var payload: Data
    public init(format: NFCTypeNameFormat, type: Data, identifier: Data, payload: Data) {
        self.typeNameFormat = format; self.type = type; self.identifier = identifier; self.payload = payload
    }
    public static func wellKnownTypeURIPayload(url: URL) -> NFCNDEFPayload? { nil }
    public static func wellKnownTypeURIPayload(string: String) -> NFCNDEFPayload? { nil }
    public static func wellKnownTypeTextPayload(string: String, locale: Locale) -> NFCNDEFPayload? { nil }
}

public final class NFCNDEFMessage {
    public var records: [NFCNDEFPayload]
    public var length: Int { 0 }
    public init(records: [NFCNDEFPayload]) { self.records = records }
    public init?(data: Data) { records = [] }
}

public final class NFCISO7816APDU {
    public var instructionClass: UInt8
    public var instructionCode: UInt8
    public var p1Parameter: UInt8
    public var p2Parameter: UInt8
    public var data: Data?
    public var expectedResponseLength: Int
    public init(instructionClass: UInt8, instructionCode: UInt8, p1Parameter: UInt8, p2Parameter: UInt8, data: Data, expectedResponseLength: Int) {
        self.instructionClass = instructionClass; self.instructionCode = instructionCode; self.p1Parameter = p1Parameter; self.p2Parameter = p2Parameter; self.data = data; self.expectedResponseLength = expectedResponseLength
    }
    public init?(data: Data) {
        guard data.count >= 4 else { return nil }
        instructionClass = data[0]; instructionCode = data[1]; p1Parameter = data[2]; p2Parameter = data[3]; self.data = nil; expectedResponseLength = -1
    }
}

public protocol NFCNDEFTag: AnyObject {
    var isAvailable: Bool { get }
    func queryNDEFStatus() async throws -> (NFCNDEFStatus, Int)
    func readNDEF() async throws -> NFCNDEFMessage
    func writeNDEF(_ message: NFCNDEFMessage) async throws
    func writeLock() async throws
}

public protocol NFCMiFareTag: NFCNDEFTag {
    var mifareFamily: NFCMiFareFamily { get }
    var identifier: Data { get }
    var historicalBytes: Data? { get }
    func sendMiFareCommand(commandPacket: Data) async throws -> Data
    func sendMiFareISO7816Command(_ apdu: NFCISO7816APDU) async throws -> (Data, UInt8, UInt8)
}

public protocol NFCISO7816Tag: NFCNDEFTag {
    var identifier: Data { get }
    var historicalBytes: Data? { get }
    var applicationData: Data? { get }
    var initialSelectedAID: String { get }
    var proprietaryApplicationDataCoding: Bool { get }
    func sendCommand(apdu: NFCISO7816APDU) async throws -> (Data, UInt8, UInt8)
}

public protocol NFCISO15693Tag: NFCNDEFTag {
    var identifier: Data { get }
    var icManufacturerCode: Int { get }
    var icSerialNumber: Data { get }
    func getSystemInfo(requestFlags: NFCISO15693RequestFlag, completionHandler: @escaping (Int, Int, Int, Int, Int, (any Error)?) -> Void)
    func readSingleBlock(requestFlags: NFCISO15693RequestFlag, blockNumber: UInt8) async throws -> Data
    func readMultipleBlocks(requestFlags: NFCISO15693RequestFlag, blockRange: NSRange) async throws -> [Data]
    func writeSingleBlock(requestFlags: NFCISO15693RequestFlag, blockNumber: UInt8, dataBlock: Data) async throws
    func lockBlock(requestFlags: NFCISO15693RequestFlag, blockNumber: UInt8) async throws
    func customCommand(requestFlags: NFCISO15693RequestFlag, customCommandCode: Int, customRequestParameters: Data) async throws -> Data
    func extendedReadSingleBlock(requestFlags: NFCISO15693RequestFlag, blockNumber: Int, completionHandler: @escaping (Data, (any Error)?) -> Void)
    func extendedReadMultipleBlocks(requestFlags: NFCISO15693RequestFlag, blockRange: NSRange, completionHandler: @escaping ([Data], (any Error)?) -> Void)
    func extendedWriteSingleBlock(requestFlags: NFCISO15693RequestFlag, blockNumber: Int, dataBlock: Data, completionHandler: @escaping ((any Error)?) -> Void)
    func extendedLockBlock(requestFlags: NFCISO15693RequestFlag, blockNumber: Int, completionHandler: @escaping ((any Error)?) -> Void)
    func getMultipleBlockSecurityStatus(requestFlags: NFCISO15693RequestFlag, blockRange: NSRange, completionHandler: @escaping ([NSNumber], (any Error)?) -> Void)
    func extendedGetMultipleBlockSecurityStatus(requestFlags: NFCISO15693RequestFlag, blockRange: NSRange, completionHandler: @escaping ([NSNumber], (any Error)?) -> Void)
    func writeAFI(requestFlags: NFCISO15693RequestFlag, afi: UInt8, completionHandler: @escaping ((any Error)?) -> Void)
    func lockAFI(requestFlags: NFCISO15693RequestFlag, completionHandler: @escaping ((any Error)?) -> Void)
    func writeDSFID(requestFlags: NFCISO15693RequestFlag, dsfid: UInt8, completionHandler: @escaping ((any Error)?) -> Void)
    func lockDFSID(requestFlags: NFCISO15693RequestFlag, completionHandler: @escaping ((any Error)?) -> Void)
    func stayQuiet() async throws
    func select(requestFlags: NFCISO15693RequestFlag) async throws
    func resetToReady(requestFlags: NFCISO15693RequestFlag) async throws
}

public protocol NFCFeliCaTag: NFCNDEFTag {
    var currentSystemCode: Data { get }
    var currentIDm: Data { get }
    func polling(systemCode: Data, requestCode: NFCFeliCaPollingRequestCode, timeSlot: NFCFeliCaPollingTimeSlot) async throws -> (Data, Data)
    func requestSystemCode() async throws -> [Data]
    func sendFeliCaCommand(commandPacket: Data) async throws -> Data
    func readWithoutEncryption(serviceCodeList: [Data], blockList: [Data]) async throws -> (Int, Int, [Data])
    func writeWithoutEncryption(serviceCodeList: [Data], blockList: [Data], blockData: [Data]) async throws -> (Int, Int)
    func requestService(nodeCodeList: [Data]) async throws -> [Data]
    func requestResponse() async throws -> Int
}

public enum NFCTag {
    case feliCa(any NFCFeliCaTag)
    case iso7816(any NFCISO7816Tag)
    case iso15693(any NFCISO15693Tag)
    case miFare(any NFCMiFareTag)
}

public class NFCReaderSession: NSObject {
    public var alertMessage: String = ""
    public var isReady: Bool { true }
    public func begin() {}
    public func invalidate() {}
    public func invalidate(errorMessage: String) {}
}

public protocol NFCTagReaderSessionDelegate: AnyObject {
    func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession)
    func tagReaderSession(_ session: NFCTagReaderSession, didInvalidateWithError error: any Error)
    func tagReaderSession(_ session: NFCTagReaderSession, didDetect tags: [NFCTag])
}

public final class NFCTagReaderSession: NFCReaderSession {
    public struct PollingOption: OptionSet {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let iso14443 = PollingOption(rawValue: 1 << 0)
        public static let iso15693 = PollingOption(rawValue: 1 << 1)
        public static let iso18092 = PollingOption(rawValue: 1 << 2)
        public static let pace = PollingOption(rawValue: 1 << 3)
    }
    public class var readingAvailable: Bool { false }
    public var connectedTag: NFCTag? { nil }
    public init?(pollingOption: PollingOption, delegate: any NFCTagReaderSessionDelegate, queue: DispatchQueue?) { super.init() }
    public func restartPolling() {}
    public func connect(to tag: NFCTag) async throws {}
    public var sessionQueue: DispatchQueue { DispatchQueue.main }
}
