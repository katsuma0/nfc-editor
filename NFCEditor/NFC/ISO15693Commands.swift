import Foundation
import CoreNFC

/// Password identifiers of the NXP ICODE SLIX family, as sent in SET PASSWORD and WRITE PASSWORD.
enum SLIXPassword: UInt8, CaseIterable {
    case read = 0x01
    case write = 0x02
    case privacy = 0x04
    case destroy = 0x08
    case easAFI = 0x10

    var label: String {
        switch self {
        case .read:
            return "Read"
        case .write:
            return "Write"
        case .privacy:
            return "Privacy"
        case .destroy:
            return "Destroy"
        case .easAFI:
            return "EAS and AFI"
        }
    }
}

enum ISO15693Commands {
    struct SystemInfo {
        var blockSize: Int?
        var totalBlocks: Int?
        var icReference: Int?
        var dsfid: Int?
        var afi: Int?
        var uid: Data
    }

    private static let defaultFlags: NFCISO15693RequestFlag = [.highDataRate, .address]
    private static let multipleBlockChunk = 32
    /// Blocks above this index only have the extended commands with a two byte block number.
    private static let lastShortBlock = 0xFF
    private static let lastBlock = 0xFFFF

    static func systemInfo(_ tag: NFCISO15693Tag) async throws -> SystemInfo {
        // Core NFC hands the identifier back LSB first; the standard order starts with E0.
        let uid = Data(tag.identifier.reversed())
        var info = SystemInfo(blockSize: nil, totalBlocks: nil, icReference: nil, dsfid: nil, afi: nil, uid: uid)

        var response: RawSystemInfo?
        do {
            response = try await querySystemInfo(tag, flags: defaultFlags)
        } catch {
            let mapped = NFCEditorError.map(error)
            if mapped == .cancelled || mapped == .timeout { throw mapped }
            // Some tags only answer when the request is not addressed.
            do {
                response = try await querySystemInfo(tag, flags: [.highDataRate])
            } catch {
                let retried = NFCEditorError.map(error)
                if isSessionError(retried) { throw retried }
            }
        }

        if let response {
            info.blockSize = positive(response.blockSize)
            info.totalBlocks = positive(response.blockCount)
            info.icReference = nonNegative(response.icReference)
            info.dsfid = nonNegative(response.dsfid)
            info.afi = nonNegative(response.afi)
        }
        return info
    }

    private struct RawSystemInfo {
        var dsfid: Int
        var afi: Int
        var blockSize: Int
        var blockCount: Int
        var icReference: Int
    }

