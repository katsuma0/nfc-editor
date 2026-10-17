import Foundation
import CoreNFC

// ISO 15693 and FeliCa command checks. Hand computed vectors: the random number 12 34 masks the
// password 11 22 33 44 as 11^12 22^34 33^12 44^34 = 03 16 21 70.
func checkType5FeliCa() {
    // MARK: Pure helpers
    checkEqual(ISO15693Commands.slixMaskPassword(hex("11223344"), random: hex("1234")), hex("03162170"), "SLIX password mask")
    checkEqual(ISO15693Commands.slixMaskPassword(hex("00000000"), random: hex("ABCD")), hex("ABCDABCD"), "SLIX mask of the default password")
    checkEqual(ISO15693Commands.lockedFlags([NSNumber(value: 0), NSNumber(value: 1), NSNumber(value: 0x02), NSNumber(value: 0x03)]), [false, true, false, true], "locked flags use bit 0")
    checkEqual(SLIXPassword.privacy.rawValue, 0x04, "SLIX privacy identifier")
    checkEqual(SLIXPassword.easAFI.rawValue, 0x10, "SLIX EAS and AFI identifier")
    checkEqual(SLIXPassword.allCases.count, 5, "five SLIX passwords")

    checkEqual(FeliCaCommands.serviceCodeData(0x000B), hex("0B00"), "FeliCa service code is little endian")
    checkEqual(FeliCaCommands.serviceCodeData(0x090F), hex("0F09"), "FeliCa Suica history service code")
    checkEqual(FeliCaCommands.blockListElement(block: 3), hex("8003"), "FeliCa two byte block list element")
    checkEqual(FeliCaCommands.blockListElement(block: 0x0102), hex("000201"), "FeliCa three byte block list element")
    checkEqual(FeliCaCommands.keyVersion(hex("FFFF")), 0xFFFF, "FeliCa absent key version")
    checkEqual(FeliCaCommands.keyVersion(hex("0100")), 0x0001, "FeliCa key version little endian")
    check(FeliCaCommands.statusError(0, 0) == nil, "FeliCa status 00 is success")
    checkEqual(FeliCaCommands.statusError(0xFF, 0xA8), NFCEditorError.commandFailed("Status 0xFF 0xA8 (block number out of range)"), "FeliCa status text")
    checkEqual(FeliCaCommands.statusError(0x01, 0x99), NFCEditorError.commandFailed("Status 0x01 0x99"), "FeliCa unknown status text")

    // MARK: ISO 15693 command sequences against a fake tag
    let tag = FakeISO15693Tag(blockCount: 300)
    var failure = runAsync {
        let pages = try await ISO15693Commands.readBlocks(tag, from: 250, to: 265, progress: nil)
        checkEqual(pages.count, 16, "read across block 255 returns every block")
        checkEqual(pages.first?.index, 250, "first block index")
        checkEqual(pages.last?.index, 265, "last block index")
        checkEqual(pages.last?.bytes, Data([0x09, 0x01, 0x00, 0x00]), "block 265 content")
        check(pages.allSatisfy { $0.readable }, "all blocks readable")
    }
    check(failure == nil, "readBlocks threw \(String(describing: failure))")
    checkEqual(tag.log, ["readMultiple 250+6", "extendedReadMultiple 256+10"], "read switches to the extended command above block 255")

    tag.log = []
    tag.multipleFails = true
    failure = runAsync {
        let pages = try await ISO15693Commands.readBlocks(tag, from: 254, to: 257, progress: nil)
        checkEqual(pages.map { $0.index }, [254, 255, 256, 257], "single block fallback indexes")
    }
    check(failure == nil, "readBlocks fallback threw \(String(describing: failure))")
    checkEqual(tag.log, ["readMultiple 254+2", "read 254", "read 255", "extendedReadMultiple 256+2", "extendedRead 256", "extendedRead 257"], "single block fallback for both command families")
    tag.multipleFails = false

    tag.log = []
    failure = runAsync {
        try await ISO15693Commands.writeBlock(tag, index: 5, bytes: hex("01020304"))
        try await ISO15693Commands.writeBlock(tag, index: 256, bytes: hex("05060708"))
        try await ISO15693Commands.lockBlock(tag, index: 7)
        try await ISO15693Commands.lockBlock(tag, index: 299)
    }
    check(failure == nil, "write and lock threw \(String(describing: failure))")
    checkEqual(tag.log, ["write 5 flags 22 01020304", "extendedWrite 256 flags 22 05060708", "lock 7 flags 22", "extendedLock 299 flags 22"], "write and lock pick the command by block index")
    checkEqual(tag.memory[256], hex("05060708"), "extended write stored")
    check(tag.locked.contains(7) && tag.locked.contains(299), "lock bits stored")
    check(runAsync { try await ISO15693Commands.writeBlock(tag, index: 70000, bytes: hex("00")) } != nil, "block above 65535 rejected")
    check(runAsync { try await ISO15693Commands.writeBlock(tag, index: 1, bytes: Data()) } != nil, "empty block rejected")

    // An ST style tag only accepts writes with the option flag; the second attempt carries it.
    tag.log = []
    tag.needsOption = true
    failure = runAsync {
        try await ISO15693Commands.writeBlock(tag, index: 9, bytes: hex("AABBCCDD"))
        try await ISO15693Commands.writeAFI(tag, afi: 0xC2)
        try await ISO15693Commands.lockAFI(tag)
        try await ISO15693Commands.writeDSFID(tag, dsfid: 0x01)
        try await ISO15693Commands.lockDSFID(tag)
    }
    check(failure == nil, "option retry threw \(String(describing: failure))")
    checkEqual(tag.log, ["write 9 flags 22 AABBCCDD", "write 9 flags 62 AABBCCDD", "writeAFI C2 flags 22", "writeAFI C2 flags 62", "lockAFI flags 22", "lockAFI flags 62", "writeDSFID 01 flags 22", "writeDSFID 01 flags 62", "lockDSFID flags 22", "lockDSFID flags 62"], "write type commands retry with the option flag")
    checkEqual(tag.afi, 0xC2, "AFI stored")
    checkEqual(tag.dsfid, 0x01, "DSFID stored")
    check(tag.afiLocked && tag.dsfidLocked, "AFI and DSFID locked")
    tag.needsOption = false

    // Security status: chunks of 32, the extended command above 255.
    tag.log = []
    tag.locked = [0, 33, 256]
    failure = runAsync {
        let flags = try await ISO15693Commands.blockSecurityStatus(tag, from: 0, to: 257)
        checkEqual(flags.count, 258, "one flag per block")
        check(flags[0] && flags[33] && flags[256] && !flags[1] && !flags[255] && !flags[257], "locked blocks reported")
    }
    check(failure == nil, "security status threw \(String(describing: failure))")
    checkEqual(tag.log, ["status 0+32", "status 32+32", "status 64+32", "status 96+32", "status 128+32", "status 160+32", "status 192+32", "status 224+32", "extendedStatus 256+2"], "security status chunks")

    tag.log = []
    tag.statusChunkLimit = 1
    failure = runAsync {
        let flags = try await ISO15693Commands.blockSecurityStatus(tag, from: 30, to: 34)
        checkEqual(flags, [false, false, false, true, false], "security status single block fallback values")
    }
    check(failure == nil, "security status fallback threw \(String(describing: failure))")
    checkEqual(tag.log, ["status 30+5", "status 30+1", "status 31+1", "status 32+1", "status 33+1", "status 34+1"], "security status falls back to single blocks")
    tag.statusChunkLimit = nil

    // SLIX: get random number first, then the masked password.
    tag.log = []
    tag.random = hex("1234")
    failure = runAsync {
        try await ISO15693Commands.slixSetPassword(tag, identifier: .privacy, password: hex("11223344"))
        try await ISO15693Commands.slixWritePassword(tag, identifier: .read, password: hex("AABBCCDD"))
        try await ISO15693Commands.slixEnablePrivacy(tag)
        try await ISO15693Commands.slixProtectPage(tag, pageNumber: 0x02, protection: 0x11)
        try await ISO15693Commands.slixSetEAS(tag)
        try await ISO15693Commands.slixResetEAS(tag)
        try await ISO15693Commands.slixLockEAS(tag)
        let alarm = try await ISO15693Commands.slixEASAlarm(tag)
        checkEqual(alarm.count, 32, "EAS alarm sequence")
        try await ISO15693Commands.slixDestroy(tag, password: hex("11223344"))
    }
    check(failure == nil, "SLIX commands threw \(String(describing: failure))")
    checkEqual(tag.log, [
        "custom B2 flags 22 ",
        "custom B3 flags 22 0403162170",
        "custom B4 flags 22 01AABBCCDD",
        "custom BA flags 22 ",
        "custom B6 flags 22 0211",
        "custom A2 flags 22 ",
        "custom A3 flags 22 ",
        "custom A4 flags 22 ",
        "custom A5 flags 22 ",
        "custom B2 flags 22 ",
        "custom B9 flags 22 03162170"
    ], "SLIX command bytes")

    tag.log = []
    tag.refuseCustom = true
    failure = runAsync {
        try await ISO15693Commands.slixSetPassword(tag, identifier: .read, password: hex("11223344"))
    }
    if case .notSupportedOnChip? = failure as? NFCEditorError {
        check(true, "SLIX set password on a tag that ignores SLIX commands says not supported")
    } else {
        check(false, "SLIX set password on a tag that ignores SLIX commands reported \(String(describing: failure))")
    }
    checkEqual(tag.log, ["custom B2 flags 22 "], "random number refused stops the password transfer")
    tag.refuseCustom = false
    tag.refuseCodes = [0xB3]
    failure = runAsync {
        try await ISO15693Commands.slixSetPassword(tag, identifier: .read, password: hex("11223344"))
    }
    checkEqual(failure as? NFCEditorError, NFCEditorError.authenticationFailed, "refused SET PASSWORD is an authentication failure")
    tag.refuseCodes = [0xA5]
    failure = runAsync {
        let alarm = try await ISO15693Commands.slixEASAlarm(tag)
        check(alarm.isEmpty, "silent EAS alarm means EAS is off")
    }
    check(failure == nil, "EAS alarm off threw \(String(describing: failure))")
    tag.refuseCodes = []
    check(runAsync { try await ISO15693Commands.slixSetPassword(tag, identifier: .read, password: hex("112233")) } != nil, "SLIX password must be 4 bytes")

    // ST25TV passwords are 8 bytes and travel in plain.
    tag.log = []
    failure = runAsync {
        try await ISO15693Commands.stPresentPassword(tag, number: 1, password: hex("0102030405060708"))
        try await ISO15693Commands.stWritePassword(tag, number: 0, password: hex("1112131415161718"))
    }
    check(failure == nil, "ST commands threw \(String(describing: failure))")
    checkEqual(tag.log, ["custom B3 flags 22 010102030405060708", "custom B1 flags 22 001112131415161718"], "ST command bytes")
    check(runAsync { try await ISO15693Commands.stPresentPassword(tag, number: 1, password: hex("01020304")) } != nil, "ST password must be 8 bytes")
    tag.refuseCodes = [0xB3]
    failure = runAsync {
        try await ISO15693Commands.stPresentPassword(tag, number: 1, password: hex("0102030405060708"))
    }
    checkEqual(failure as? NFCEditorError, NFCEditorError.authenticationFailed, "refused PRESENT PASSWORD is an authentication failure")
    tag.refuseCodes = []

    // MARK: FeliCa command sequences against a fake card
    let card = FakeFeliCaTag()
    failure = runAsync {
        let blocks = try await FeliCaCommands.readWithoutEncryption(card, serviceCode: 0x000B, blocks: Array(0...5))
        checkEqual(blocks.count, 6, "FeliCa read returns one block per request")
        checkEqual(blocks[5].first, 5, "FeliCa block content")
        check(blocks.allSatisfy { $0.count == 16 }, "FeliCa blocks are 16 bytes")
    }
    check(failure == nil, "FeliCa read threw \(String(describing: failure))")
    checkEqual(card.log, ["read 0B00 blocks 8000 8001 8002 8003", "read 0B00 blocks 8004 8005"], "FeliCa reads in chunks of four")

    card.log = []
    failure = runAsync {
        try await FeliCaCommands.writeWithoutEncryption(card, serviceCode: 0x0009, block: 2, data: Data(repeating: 0xAB, count: 16))
    }
    check(failure == nil, "FeliCa write threw \(String(describing: failure))")
    checkEqual(card.log, ["write 0900 blocks 8002 data ABABABABABABABABABABABABABABABAB"], "FeliCa write command")
    checkEqual(card.blocks[2], Data(repeating: 0xAB, count: 16), "FeliCa write stored")
    check(runAsync { try await FeliCaCommands.writeWithoutEncryption(card, serviceCode: 0x0009, block: 2, data: hex("00")) } != nil, "FeliCa write needs 16 bytes")

    card.log = []
    card.status = (0xFF, 0xA8)
    failure = runAsync {
        _ = try await FeliCaCommands.readWithoutEncryption(card, serviceCode: 0x000B, blocks: [200])
    }
    checkEqual(failure as? NFCEditorError, NFCEditorError.commandFailed("Status 0xFF 0xA8 (block number out of range)"), "FeliCa status error surfaces")
    card.status = (0, 0)

    card.log = []
    card.knownServices = [0x000B, 0x0009]
    failure = runAsync {
        let versions = try await FeliCaCommands.requestService(card, serviceCodes: [0x000B, 0x1234, 0x0009])
        checkEqual(versions, [0x0001, 0xFFFF, 0x0001], "FeliCa request service marks absent services")
    }
    check(failure == nil, "FeliCa request service threw \(String(describing: failure))")
    checkEqual(card.log, ["requestService 0B00 3412 0900"], "FeliCa request service node codes")
    failure = runAsync {
        let versions = try await FeliCaCommands.requestService(card, serviceCodes: Array(repeating: UInt16(0x000B), count: 40))
        checkEqual(versions.count, 40, "FeliCa request service over 32 codes")
    }
    check(failure == nil, "FeliCa request service chunking threw \(String(describing: failure))")
    checkEqual(card.log.count, 3, "FeliCa request service splits at 32 codes")
}

/// Runs async code from the synchronous test and returns what it threw, if anything.
private func runAsync(_ body: @escaping () async throws -> Void) -> Error? {
    let semaphore = DispatchSemaphore(value: 0)
    let box = ErrorBox()
    Task.detached {
        do {
            try await body()
        } catch {
            box.error = error
        }
        semaphore.signal()
    }
    semaphore.wait()
    return box.error
}

private final class ErrorBox: @unchecked Sendable {
    var error: Error?
}

private func flagText(_ flags: NFCISO15693RequestFlag) -> String {
    flags.rawValue.hex
}

/// Records every command and behaves like a tag with `blockCount` four byte blocks.
private final class FakeISO15693Tag: NFCISO15693Tag, @unchecked Sendable {
    var log: [String] = []
    var memory: [Data]
    var locked: Set<Int> = []
    var afi: UInt8 = 0
    var dsfid: UInt8 = 0
    var afiLocked = false
    var dsfidLocked = false
    var random = Data([0x12, 0x34])
    var multipleFails = false
    var needsOption = false
    var statusChunkLimit: Int?
    var refuseCustom = false
    var refuseCodes: Set<Int> = []

    init(blockCount: Int) {
        memory = (0..<blockCount).map { Data([UInt8($0 & 0xFF), UInt8($0 >> 8), 0, 0]) }
    }