    /// Core NFC reports -1 for every field the tag did not provide.
    private static func querySystemInfo(_ tag: NFCISO15693Tag, flags: NFCISO15693RequestFlag) async throws -> RawSystemInfo {
        // The labelled completion handler form is the one Core NFC has shipped since iOS 13; the async and Result forms differ between SDKs.
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<RawSystemInfo, Error>) in
            tag.getSystemInfo(requestFlags: flags, completionHandler: { dsfid, afi, blockSize, blockCount, icReference, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: RawSystemInfo(dsfid: dsfid, afi: afi, blockSize: blockSize, blockCount: blockCount, icReference: icReference))
                }
            })
        }
    }

    static func readBlocks(_ tag: NFCISO15693Tag, from: Int, to: Int, progress: ((Int) -> Void)?) async throws -> [MemoryPage] {
        guard from >= 0, to <= lastBlock, from <= to else {
            throw NFCEditorError.invalidInput("The block range must be within 0 to \(lastBlock).")
        }

        var pages: [MemoryPage] = []
        var current = from
        var multipleWorks = true
        var extendedMultipleWorks = true

        while current <= to {
            let extended = current > lastShortBlock
            if extended ? extendedMultipleWorks : multipleWorks {
                let chunkEnd = chunkLimit(from: current, to: to)
                let count = chunkEnd - current + 1
                let range = NSRange(location: current, length: count)
                do {
                    let blocks: [Data]
                    if extended {
                        blocks = try await tag.extendedReadMultipleBlocks(requestFlags: defaultFlags, blockRange: range)
                    } else {
                        blocks = try await tag.readMultipleBlocks(requestFlags: defaultFlags, blockRange: range)
                    }
                    if blocks.count == count {
                        for (offset, block) in blocks.enumerated() {
                            pages.append(MemoryPage(index: current + offset, bytes: Data(block), readable: true))
                        }
                        current = chunkEnd + 1
                        progress?(pages.count)
                        continue
                    }
                    if extended { extendedMultipleWorks = false } else { multipleWorks = false }
                } catch {
                    let mapped = NFCEditorError.map(error)
                    if mapped == .cancelled || mapped == .timeout { throw mapped }
                    // Fall back to single block reads; a tag that ignores the multiple block command looks lost to Core NFC.
                    if extended { extendedMultipleWorks = false } else { multipleWorks = false }
                }
            }

            do {
                let block = try await readSingleBlock(tag, index: current)
                pages.append(MemoryPage(index: current, bytes: Data(block), readable: true))
            } catch {
                let mapped = NFCEditorError.map(error)
                if isSessionError(mapped) { throw mapped }
                pages.append(MemoryPage(index: current, bytes: Data(), readable: false))
            }
            current += 1
            progress?(pages.count)
        }
        return pages
    }

    static func writeBlock(_ tag: NFCISO15693Tag, index: Int, bytes: Data) async throws {
        try checkBlockIndex(index)
        guard !bytes.isEmpty, bytes.count <= 32 else {
            throw NFCEditorError.invalidInput("Enter between 1 and 32 bytes for the block.")
        }
        try await withOptionRetry { flags in
            if index > lastShortBlock {
                try await tag.extendedWriteSingleBlock(requestFlags: flags, blockNumber: index, dataBlock: bytes)
            } else {
                try await tag.writeSingleBlock(requestFlags: flags, blockNumber: UInt8(index), dataBlock: bytes)
            }
        }
    }

    static func custom(_ tag: NFCISO15693Tag, flags: NFCISO15693RequestFlag, code: Int, parameters: Data) async throws -> Data {
        guard (0...255).contains(code) else {
            throw NFCEditorError.invalidInput("The command code must be a single byte.")
        }
        do {
            let response = try await tag.customCommand(requestFlags: flags, customCommandCode: code, customRequestParameters: parameters)
            return Data(response)
        } catch {
            throw NFCEditorError.map(error)
        }
    }

    static func lockBlock(_ tag: NFCISO15693Tag, index: Int) async throws {
        try checkBlockIndex(index)
        try await withOptionRetry { flags in
            if index > lastShortBlock {
                try await tag.extendedLockBlock(requestFlags: flags, blockNumber: index)
            } else {
                try await tag.lockBlock(requestFlags: flags, blockNumber: UInt8(index))
            }
        }
    }

    /// One flag per block in `from...to`, true when the block is locked. Stops at block 255: the extended
    /// security status call does not compile against current SDKs, so blocks above it are left unreported.
    static func blockSecurityStatus(_ tag: NFCISO15693Tag, from: Int, to: Int) async throws -> [Bool] {
        guard from >= 0, to <= lastBlock, from <= to, from <= lastShortBlock else {
            throw NFCEditorError.invalidInput("Lock state can be read for blocks 0 to \(lastShortBlock).")
        }
        let to = min(to, lastShortBlock)
        var locked: [Bool] = []
        var current = from
        while current <= to {
            let chunkEnd = chunkLimit(from: current, to: to)
            let count = chunkEnd - current + 1
            var statuses: [NSNumber] = []
            do {
                statuses = try await securityStatus(tag, from: current, count: count)
            } catch {
                let mapped = NFCEditorError.map(error)
                if isSessionError(mapped) || count == 1 { throw mapped }
            }
            if statuses.count != count {
                // Some tags refuse a long range, so ask for the blocks of this chunk one at a time.
                statuses = []
                for block in current...chunkEnd {
                    let single = try await securityStatus(tag, from: block, count: 1)
                    guard let status = single.first else {
                        throw NFCEditorError.commandFailed("The tag did not report the lock state of block \(block).")
                    }
                    statuses.append(status)
                }
            }
            locked.append(contentsOf: lockedFlags(statuses))
            current = chunkEnd + 1
        }
        return locked
    }

    /// Bit 0 of a block security status byte is the lock flag; the other bits are chip specific.
    static func lockedFlags(_ statuses: [NSNumber]) -> [Bool] {
        statuses.map { $0.intValue & 0x01 != 0 }
    }

    private static func securityStatus(_ tag: NFCISO15693Tag, from: Int, count: Int) async throws -> [NSNumber] {
        let range = NSRange(location: from, length: count)
        return try await tag.getMultipleBlockSecurityStatus(requestFlags: defaultFlags, blockRange: range)
    }

    private static func readSingleBlock(_ tag: NFCISO15693Tag, index: Int) async throws -> Data {
        if index > lastShortBlock {
            return try await tag.extendedReadSingleBlock(requestFlags: defaultFlags, blockNumber: index)
        }
        return try await tag.readSingleBlock(requestFlags: defaultFlags, blockNumber: UInt8(index))
    }

    /// A chunk never crosses block 255 because the two command families address blocks differently.
    private static func chunkLimit(from current: Int, to: Int) -> Int {
        let limit = current > lastShortBlock ? to : min(to, lastShortBlock)
        return min(current + multipleBlockChunk - 1, limit)
    }

    private static func checkBlockIndex(_ index: Int) throws {
        guard (0...lastBlock).contains(index) else {
            throw NFCEditorError.invalidInput("Block \(index) is out of range (0 to \(lastBlock)).")
        }
    }

    /// Tags from ST and TI only answer a write type command when the option flag is set, so a refused attempt is repeated with it.
    private static func withOptionRetry(_ send: (NFCISO15693RequestFlag) async throws -> Void) async throws {
        do {
            try await send(defaultFlags)
        } catch {
            let mapped = NFCEditorError.map(error)
            if mapped == .cancelled || mapped == .timeout { throw mapped }
            do {
                try await send(defaultFlags.union(.option))
            } catch {
                throw NFCEditorError.map(error)
            }
        }
    }

    private static func positive(_ value: Int) -> Int? {
        value > 0 ? value : nil
    }

    private static func nonNegative(_ value: Int) -> Int? {
        value >= 0 ? value : nil
    }

    private static func isSessionError(_ error: NFCEditorError) -> Bool {
        switch error {
        case .cancelled, .timeout, .tagLost, .nfcUnavailable, .multipleTags:
            return true
        default:
            return false
        }
    }
}