    private func refused() -> Error {
        NFCReaderError(.readerTransceiveErrorTagResponseError)
    }

    private func checkOption(_ flags: NFCISO15693RequestFlag) throws {
        if needsOption && !flags.contains(.option) { throw refused() }
    }

    var isAvailable: Bool { true }
    func queryNDEFStatus() async throws -> (NFCNDEFStatus, Int) { (.notSupported, 0) }
    func readNDEF() async throws -> NFCNDEFMessage { NFCNDEFMessage(records: []) }
    func writeNDEF(_ message: NFCNDEFMessage) async throws {}
    func writeLock() async throws {}
    var identifier: Data { Data([0x78, 0x56, 0x34, 0x12, 0x00, 0x01, 0x04, 0xE0]) }
    var icManufacturerCode: Int { 4 }
    var icSerialNumber: Data { Data() }
    func getSystemInfo(requestFlags: NFCISO15693RequestFlag) async throws -> (Int, Int, Int, Int, Int) { (0, 0, 4, memory.count, 1) }
    func getSystemInfoAndUID(requestFlags: NFCISO15693RequestFlag) async throws -> (Data?, Int, Int, Int, Int, Int) { (nil, 0, 0, 4, memory.count, 1) }

    func readSingleBlock(requestFlags: NFCISO15693RequestFlag, blockNumber: UInt8) async throws -> Data {
        log.append("read \(blockNumber)")
        return memory[Int(blockNumber)]
    }

    func readMultipleBlocks(requestFlags: NFCISO15693RequestFlag, blockRange: NSRange) async throws -> [Data] {
        log.append("readMultiple \(blockRange.location)+\(blockRange.length)")
        if multipleFails { throw refused() }
        return (blockRange.location..<blockRange.location + blockRange.length).map { memory[$0] }
    }

    func writeSingleBlock(requestFlags: NFCISO15693RequestFlag, blockNumber: UInt8, dataBlock: Data) async throws {
        log.append("write \(blockNumber) flags \(flagText(requestFlags)) \(dataBlock.hexString())")
        try checkOption(requestFlags)
        memory[Int(blockNumber)] = dataBlock
    }

    func lockBlock(requestFlags: NFCISO15693RequestFlag, blockNumber: UInt8) async throws {
        log.append("lock \(blockNumber) flags \(flagText(requestFlags))")
        try checkOption(requestFlags)
        locked.insert(Int(blockNumber))
    }

    func customCommand(requestFlags: NFCISO15693RequestFlag, customCommandCode: Int, customRequestParameters: Data) async throws -> Data {
        log.append("custom \(UInt8(customCommandCode).hex) flags \(flagText(requestFlags)) \(customRequestParameters.hexString())")
        if refuseCustom || refuseCodes.contains(customCommandCode) { throw refused() }
        switch customCommandCode {
        case 0xB2: return random
        case 0xA5: return Data(repeating: 0x5A, count: 32)
        default: return Data()
        }
    }