// MARK: AFI and DSFID

extension ISO15693Commands {
    static func writeAFI(_ tag: NFCISO15693Tag, afi: UInt8) async throws {
        try await withOptionRetry { flags in
            try await tag.writeAFI(requestFlags: flags, afi: afi)
        }
    }

    /// Permanent: the AFI can never be changed again.
    static func lockAFI(_ tag: NFCISO15693Tag) async throws {
        try await withOptionRetry { flags in
            try await tag.lockAFI(requestFlags: flags)
        }
    }

    static func writeDSFID(_ tag: NFCISO15693Tag, dsfid: UInt8) async throws {
        try await withOptionRetry { flags in
            try await tag.writeDSFID(requestFlags: flags, dsfid: dsfid)
        }
    }

    /// Permanent: the DSFID can never be changed again. Core NFC spells the command lockDFSID.
    static func lockDSFID(_ tag: NFCISO15693Tag) async throws {
        try await withOptionRetry { flags in
            try await completion { tag.lockDFSID(requestFlags: flags, completionHandler: $0) }
        }
    }
}

// MARK: ICODE SLIX family (NXP, manufacturer 0x04)

extension ISO15693Commands {
    private enum SLIXCommand {
        static let setEAS = 0xA2
        static let resetEAS = 0xA3
        static let lockEAS = 0xA4
        static let easAlarm = 0xA5
        static let protectPage = 0xB6
        static let getRandomNumber = 0xB2
        static let setPassword = 0xB3
        static let writePassword = 0xB4
        static let destroy = 0xB9
        static let enablePrivacy = 0xBA
    }

    /// GET RANDOM NUMBER (B2): two bytes the tag uses to hide the next password transfer.
    static func slixGetRandomNumber(_ tag: NFCISO15693Tag) async throws -> Data {
        let response: Data
        do {
            response = try await slixCommand(tag, code: SLIXCommand.getRandomNumber, parameters: Data())
        } catch let error as NFCEditorError {
            // Only ICODE SLIX chips answer B2, so a refusal here means the wrong kind of tag rather than a wrong password.
            if case .nak = error { throw NFCEditorError.notSupportedOnChip("This tag does not answer ICODE SLIX commands.") }
            throw error
        }
        guard response.count >= 2 else {
            throw NFCEditorError.commandFailed("The tag did not return a random number.")
        }
        return Data(response.prefix(2))
    }

    /// SET PASSWORD (B3): presents a password so the protected feature opens until the tag leaves the field.
    static func slixSetPassword(_ tag: NFCISO15693Tag, identifier: SLIXPassword, password: Data) async throws {
        try checkSLIXPassword(password)
        let random = try await slixGetRandomNumber(tag)
        let parameters = Data([identifier.rawValue]) + slixMaskPassword(password, random: random)
        do {
            _ = try await slixCommand(tag, code: SLIXCommand.setPassword, parameters: parameters)
        } catch let error as NFCEditorError {
            throw passwordError(error)
        }
    }

    /// WRITE PASSWORD (B4): changes a password. The current one must have been presented first.
    static func slixWritePassword(_ tag: NFCISO15693Tag, identifier: SLIXPassword, password: Data) async throws {
        try checkSLIXPassword(password)
        _ = try await slixCommand(tag, code: SLIXCommand.writePassword, parameters: Data([identifier.rawValue]) + password)
    }