    func extendedReadSingleBlock(requestFlags: NFCISO15693RequestFlag, blockNumber: Int) async throws -> Data {
        log.append("extendedRead \(blockNumber)")
        return memory[blockNumber]
    }

    func extendedReadMultipleBlocks(requestFlags: NFCISO15693RequestFlag, blockRange: NSRange) async throws -> [Data] {
        log.append("extendedReadMultiple \(blockRange.location)+\(blockRange.length)")
        if multipleFails { throw refused() }
        return (blockRange.location..<blockRange.location + blockRange.length).map { memory[$0] }
    }

    func extendedWriteSingleBlock(requestFlags: NFCISO15693RequestFlag, blockNumber: Int, dataBlock: Data) async throws {
        log.append("extendedWrite \(blockNumber) flags \(flagText(requestFlags)) \(dataBlock.hexString())")
        try checkOption(requestFlags)
        memory[blockNumber] = dataBlock
    }

    func extendedLockBlock(requestFlags: NFCISO15693RequestFlag, blockNumber: Int) async throws {
        log.append("extendedLock \(blockNumber) flags \(flagText(requestFlags))")
        try checkOption(requestFlags)
        locked.insert(blockNumber)
    }

    private func statuses(_ range: NSRange) throws -> [NSNumber] {
        if let limit = statusChunkLimit, range.length > limit { throw refused() }
        return (range.location..<range.location + range.length).map { NSNumber(value: locked.contains($0) ? 1 : 0) }
    }

    func getMultipleBlockSecurityStatus(requestFlags: NFCISO15693RequestFlag, blockRange: NSRange) async throws -> [NSNumber] {
        log.append("status \(blockRange.location)+\(blockRange.length)")
        return try statuses(blockRange)
    }

    func extendedGetMultipleBlockSecurityStatus(requestFlags: NFCISO15693RequestFlag, blockRange: NSRange) async throws -> [NSNumber] {
        log.append("extendedStatus \(blockRange.location)+\(blockRange.length)")
        return try statuses(blockRange)
    }

    func writeAFI(requestFlags: NFCISO15693RequestFlag, afi: UInt8) async throws {
        log.append("writeAFI \(afi.hex) flags \(flagText(requestFlags))")
        try checkOption(requestFlags)
        self.afi = afi
    }

    func lockAFI(requestFlags: NFCISO15693RequestFlag) async throws {
        log.append("lockAFI flags \(flagText(requestFlags))")
        try checkOption(requestFlags)
        afiLocked = true
    }

    func writeDSFID(requestFlags: NFCISO15693RequestFlag, dsfid: UInt8) async throws {
        log.append("writeDSFID \(dsfid.hex) flags \(flagText(requestFlags))")
        try checkOption(requestFlags)
        self.dsfid = dsfid
    }

    func lockDFSID(requestFlags: NFCISO15693RequestFlag) async throws {
        log.append("lockDSFID flags \(flagText(requestFlags))")
        try checkOption(requestFlags)
        dsfidLocked = true
    }

    func stayQuiet() async throws {}
    func select(requestFlags: NFCISO15693RequestFlag) async throws {}
    func resetToReady(requestFlags: NFCISO15693RequestFlag) async throws {}
}

/// A FeliCa card with sixteen blocks whose first byte is the block number.
private final class FakeFeliCaTag: NFCFeliCaTag, @unchecked Sendable {
    var log: [String] = []
    var blocks: [Data] = (0..<16).map { Data([UInt8($0)] + [UInt8](repeating: 0, count: 15)) }
    var status: (Int, Int) = (0, 0)
    var knownServices: Set<UInt16> = []

    var isAvailable: Bool { true }
    func queryNDEFStatus() async throws -> (NFCNDEFStatus, Int) { (.notSupported, 0) }
    func readNDEF() async throws -> NFCNDEFMessage { NFCNDEFMessage(records: []) }
    func writeNDEF(_ message: NFCNDEFMessage) async throws {}
    func writeLock() async throws {}
    var currentSystemCode: Data { Data([0x00, 0x03]) }
    var currentIDm: Data { Data([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08]) }
    func polling(systemCode: Data, requestCode: NFCFeliCaPollingRequestCode, timeSlot: NFCFeliCaPollingTimeSlot) async throws -> (Data, Data) { (Data(), Data()) }
    func requestSystemCode() async throws -> [Data] { [currentSystemCode] }
    func sendFeliCaCommand(commandPacket: Data) async throws -> Data { Data() }

    private func blockNumber(_ element: Data) -> Int {
        let bytes = element.bytes
        if bytes.count == 2 { return Int(bytes[1]) }
        return Int(bytes[1]) | Int(bytes[2]) << 8
    }

    func readWithoutEncryption(serviceCodeList: [Data], blockList: [Data]) async throws -> (Int, Int, [Data]) {
        log.append("read \(serviceCodeList.map { $0.hexString() }.joined(separator: " ")) blocks \(blockList.map { $0.hexString() }.joined(separator: " "))")
        if status.0 != 0 { return (status.0, status.1, []) }
        return (0, 0, blockList.map { blocks[blockNumber($0)] })
    }

    func writeWithoutEncryption(serviceCodeList: [Data], blockList: [Data], blockData: [Data]) async throws -> (Int, Int) {
        log.append("write \(serviceCodeList.map { $0.hexString() }.joined(separator: " ")) blocks \(blockList.map { $0.hexString() }.joined(separator: " ")) data \(blockData.map { $0.hexString() }.joined(separator: " "))")
        if status.0 != 0 { return status }
        for (element, data) in zip(blockList, blockData) {
            blocks[blockNumber(element)] = data
        }
        return (0, 0)
    }

    func requestService(nodeCodeList: [Data]) async throws -> [Data] {
        log.append("requestService \(nodeCodeList.map { $0.hexString() }.joined(separator: " "))")
        return nodeCodeList.map { node in
            let code = UInt16(node[0]) | UInt16(node[1]) << 8
            return knownServices.contains(code) ? Data([0x01, 0x00]) : Data([0xFF, 0xFF])
        }
    }

    func requestResponse() async throws -> Int { 0 }
}