    /// ENABLE PRIVACY (BA): the tag only answers GET RANDOM NUMBER and SET PASSWORD until the privacy password is presented.
    static func slixEnablePrivacy(_ tag: NFCISO15693Tag) async throws {
        _ = try await slixCommand(tag, code: SLIXCommand.enablePrivacy, parameters: Data())
    }

    /// PROTECT PAGE (B6): sets the read and write protection of a page of blocks.
    static func slixProtectPage(_ tag: NFCISO15693Tag, pageNumber: UInt8, protection: UInt8) async throws {
        _ = try await slixCommand(tag, code: SLIXCommand.protectPage, parameters: Data([pageNumber, protection]))
    }

    static func slixSetEAS(_ tag: NFCISO15693Tag) async throws {
        _ = try await slixCommand(tag, code: SLIXCommand.setEAS, parameters: Data())
    }

    static func slixResetEAS(_ tag: NFCISO15693Tag) async throws {
        _ = try await slixCommand(tag, code: SLIXCommand.resetEAS, parameters: Data())
    }

    /// Permanent: the EAS state can never be changed again.
    static func slixLockEAS(_ tag: NFCISO15693Tag) async throws {
        _ = try await slixCommand(tag, code: SLIXCommand.lockEAS, parameters: Data())
    }

    /// EAS ALARM (A5): the 32 byte EAS sequence when EAS is on, empty when the tag stays silent because it is off.
    static func slixEASAlarm(_ tag: NFCISO15693Tag) async throws -> Data {
        do {
            return try await slixCommand(tag, code: SLIXCommand.easAlarm, parameters: Data())
        } catch let error as NFCEditorError {
            if case .nak = error { return Data() }
            throw error
        }
    }

    /// DESTROY (B9): irreversible, the tag never answers again. Needs the destroy password.
    static func slixDestroy(_ tag: NFCISO15693Tag, password: Data) async throws {
        try checkSLIXPassword(password)
        let random = try await slixGetRandomNumber(tag)
        do {
            _ = try await slixCommand(tag, code: SLIXCommand.destroy, parameters: slixMaskPassword(password, random: random))
        } catch let error as NFCEditorError {
            throw passwordError(error)
        }
    }

    /// The password bytes are XORed with the random number repeated: p0^r0, p1^r1, p2^r0, p3^r1.
    static func slixMaskPassword(_ password: Data, random: Data) -> Data {
        let p = password.bytes
        let r = random.bytes
        guard p.count == 4, r.count >= 2 else { return password }
        return Data([p[0] ^ r[0], p[1] ^ r[1], p[2] ^ r[0], p[3] ^ r[1]])
    }

    private static func slixCommand(_ tag: NFCISO15693Tag, code: Int, parameters: Data) async throws -> Data {
        try await custom(tag, flags: defaultFlags, code: code, parameters: parameters)
    }

    private static func checkSLIXPassword(_ password: Data) throws {
        guard password.count == 4 else {
            throw NFCEditorError.invalidInput("A SLIX password is exactly 4 bytes.")
        }
    }

    /// A tag that refuses or ignores a password command did not accept the password.
    private static func passwordError(_ error: NFCEditorError) -> NFCEditorError {
        if case .nak = error { return .authenticationFailed }
        return error
    }
}

// MARK: ST25TV (ST, manufacturer 0x02)

extension ISO15693Commands {
    private enum STCommand {
        static let writePassword = 0xB1
        static let presentPassword = 0xB3
    }

    /// PRESENT PASSWORD (B3): opens the areas the password protects until the tag leaves the field.
    static func stPresentPassword(_ tag: NFCISO15693Tag, number: UInt8, password: Data) async throws {
        try checkSTPassword(password)
        do {
            try await withOptionRetry { flags in
                _ = try await custom(tag, flags: flags, code: STCommand.presentPassword, parameters: Data([number]) + password)
            }
        } catch let error as NFCEditorError {
            throw passwordError(error)
        }
    }

    /// WRITE PASSWORD (B1): changes a password. The current one must have been presented first.
    static func stWritePassword(_ tag: NFCISO15693Tag, number: UInt8, password: Data) async throws {
        try checkSTPassword(password)
        try await withOptionRetry { flags in
            _ = try await custom(tag, flags: flags, code: STCommand.writePassword, parameters: Data([number]) + password)
        }
    }

    private static func checkSTPassword(_ password: Data) throws {
        guard password.count == 8 else {
            throw NFCEditorError.invalidInput("An ST25TV password is exactly 8 bytes.")
        }
    }
}

// MARK: Completion handler bridges

extension ISO15693Commands {
    // lockDFSID has no async form, so it is bridged here.
    fileprivate static func completion(_ start: (@escaping @Sendable (Error?) -> Void) -> Void) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            start { error in
                if let error = error { continuation.resume(throwing: error) } else { continuation.resume(returning: ()) }
            }
        }
    }
}
