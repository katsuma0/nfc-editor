import Foundation
import CoreNFC

struct WriteOptions: Codable, Hashable, Sendable {
    var lockAfterWrite: Bool = false
    var verifyAfterWrite: Bool = true
    var eraseFirst: Bool = false
}

struct WriteResult: Hashable, Sendable {
    var bytesWritten: Int
    var capacity: Int?
    var locked: Bool
    var verified: Bool?
}

struct PasswordConfig: Hashable, Sendable {
    var password: Data
    var pack: Data
    var protectFromPage: Int = 4
    var protectReads: Bool = false
    var authLimit: Int = 0
    var currentPassword: Data? = nil
}

enum RawTransport: String, Codable, CaseIterable, Sendable {
    case mifare, apdu, iso15693, feliCa
}

struct RawCommand: Hashable, Sendable {
    var transport: RawTransport
    var bytes: Data
}

struct RawResponse: Hashable, Sendable {
    var bytes: Data
    var sw1: UInt8?
    var sw2: UInt8?
    var elapsedMS: Int
}

/// A read only snapshot of an ISO 15693 (Type 5) tag's settings, used by the Type 5 tool.
struct Type5Settings: Hashable, Sendable {
    var dsfid: Int?
    var afi: Int?
    var blockSize: Int
    var totalBlocks: Int
    var lockedBlocks: [Bool]
    var isSLIX: Bool
    var isST: Bool
}

/// High-level operations. Each is run inside NFCSessionManager.run { session, tag in ... }.
enum TagOperations {
    private static let emptyTLV = Data([0x03, 0x00, 0xFE, 0x00])
    private static let zeroPage = Data(repeating: 0, count: 4)
    private static let maxProbePages = 256

    private struct NDEFContent {
        var status: NDEFStatus
        var capacity: Int?
        var records: [NDEFRecord]
    }

    private struct PasswordLayout {
        var cfg0: Int
        var cfg1: Int
        var pwd: Int
        var pack: Int
    }

    // MARK: Read

    static func readTag(_ session: NFCTagReaderSession, _ tag: NFCTag, includeDump: Bool) async throws -> TagInfo {
        switch tag {
        case .miFare(let mifare):
            if mifare.mifareFamily == .desfire {
                return try await readDESFire(session, mifare, includeDump: includeDump)
            }
            return try await readType2(session, mifare, includeDump: includeDump)
        case .iso15693(let iso15693):
            return try await readISO15693(session, iso15693, includeDump: includeDump)
        case .feliCa(let feliCa):
            return try await readFeliCa(session, feliCa)
        case .iso7816(let iso7816):
            return try await readISO7816(session, iso7816)
        @unknown default:
            throw NFCEditorError.unsupportedTag("This tag type is not supported.")
        }
    }

    private static func readType2(_ session: NFCTagReaderSession, _ tag: NFCMiFareTag, includeDump: Bool) async throws -> TagInfo {
        session.alertMessage = "Identifying the tag."
        let (spec, version) = try await identifyType2(session, tag)
        var info = TagInfo(technology: .iso14443A, chip: spec, uid: Data(tag.identifier))
        info.versionBytes = version

        session.alertMessage = "Reading records."
        let content = try await readNDEFContent(tag)
        apply(content, to: &info)

        guard spec.supportsRawPages else { return info }
        // A protected or unformatted tag refuses the NDEF read and drops to idle, so select it again before raw reads.
        await reselect(session, tag)

        var header: [UInt8]?
        if includeDump {
            let pages = try await dumpType2(session, tag, spec)
            info.dump = MemoryDump(pageSize: 4, pages: pages, chip: spec, readAt: Date())
            if pages.count >= 4, pages[0..<4].allSatisfy({ $0.readable && $0.bytes.count == 4 }) {
                header = pages[0..<4].flatMap { $0.bytes.bytes }
            }
        }
        if header == nil, let page0 = try await probe(session, tag, { try await MiFareCommands.read(tag, page: 0) }) {
            header = page0.bytes
        }

        if let header, header.count >= 16 {
            info.extras.append(field("Static lock bytes", Data(header[10..<12]).hexString(separator: " "), "lock"))
            info.extras.append(field("Capability container", Data(header[12..<16]).hexString(separator: " "), "doc.text"))
        }

        if let dynamicPage = spec.dynamicLockPage {
            var dynamic: [UInt8]?
            if let dump = info.dump, let page = dump.pages.first(where: { $0.index == dynamicPage }), page.readable {
                dynamic = page.bytes.bytes
            } else if let data = try await probe(session, tag, { try await MiFareCommands.read(tag, page: dynamicPage) }) {
                dynamic = data.bytes
            }
            if let dynamic, dynamic.count >= 3 {
                info.extras.append(field("Dynamic lock bytes", Data(dynamic[0..<3]).hexString(separator: " "), "lock"))
            }
        }

        if let cfg0Page = spec.cfg0Page {
            let config = try await probe(session, tag, { try await MiFareCommands.read(tag, page: cfg0Page) })
            if let config, config.count >= 8 {
                let bytes = config.bytes
                let auth0 = Int(bytes[3])
                let lastPage = (spec.totalPages ?? maxProbePages) - 1
                let protected = auth0 <= lastPage
                info.passwordProtected = protected
                let access = bytes[4]
                if spec.supportsCounter, isNTAG21x(spec) {
                    info.counterEnabled = (access & 0x10) != 0
                }
                if protected {
                    info.extras.append(field("Protected from page", "\(auth0)", "lock.shield"))
                    info.extras.append(field("Protection", (access & 0x80) != 0 ? "Read and write" : "Write only", "lock.shield"))
                    let limit = Int(access & 0x07)
                    info.extras.append(field("Wrong attempts allowed", limit == 0 ? "Unlimited" : "\(limit)", "lock.shield"))
                }
            }
        }

        if spec.supportsCounter {
            if isNTAG21x(spec) {
                info.counter = try await probe(session, tag, { try await MiFareCommands.readCounter(tag, address: 2) })
            } else if spec.family == .ultralightEV1 {
                for address in 0...2 {
                    let counterAddress = UInt8(address)
                    if let value = try await probe(session, tag, { try await MiFareCommands.readCounter(tag, address: counterAddress) }) {
                        if info.counter == nil { info.counter = value }
                        info.extras.append(field("Counter \(address)", "\(value)", "number"))
                    }
                }
            }
        }

        if spec.supportsSignature {
            if let signature = try await probe(session, tag, { try await MiFareCommands.readSignature(tag) }) {
                info.signature = signature
                info.signatureVerdict = OriginalitySignature.verify(signature: signature, uid: info.uid, chip: spec)
            }
        }

        if isNTAG21x(spec) {
            if let mirror = try await probe(session, tag, { try await NTAGMirror.read(tag, chip: spec) }) {
                info.extras.append(field("Mirror", mirrorDescription(mirror), "arrow.triangle.2.circlepath"))
            }
        }

        // The NTAG 213 TT answers READ_TT_STATUS with five bytes of tamper state.
        if spec.name.contains("TT") {
            if let tamper = try await probe(session, tag, { try await MiFareCommands.transceive(tag, Data([0xA4, 0x00]), expectAck: false) }), tamper.count >= 5 {
                info.tamperStatus = Data(tamper.prefix(5))
            }
        }

        if let version {
            info.extras.append(field("GET_VERSION", version.hexString(separator: " "), "info.circle"))
        }
        return info
    }

    private static func mirrorDescription(_ mirror: MirrorConfig) -> String {
        switch mirror.kind {
        case .none:
            return "Off"
        case .uid:
            return "UID at page \(mirror.page), byte \(mirror.byte)"
        case .counter:
            return "Counter at page \(mirror.page), byte \(mirror.byte)"
        case .both:
            return "UID and counter at page \(mirror.page), byte \(mirror.byte)"
        }
    }

    private static func readDESFire(_ session: NFCTagReaderSession, _ tag: NFCMiFareTag, includeDump: Bool) async throws -> TagInfo {
        session.alertMessage = "Identifying the tag."
        let (spec, version) = try await desfireSpec(tag)
        var info = TagInfo(technology: .iso14443_4, chip: spec, uid: Data(tag.identifier))
        info.versionBytes = version?.raw

        session.alertMessage = "Reading records."
        let content = try await readNDEFContent(tag)
        apply(content, to: &info)

        if let historical = tag.historicalBytes, !historical.isEmpty {
            info.extras.append(field("Historical bytes", historical.hexString(separator: " "), "info.circle"))
        }
        if let version {
            let hardware = version.hardware.bytes
            let software = version.software.bytes
            if hardware.count >= 7 {
                info.extras.append(field("Hardware version", "\(hardware[3]).\(hardware[4])", "cpu"))
                info.extras.append(field("Storage size code", "0x" + hardware[5].hex, "cpu"))
            }
            if software.count >= 7 {
                info.extras.append(field("Software version", "\(software[3]).\(software[4])", "cpu"))
            }
            if !version.production.isEmpty {
                info.extras.append(field("Production data", version.production.hexString(separator: " "), "info.circle"))
            }
        }

        // The master application lists the other applications and, on EV1 and newer, the free memory.
        if try await attempt({ try await DESFireCommands.selectApplication(tag, aid: Data([0x00, 0x00, 0x00])) }) != nil {
            if let applications = try await attempt({ try await DESFireCommands.getApplicationIDs(tag) }) {
                if applications.isEmpty {
                    info.extras.append(field("Applications", "None", "app.badge"))
                } else {
                    let list = applications.map { $0.hexString() }.joined(separator: ", ")
                    info.extras.append(field("Applications", "\(applications.count): \(list)", "app.badge"))
                }
            }
            if let free = try await attempt({ try await DESFireCommands.getFreeMemory(tag) }), let bytes = free {
                info.extras.append(field("Free memory", "\(bytes) bytes", "memorychip"))
            }
        }

        if includeDump {
            session.alertMessage = "Reading the NDEF file."
            let file = try await attempt({
                try await DESFireCommands.readNDEFFile(send: { try await DESFireCommands.apdu(tag, $0) })
            })
            if let file, let bytes = file {
                var dumpSpec = spec
                dumpSpec.pageSize = 16
                info.dump = MemoryDump(flatBytes: bytes, pageSize: 16, chip: dumpSpec)
            }
        }
        return info
    }

    private static func readISO15693(_ session: NFCTagReaderSession, _ tag: NFCISO15693Tag, includeDump: Bool) async throws -> TagInfo {
        session.alertMessage = "Identifying the tag."
        let system = try await ISO15693Commands.systemInfo(tag)
        let spec = iso15693Spec(tag, system)
        var info = TagInfo(technology: .iso15693, chip: spec, uid: system.uid)

        session.alertMessage = "Reading records."
        let content = try await readNDEFContent(tag)
        apply(content, to: &info)

        if let dsfid = system.dsfid {
            info.extras.append(field("DSFID", "0x" + UInt8(truncatingIfNeeded: dsfid).hex, "info.circle"))
        }
        if let afi = system.afi {
            info.extras.append(field("AFI", "0x" + UInt8(truncatingIfNeeded: afi).hex, "info.circle"))
        }
        if let reference = system.icReference {
            info.extras.append(field("IC reference", "0x" + UInt8(truncatingIfNeeded: reference).hex, "cpu"))
        }
        if let blockSize = system.blockSize, let total = system.totalBlocks {
            info.extras.append(field("Blocks", "\(total) blocks of \(blockSize) bytes", "square.grid.3x3"))
        }
        info.extras.append(field("IC manufacturer code", "0x" + UInt8(truncatingIfNeeded: tag.icManufacturerCode).hex, "building.2"))

        if let total = system.totalBlocks, total > 0 {
            let count = min(total, maxProbePages)
            if let locked = try await attempt({ try await ISO15693Commands.blockSecurityStatus(tag, from: 0, to: count - 1) }) {
                let lockedCount = locked.filter { $0 }.count
                info.extras.append(field("Locked blocks", "\(lockedCount) of \(locked.count)", "lock"))
            }
        }

        if includeDump {
            let pages = try await dumpISO15693(session, tag, system)
            info.dump = MemoryDump(pageSize: system.blockSize ?? 4, pages: pages, chip: spec, readAt: Date())
        }
        return info
    }

    private static func readFeliCa(_ session: NFCTagReaderSession, _ tag: NFCFeliCaTag) async throws -> TagInfo {
        session.alertMessage = "Identifying the tag."
        let feliCa = try await FeliCaCommands.info(tag)
        let spec = ChipIdentifier.feliCa(systemCode: feliCa.systemCode)
        var info = TagInfo(technology: .feliCa, chip: spec, uid: feliCa.idm)

        session.alertMessage = "Reading records."
        let content = try await readNDEFContent(tag)
        apply(content, to: &info)

        if let pmm = feliCa.pmm {
            info.extras.append(field("PMm", pmm.hexString(separator: " "), "info.circle"))
        }
        info.extras.append(field("System code", "0x" + feliCa.systemCode.hexString(), "number"))
        if feliCa.systemCodes.count > 1 {
            let list = feliCa.systemCodes.map { "0x" + $0.hexString() }.joined(separator: ", ")
            info.extras.append(field("System codes", list, "number"))
        }
        return info
    }

    private static func readISO7816(_ session: NFCTagReaderSession, _ tag: NFCISO7816Tag) async throws -> TagInfo {
        session.alertMessage = "Reading the tag."
        var info = TagInfo(technology: .iso14443_4, chip: ChipIdentifier.iso7816Generic(), uid: Data(tag.identifier))

        let content = try await readNDEFContent(tag)
        apply(content, to: &info)

        if let historical = tag.historicalBytes, !historical.isEmpty {
            info.extras.append(field("Historical bytes", historical.hexString(separator: " "), "info.circle"))
        }
        if !tag.initialSelectedAID.isEmpty {
            info.extras.append(field("Selected application", tag.initialSelectedAID, "app.badge"))
        }
        if let applicationData = tag.applicationData, !applicationData.isEmpty {
            info.extras.append(field("Application data", applicationData.hexString(separator: " "), "info.circle"))
        }
        return info
    }

    // MARK: Write

    static func writeRecords(_ session: NFCTagReaderSession, _ tag: NFCTag, records: [NDEFRecord], options: WriteOptions) async throws -> WriteResult {
        guard !records.isEmpty else {
            throw NFCEditorError.invalidInput("Add at least one record.")
        }
        let ndef = try ndefTag(for: tag)

        session.alertMessage = "Checking the tag."
        var queried = try await queryStatus(ndef)
        if queried.0 == .notSupported {
            if case .miFare(let mifare) = tag, mifare.mifareFamily != .desfire, try await formatIfBlank(session, mifare) {
                // Raw page writes leave the tag selected but Core NFC only detects NDEF on a fresh selection.
                await reselect(session, mifare)
                queried = try await queryStatus(ndef)
            }
            if queried.0 == .notSupported {
                throw notFormatted(tag)
            }
        }
        if queried.0 == .readOnly {
            throw NFCEditorError.readOnly
        }
        let capacity = queried.1

        let needed = NDEFMessageCodec.byteCount(records)
        if capacity > 0, needed > capacity {
            throw NFCEditorError.capacityExceeded(needed: needed, capacity: capacity)
        }

        if options.eraseFirst {
            session.alertMessage = "Erasing."
            try await writeMessage(ndef, [NDEFRecord.empty])
        }

        session.alertMessage = "Writing \(needed) bytes."
        try await writeMessage(ndef, records)

        var verified: Bool?
        if options.verifyAfterWrite {
            session.alertMessage = "Verifying."
            let readBack = try await readMessage(ndef)
            guard NDEFMessageCodec.encode(readBack) == NDEFMessageCodec.encode(records) else {
                throw NFCEditorError.failed("The data read back from the tag does not match what was written.")
            }
            verified = true
        }

        var locked = false
        if options.lockAfterWrite {
            session.alertMessage = "Locking the tag."
            do {
                try await ndef.writeLock()
            } catch {
                throw NFCEditorError.map(error)
            }
            locked = true
        }

        return WriteResult(bytesWritten: needed, capacity: capacity > 0 ? capacity : nil, locked: locked, verified: verified)
    }

    static func erase(_ session: NFCTagReaderSession, _ tag: NFCTag, zeroUserMemory: Bool) async throws {
        let ndef = try ndefTag(for: tag)
        session.alertMessage = "Checking the tag."
        let (status, _) = try await queryStatus(ndef)
        if status == .readOnly {
            throw NFCEditorError.readOnly
        }

        switch tag {
        case .miFare(let mifare) where zeroUserMemory && mifare.mifareFamily != .desfire:
            let (spec, _) = try await identifyType2(session, mifare)
            guard spec.supportsRawPages, let range = spec.userPageRange else {
                throw NFCEditorError.notSupportedOnChip("The memory layout of \(spec.name) is not known, so it cannot be zeroed.")
            }
            session.alertMessage = "Erasing."
            try await MiFareCommands.write(mifare, page: range.lowerBound, bytes: emptyTLV)
            try await zeroPages(session, mifare, from: range.lowerBound + 1, to: range.upperBound)
        case .iso15693(let iso15693) where zeroUserMemory:
            try await layoutISO15693(session, iso15693, writeCapabilityContainer: false)
        default:
            if status == .notSupported {
                throw notFormatted(tag)
            }
            session.alertMessage = "Erasing."
            try await writeMessage(ndef, [NDEFRecord.empty])
        }
    }

    /// Format tag only lays out NTAG, Ultralight and ISO 15693 memory, so other chips get their own message.
    private static func notFormatted(_ tag: NFCTag) -> NFCEditorError {
        switch tag {
        case .miFare(let mifare) where mifare.mifareFamily == .desfire:
            return .noNDEFApplication
        case .feliCa, .iso7816:
            return .unsupportedTag("It has no NDEF data area, and this app cannot create one on this chip.")
        default:
            return .notNDEFFormatted
        }
    }

    static func lock(_ session: NFCTagReaderSession, _ tag: NFCTag) async throws {
        let ndef = try ndefTag(for: tag)
        session.alertMessage = "Checking the tag."
        let (status, _) = try await queryStatus(ndef)
        if status == .notSupported {
            throw notFormatted(tag)
        }
        if status == .readOnly {
            throw NFCEditorError.readOnly
        }
        session.alertMessage = "Locking the tag."
        do {
            try await ndef.writeLock()
        } catch {
            throw NFCEditorError.map(error)
        }
    }

    static func format(_ session: NFCTagReaderSession, _ tag: NFCTag) async throws {
        switch tag {
        case .miFare(let mifare) where mifare.mifareFamily != .desfire:
            session.alertMessage = "Identifying the tag."
            let (spec, _) = try await identifyType2(session, mifare)
            try await formatType2(session, mifare, spec)
        case .iso15693(let iso15693):
            try await layoutISO15693(session, iso15693, writeCapabilityContainer: true)
        default:
            throw NFCEditorError.notSupportedOnChip("Formatting is only available for Type 2 and Type 5 tags.")
        }
    }

    // MARK: Memory

    static func readMemory(_ session: NFCTagReaderSession, _ tag: NFCTag, password: Data?) async throws -> MemoryDump {
        switch tag {
        case .miFare(let mifare) where mifare.mifareFamily == .desfire:
            session.alertMessage = "Reading the NDEF file."
            let (spec, _) = try await desfireSpec(mifare)
            return try await type4Dump(spec: spec) { try await DESFireCommands.apdu(mifare, $0) }
        case .miFare(let mifare):
            session.alertMessage = "Identifying the tag."
            let (spec, _) = try await identifyType2(session, mifare)
            guard spec.supportsRawPages else {
                throw NFCEditorError.notSupportedOnChip("The memory of \(spec.name) cannot be read by iOS.")
            }
            if let password {
                try await authenticate(mifare, password: password)
            }
            let pages = try await dumpType2(session, mifare, spec)
            return MemoryDump(pageSize: 4, pages: pages, chip: spec, readAt: Date())
        case .iso15693(let iso15693):
            session.alertMessage = "Identifying the tag."
            let system = try await ISO15693Commands.systemInfo(iso15693)
            let spec = iso15693Spec(iso15693, system)
            let pages = try await dumpISO15693(session, iso15693, system)
            return MemoryDump(pageSize: system.blockSize ?? 4, pages: pages, chip: spec, readAt: Date())
        case .iso7816(let iso7816):
            session.alertMessage = "Reading the NDEF file."
            return try await type4Dump(spec: ChipIdentifier.iso7816Generic()) { try await DESFireCommands.apdu(iso7816, $0) }
        case .feliCa:
            throw NFCEditorError.notSupportedOnChip("Reading raw memory is not supported on FeliCa tags.")
        @unknown default:
            throw NFCEditorError.unsupportedTag("This tag type is not supported.")
        }
    }

    static func writePage(_ session: NFCTagReaderSession, _ tag: NFCTag, index: Int, bytes: Data, password: Data?) async throws {
        switch tag {
        case .miFare(let mifare) where mifare.mifareFamily != .desfire:
            guard bytes.count == 4 else {
                throw NFCEditorError.invalidInput("Enter exactly 4 bytes.")
            }
            guard (0...255).contains(index) else {
                throw NFCEditorError.invalidInput("The page must be between 0 and 255.")
            }
            if let password {
                session.alertMessage = "Authenticating."
                try await authenticate(mifare, password: password)
            }
            session.alertMessage = "Writing page \(index)."
            try await MiFareCommands.write(mifare, page: index, bytes: bytes)
        case .iso15693(let iso15693):
            session.alertMessage = "Writing block \(index)."
            try await ISO15693Commands.writeBlock(iso15693, index: index, bytes: bytes)
        default:
            throw NFCEditorError.notSupportedOnChip("Writing single pages is only available for Type 2 and Type 5 tags.")
        }
    }

    /// Writes `dump.pages` whose index is within `range` (nil = the chip's user range). Skips unreadable pages. Returns pages written.
    static func writeDump(_ session: NFCTagReaderSession, _ tag: NFCTag, dump: MemoryDump, range: ClosedRange<Int>?, password: Data?, includeSerialPages: Bool = false) async throws -> Int {
        switch tag {
        case .miFare(let mifare) where mifare.mifareFamily != .desfire:
            session.alertMessage = "Identifying the tag."
            let (spec, _) = try await identifyType2(session, mifare)
            guard spec.supportsRawPages else {
                throw NFCEditorError.notSupportedOnChip("The memory of \(spec.name) cannot be written by iOS.")
            }
            guard dump.pageSize == 4 else {
                throw NFCEditorError.invalidInput("The dump must use 4-byte pages for this tag.")
            }
            let target = range ?? spec.userPageRange ?? fallbackRange(for: dump)
            var indices = Set(dump.pages.filter { target.contains($0.index) && $0.index <= 255 && $0.readable && $0.bytes.count == 4 }.map { $0.index })
            if includeSerialPages {
                // Pages 0 and 1 hold the serial number; only magic clone chips accept a write there.
                for serialPage in [0, 1] where dump.pages.contains(where: { $0.index == serialPage && $0.readable && $0.bytes.count == 4 }) {
                    indices.insert(serialPage)
                }
            }
            let pages = dump.pages.filter { indices.contains($0.index) }.sorted { $0.index < $1.index }
            guard !pages.isEmpty else {
                throw NFCEditorError.invalidInput("The dump has no pages in the selected range.")
            }
            if let password {
                session.alertMessage = "Authenticating."
                try await authenticate(mifare, password: password)
            }
            var written = 0
            for page in pages {
                session.alertMessage = "Writing page \(page.index) (\(written + 1) of \(pages.count))."
                do {
                    try await MiFareCommands.write(mifare, page: page.index, bytes: page.bytes)
                } catch let error as NFCEditorError {
                    throw writeFailure(error, page: page.index, written: written)
                }
                written += 1
            }
            return written
        case .iso15693(let iso15693):
            session.alertMessage = "Identifying the tag."
            let system = try await ISO15693Commands.systemInfo(iso15693)
            let blockSize = system.blockSize ?? 4
            guard dump.pageSize == blockSize else {
                throw NFCEditorError.invalidInput("The dump uses \(dump.pageSize)-byte pages but this tag has \(blockSize)-byte blocks.")
            }
            let lastBlock = max(min(system.totalBlocks ?? maxProbePages, maxProbePages) - 1, 0)
            let target = range ?? (0...lastBlock)
            let pages = dump.pages.filter { target.contains($0.index) && $0.readable && $0.bytes.count == blockSize }
            guard !pages.isEmpty else {
                throw NFCEditorError.invalidInput("The dump has no blocks in the selected range.")
            }
            var written = 0
            for page in pages {
                session.alertMessage = "Writing block \(page.index) (\(written + 1) of \(pages.count))."
                do {
                    try await ISO15693Commands.writeBlock(iso15693, index: page.index, bytes: page.bytes)
                } catch let error as NFCEditorError {
                    throw writeFailure(error, page: page.index, written: written)
                }
                written += 1
            }
            return written
        default:
            throw NFCEditorError.notSupportedOnChip("Writing a memory dump is only available for Type 2 and Type 5 tags.")
        }
    }

    // MARK: Password

    static func setPassword(_ session: NFCTagReaderSession, _ tag: NFCTag, config: PasswordConfig) async throws {
        guard case .miFare(let mifare) = tag, mifare.mifareFamily != .desfire else {
            throw NFCEditorError.notSupportedOnChip("Passwords are only available on NTAG and Ultralight EV1 tags.")
        }
        guard config.password.count == 4 else {
            throw NFCEditorError.invalidInput("The password must be 4 bytes.")
        }
        guard config.pack.count == 2 else {
            throw NFCEditorError.invalidInput("The PACK must be 2 bytes.")
        }
        guard (0...7).contains(config.authLimit) else {
            throw NFCEditorError.invalidInput("Wrong attempts allowed must be between 0 and 7.")
        }
        guard (0...255).contains(config.protectFromPage) else {
            throw NFCEditorError.invalidInput("The first protected page must be between 0 and 255.")
        }

        session.alertMessage = "Identifying the tag."
        let (spec, _) = try await identifyType2(session, mifare)
        let layout = try passwordLayout(spec)
        if let current = config.currentPassword {
            session.alertMessage = "Authenticating."
            try await authenticate(mifare, password: current)
        }

        var (cfg0, cfg1) = try await readConfigPages(mifare, layout)

        session.alertMessage = "Setting the password."
        var packPage = Data(config.pack)
        packPage.append(contentsOf: [0x00, 0x00])
        try await MiFareCommands.write(mifare, page: layout.pwd, bytes: config.password)
        try await MiFareCommands.write(mifare, page: layout.pack, bytes: packPage)

        let protectBit: UInt8 = config.protectReads ? 0x80 : 0x00
        cfg1[0] = (cfg1[0] & 0x78) | protectBit | UInt8(config.authLimit & 0x07)
        try await MiFareCommands.write(mifare, page: layout.cfg1, bytes: Data(cfg1))

        // AUTH0 goes last so protection only starts once PWD, PACK and ACCESS are in place.
        cfg0[3] = UInt8(config.protectFromPage)
        try await MiFareCommands.write(mifare, page: layout.cfg0, bytes: Data(cfg0))
    }

    static func removePassword(_ session: NFCTagReaderSession, _ tag: NFCTag, currentPassword: Data) async throws {
        guard case .miFare(let mifare) = tag, mifare.mifareFamily != .desfire else {
            throw NFCEditorError.notSupportedOnChip("Passwords are only available on NTAG and Ultralight EV1 tags.")
        }
        session.alertMessage = "Identifying the tag."
        let (spec, _) = try await identifyType2(session, mifare)
        let layout = try passwordLayout(spec)

        session.alertMessage = "Authenticating."
        try await authenticate(mifare, password: currentPassword)

        var (cfg0, cfg1) = try await readConfigPages(mifare, layout)
        session.alertMessage = "Removing the password."
        cfg1[0] &= 0x78
        try await MiFareCommands.write(mifare, page: layout.cfg1, bytes: Data(cfg1))
        cfg0[3] = 0xFF
        try await MiFareCommands.write(mifare, page: layout.cfg0, bytes: Data(cfg0))
    }

    // MARK: Counter and signature

    static func readCounter(_ session: NFCTagReaderSession, _ tag: NFCTag, address: Int) async throws -> UInt32 {
        guard case .miFare(let mifare) = tag, mifare.mifareFamily != .desfire else {
            throw NFCEditorError.notSupportedOnChip("Counters are only available on NTAG and Ultralight EV1 tags.")
        }
        session.alertMessage = "Identifying the tag."
        let (spec, _) = try await identifyType2(session, mifare)
        guard spec.supportsCounter else {
            throw NFCEditorError.notSupportedOnChip("\(spec.name) has no counter.")
        }
        if isNTAG21x(spec) {
            guard address == 2 else {
                throw NFCEditorError.invalidInput("NTAG tags only have counter 2.")
            }
        } else {
            guard (0...2).contains(address) else {
                throw NFCEditorError.invalidInput("The counter address must be 0, 1 or 2.")
            }
        }
        session.alertMessage = "Reading the counter."
        do {
            return try await MiFareCommands.readCounter(mifare, address: UInt8(address))
        } catch let error as NFCEditorError {
            if case .nak = error {
                throw NFCEditorError.commandFailed("The tag refused to show the counter. It may be disabled or password protected.")
            }
            throw error
        }
    }

    static func setCounter(_ session: NFCTagReaderSession, _ tag: NFCTag, enabled: Bool, passwordProtected: Bool?, password: Data?) async throws {
        guard case .miFare(let mifare) = tag, mifare.mifareFamily != .desfire else {
            throw NFCEditorError.notSupportedOnChip("Counters are only available on NTAG tags.")
        }
        session.alertMessage = "Identifying the tag."
        let (spec, _) = try await identifyType2(session, mifare)
        guard spec.supportsCounter, isNTAG21x(spec) else {
            throw NFCEditorError.notSupportedOnChip("\(spec.name) has no NFC counter that can be switched on or off.")
        }
        let layout = try passwordLayout(spec)
        if let password {
            session.alertMessage = "Authenticating."
            try await authenticate(mifare, password: password)
        }
        var (_, cfg1) = try await readConfigPages(mifare, layout)
        session.alertMessage = enabled ? "Enabling the counter." : "Disabling the counter."
        if enabled {
            cfg1[0] |= 0x10 // NFC_CNT_EN
        } else {
            cfg1[0] &= 0xEF
        }
        // NFC_CNT_PWD_PROT makes the counter readable only after a password check; nil keeps it as it is.
        if let passwordProtected {
            if passwordProtected {
                cfg1[0] |= 0x08
            } else {
                cfg1[0] &= 0xF7
            }
        }
        try await MiFareCommands.write(mifare, page: layout.cfg1, bytes: Data(cfg1))
    }

    static func readSignature(_ session: NFCTagReaderSession, _ tag: NFCTag) async throws -> Data {
        guard case .miFare(let mifare) = tag, mifare.mifareFamily != .desfire else {
            throw NFCEditorError.notSupportedOnChip("Signatures are only available on NTAG and Ultralight EV1 tags.")
        }
        session.alertMessage = "Identifying the tag."
        let (spec, _) = try await identifyType2(session, mifare)
        guard spec.supportsSignature else {
            throw NFCEditorError.notSupportedOnChip("\(spec.name) has no originality signature.")
        }
        session.alertMessage = "Reading the signature."
        return try await MiFareCommands.readSignature(mifare)
    }

    // MARK: Raw commands

    static func sendRaw(_ session: NFCTagReaderSession, _ tag: NFCTag, commands: [RawCommand]) async throws -> [RawResponse] {
        guard !commands.isEmpty else {
            throw NFCEditorError.invalidInput("Enter at least one command.")
        }
        var responses: [RawResponse] = []
        for (position, command) in commands.enumerated() {
            session.alertMessage = "Sending command \(position + 1) of \(commands.count)."
            let started = Date()
            do {
                var response = try await send(command, to: tag)
                response.elapsedMS = Int(Date().timeIntervalSince(started) * 1000)
                responses.append(response)
            } catch {
                let mapped = NFCEditorError.map(error)
                if isSessionError(mapped) { throw mapped }
                throw NFCEditorError.commandFailed("Command \(position + 1) failed: \(mapped.errorDescription ?? "Unknown error.")")
            }
        }
        return responses
    }

    /// Picks the transport for Advanced commands based on the tag type.
    static func defaultTransport(for tag: NFCTag) -> RawTransport {
        switch tag {
        case .miFare(let mifare):
            return mifare.mifareFamily == .desfire ? .apdu : .mifare
        case .iso7816:
            return .apdu
        case .iso15693:
            return .iso15693
        case .feliCa:
            return .feliCa
        @unknown default:
            return .mifare
        }
    }

    /// Quick chip identification without reading everything. Used by Tools views to show "NTAG216 detected".
    static func identify(_ session: NFCTagReaderSession, _ tag: NFCTag) async throws -> (ChipSpec, Data) {
        session.alertMessage = "Identifying the tag."
        switch tag {
        case .miFare(let mifare):
            if mifare.mifareFamily == .desfire {
                let (spec, _) = try await desfireSpec(mifare)
                return (spec, Data(mifare.identifier))
            }
            let (spec, _) = try await identifyType2(session, mifare)
            return (spec, Data(mifare.identifier))
        case .iso15693(let iso15693):
            let system = try await ISO15693Commands.systemInfo(iso15693)
            return (iso15693Spec(iso15693, system), system.uid)
        case .feliCa(let feliCa):
            let info = try await FeliCaCommands.info(feliCa)
            return (ChipIdentifier.feliCa(systemCode: info.systemCode), info.idm)
        case .iso7816(let iso7816):
            return (ChipIdentifier.iso7816Generic(), Data(iso7816.identifier))
        @unknown default:
            throw NFCEditorError.unsupportedTag("This tag type is not supported.")
        }
    }

    // MARK: NDEF read only flag and configuration lock

    /// Marks the tag read only for NDEF without burning the lock bits: Type 2 sets the OTP read only
    /// bit in the capability container, Type 5 sets the read only nibble of block 0.
    static func setNDEFReadOnlyFlag(_ session: NFCTagReaderSession, _ tag: NFCTag) async throws {
        switch tag {
        case .miFare(let mifare) where mifare.mifareFamily != .desfire:
            session.alertMessage = "Reading the capability container."
            let page = try await MiFareCommands.read(mifare, page: 3).bytes
            guard page.count >= 4 else {
                throw NFCEditorError.commandFailed("The capability container could not be read.")
            }
            var cc = Array(page[0..<4])
            cc[3] |= 0x0F
            session.alertMessage = "Setting the read only flag."
            try await MiFareCommands.write(mifare, page: 3, bytes: Data(cc))
        case .iso15693(let iso15693):
            session.alertMessage = "Reading the capability container."
            let blocks = try await ISO15693Commands.readBlocks(iso15693, from: 0, to: 0, progress: nil)
            guard let block = blocks.first, block.readable, block.bytes.count >= 2 else {
                throw NFCEditorError.commandFailed("The capability container could not be read.")
            }
            var bytes = block.bytes.bytes
            bytes[1] = (bytes[1] & 0xF0) | 0x0F
            session.alertMessage = "Setting the read only flag."
            try await ISO15693Commands.writeBlock(iso15693, index: 0, bytes: Data(bytes))
        default:
            throw NFCEditorError.notSupportedOnChip("The NDEF read only flag is only available on Type 2 and Type 5 tags.")
        }
    }

    /// Burns CFGLCK so the configuration pages can never be changed again. Irreversible.
    static func lockConfiguration(_ session: NFCTagReaderSession, _ tag: NFCTag, password: Data?) async throws {
        let mifare = try mifareType2(tag)
        session.alertMessage = "Identifying the tag."
        let (spec, _) = try await identifyType2(session, mifare)
        let layout = try passwordLayout(spec)
        if let password {
            session.alertMessage = "Authenticating."
            try await authenticate(mifare, password: password)
        }
        var (_, cfg1) = try await readConfigPages(mifare, layout)
        session.alertMessage = "Locking the configuration."
        cfg1[0] |= 0x40 // CFGLCK
        try await MiFareCommands.write(mifare, page: layout.cfg1, bytes: Data(cfg1))
    }

    // MARK: Tamper, lock pages and lock state

    static func readTamperStatus(_ session: NFCTagReaderSession, _ tag: NFCTag) async throws -> Data {
        let mifare = try mifareType2(tag)
        session.alertMessage = "Identifying the tag."
        let (spec, _) = try await identifyType2(session, mifare)
        guard spec.name.contains("TT") else {
            throw NFCEditorError.notSupportedOnChip("Only the NTAG 213TT reports a tamper status.")
        }
        session.alertMessage = "Reading the tamper status."
        let response = try await MiFareCommands.transceive(mifare, Data([0xA4, 0x00]), expectAck: false)
        guard response.count >= 5 else {
            throw NFCEditorError.commandFailed("The tamper status answer was too short.")
        }
        return Data(response.prefix(5))
    }

    static func lockPages(_ session: NFCTagReaderSession, _ tag: NFCTag, groups: [PageLock], password: Data?) async throws {
        let mifare = try mifareType2(tag)
        session.alertMessage = "Identifying the tag."
        let (spec, _) = try await identifyType2(session, mifare)
        guard spec.supportsRawPages else {
            throw NFCEditorError.notSupportedOnChip("Lock bits are not available on \(spec.name).")
        }
        if let password {
            session.alertMessage = "Authenticating."
            try await authenticate(mifare, password: password)
        }

        session.alertMessage = "Reading the current lock bytes."
        let page2 = try await MiFareCommands.read(mifare, page: 2).bytes
        guard page2.count >= 4 else {
            throw NFCEditorError.commandFailed("The static lock bytes could not be read.")
        }
        let staticLock = Data(page2[2..<4])

        var dynamicLock: Data?
        var dynamicTail: UInt8 = 0
        if let dynamicPage = spec.dynamicLockPage {
            let dynamic = try await MiFareCommands.read(mifare, page: dynamicPage).bytes
            guard dynamic.count >= 4 else {
                throw NFCEditorError.commandFailed("The dynamic lock bytes could not be read.")
            }
            dynamicLock = Data(dynamic[0..<3])
            dynamicTail = dynamic[3]
        }

        let result = LockBits.bytesToLock(groups: groups, chip: spec, staticLock: staticLock, dynamicLock: dynamicLock)
        let lockBytes = result.page2LockBytes.bytes
        guard lockBytes.count == 2 else {
            throw NFCEditorError.failed("The lock bytes could not be prepared.")
        }

        session.alertMessage = "Locking the pages."
        var newPage2 = Array(page2[0..<4])
        newPage2[2] = lockBytes[0]
        newPage2[3] = lockBytes[1]
        try await MiFareCommands.write(mifare, page: 2, bytes: Data(newPage2))

        if let dynamicPage = spec.dynamicLockPage, let dynamic = result.dynamic, dynamic.count == 3 {
            var block = dynamic.bytes
            block.append(dynamicTail)
            try await MiFareCommands.write(mifare, page: dynamicPage, bytes: Data(block.prefix(4)))
        }
    }

    static func lockState(_ session: NFCTagReaderSession, _ tag: NFCTag) async throws -> [PageLock] {
        let mifare = try mifareType2(tag)
        session.alertMessage = "Identifying the tag."
        let (spec, _) = try await identifyType2(session, mifare)
        guard spec.supportsRawPages else {
            throw NFCEditorError.notSupportedOnChip("Lock bits are not available on \(spec.name).")
        }
        session.alertMessage = "Reading the lock state."
        let page2 = try await MiFareCommands.read(mifare, page: 2).bytes
        guard page2.count >= 4 else {
            throw NFCEditorError.commandFailed("The static lock bytes could not be read.")
        }
        let staticLock = Data(page2[2..<4])

        var dynamicLock: Data?
        if let dynamicPage = spec.dynamicLockPage {
            if let dynamic = try await probe(session, mifare, { try await MiFareCommands.read(mifare, page: dynamicPage) }), dynamic.count >= 3 {
                dynamicLock = Data(dynamic.prefix(3))
            }
        }
        return LockBits.groups(chip: spec, staticLock: staticLock, dynamicLock: dynamicLock)
    }

    // MARK: Ultralight C

    static func ultralightCAuthenticate(_ session: NFCTagReaderSession, _ tag: NFCTag, key: Data) async throws {
        let mifare = try mifareType2(tag)
        try checkUltralightCKey(key)
        session.alertMessage = "Authenticating."
        try await UltralightC.authenticate(mifare, key: key)
    }

    static func ultralightCSetKey(_ session: NFCTagReaderSession, _ tag: NFCTag, currentKey: Data, newKey: Data, firstPage: Int, writeOnly: Bool) async throws {
        let mifare = try mifareType2(tag)
        try checkUltralightCKey(currentKey)
        try checkUltralightCKey(newKey)
        session.alertMessage = "Authenticating."
        try await UltralightC.authenticate(mifare, key: currentKey)
        session.alertMessage = "Writing the new key."
        try await UltralightC.writeKey(mifare, key: newKey)
        session.alertMessage = "Setting the protection."
        try await UltralightC.setProtection(mifare, firstPage: firstPage, writeOnly: writeOnly)
    }

    static func ultralightCRemoveProtection(_ session: NFCTagReaderSession, _ tag: NFCTag, key: Data) async throws {
        let mifare = try mifareType2(tag)
        try checkUltralightCKey(key)
        session.alertMessage = "Authenticating."
        try await UltralightC.authenticate(mifare, key: key)
        session.alertMessage = "Removing the protection."
        try await UltralightC.removeProtection(mifare)
    }

    // MARK: Mirror

    static func writeMirroredURL(_ session: NFCTagReaderSession, _ tag: NFCTag, url: String, kind: MirrorKind, password: Data?) async throws -> String {
        let mifare = try mifareType2(tag)
        session.alertMessage = "Identifying the tag."
        let (spec, _) = try await identifyType2(session, mifare)
        return try await NTAGMirror.writeMirroredURL(session, mifare, chip: spec, url: url, kind: kind, password: password)
    }

    static func readMirror(_ session: NFCTagReaderSession, _ tag: NFCTag) async throws -> MirrorConfig {
        let mifare = try mifareType2(tag)
        session.alertMessage = "Identifying the tag."
        let (spec, _) = try await identifyType2(session, mifare)
        session.alertMessage = "Reading the mirror setting."
        return try await NTAGMirror.read(mifare, chip: spec)
    }

    static func disableMirror(_ session: NFCTagReaderSession, _ tag: NFCTag, password: Data?) async throws {
        let mifare = try mifareType2(tag)
        session.alertMessage = "Identifying the tag."
        let (spec, _) = try await identifyType2(session, mifare)
        if let password {
            session.alertMessage = "Authenticating."
            try await authenticate(mifare, password: password)
        }
        session.alertMessage = "Turning the mirror off."
        try await NTAGMirror.disable(mifare, chip: spec)
    }

    // MARK: DESFire

    static func desfireOverview(_ session: NFCTagReaderSession, _ tag: NFCTag) async throws -> DESFireOverview {
        let mifare = try desfireTag(tag)
        session.alertMessage = "Reading the card."
        var overview = DESFireOverview(version: nil, applications: [], freeMemory: nil, keySettings: nil, maxKeys: nil, hasNDEFApplication: false)
        overview.version = (try await attempt { try await DESFireCommands.getVersion(mifare) })?.raw
        _ = try await attempt { try await DESFireCommands.selectApplication(mifare, aid: Data([0x00, 0x00, 0x00])) }
        if let applications = try await attempt({ try await DESFireCommands.getApplicationIDs(mifare) }) {
            overview.applications = applications
            overview.hasNDEFApplication = applications.contains(Data([0x01, 0x00, 0x00]))
        }
        if let free = try await attempt({ try await DESFireCommands.getFreeMemory(mifare) }), let bytes = free {
            overview.freeMemory = bytes
        }
        if let settings = try await attempt({ try await DESFireCommands.getKeySettings(mifare) }) {
            overview.keySettings = settings.settings
            overview.maxKeys = settings.maxKeys
        }
        return overview
    }

    static func desfireFormat(_ session: NFCTagReaderSession, _ tag: NFCTag, masterKey: Data) async throws {
        let mifare = try desfireTag(tag)
        session.alertMessage = "Selecting the card."
        try await DESFireCommands.selectApplication(mifare, aid: Data([0x00, 0x00, 0x00]))
        session.alertMessage = "Authenticating with the master key."
        _ = try await DESFireCommands.authenticateLegacy(mifare, keyNumber: 0, key: masterKey)
        session.alertMessage = "Formatting the card."
        try await DESFireCommands.formatPICC(mifare)
    }

    static func desfireCreateNDEFApplication(_ session: NFCTagReaderSession, _ tag: NFCTag, masterKey: Data, formatFirst: Bool, ndefFileSize: Int) async throws {
        let mifare = try desfireTag(tag)
        try await DESFireCommands.createNDEFApplication(session, mifare, masterKey: masterKey, formatFirst: formatFirst, ndefFileSize: ndefFileSize)
    }

    // MARK: Type 5 settings

    static func type5Settings(_ session: NFCTagReaderSession, _ tag: NFCTag) async throws -> Type5Settings {
        let iso15693 = try iso15693Target(tag)
        session.alertMessage = "Reading the settings."
        let system = try await ISO15693Commands.systemInfo(iso15693)
        let blockSize = system.blockSize ?? 4
        let totalBlocks = system.totalBlocks ?? 0
        var lockedBlocks: [Bool] = []
        if totalBlocks > 0 {
            let count = min(totalBlocks, maxProbePages)
            lockedBlocks = (try await attempt { try await ISO15693Commands.blockSecurityStatus(iso15693, from: 0, to: count - 1) }) ?? []
        }
        let spec = iso15693Spec(iso15693, system)
        let isSLIX = spec.family == .icodeSLIX || spec.family == .icodeSLIX2 || spec.family == .icodeSLI || spec.family == .icodeDNA
        let isST = spec.family == .st25TV || spec.family == .st25TA
        return Type5Settings(dsfid: system.dsfid, afi: system.afi, blockSize: blockSize, totalBlocks: totalBlocks, lockedBlocks: lockedBlocks, isSLIX: isSLIX, isST: isST)
    }

    static func type5WriteAFI(_ session: NFCTagReaderSession, _ tag: NFCTag, afi: UInt8, lock: Bool) async throws {
        let iso15693 = try iso15693Target(tag)
        session.alertMessage = "Writing the AFI."
        try await ISO15693Commands.writeAFI(iso15693, afi: afi)
        if lock {
            session.alertMessage = "Locking the AFI."
            try await ISO15693Commands.lockAFI(iso15693)
        }
    }

    static func type5WriteDSFID(_ session: NFCTagReaderSession, _ tag: NFCTag, dsfid: UInt8, lock: Bool) async throws {
        let iso15693 = try iso15693Target(tag)
        session.alertMessage = "Writing the DSFID."
        try await ISO15693Commands.writeDSFID(iso15693, dsfid: dsfid)
        if lock {
            session.alertMessage = "Locking the DSFID."
            try await ISO15693Commands.lockDSFID(iso15693)
        }
    }

    static func type5LockBlocks(_ session: NFCTagReaderSession, _ tag: NFCTag, blocks: [Int]) async throws {
        let iso15693 = try iso15693Target(tag)
        guard !blocks.isEmpty else {
            throw NFCEditorError.invalidInput("Choose at least one block to lock.")
        }
        var done = 0
        for block in blocks {
            session.alertMessage = "Locking block \(block) (\(done + 1) of \(blocks.count))."
            try await ISO15693Commands.lockBlock(iso15693, index: block)
            done += 1
        }
    }

    // MARK: ICODE SLIX

    static func slixSetPassword(_ session: NFCTagReaderSession, _ tag: NFCTag, identifier: SLIXPassword, currentPassword: Data?, newPassword: Data) async throws {
        let iso15693 = try iso15693Target(tag)
        if let currentPassword {
            session.alertMessage = "Presenting the current password."
            try await ISO15693Commands.slixSetPassword(iso15693, identifier: identifier, password: currentPassword)
        }
        session.alertMessage = "Writing the new password."
        try await ISO15693Commands.slixWritePassword(iso15693, identifier: identifier, password: newPassword)
    }

    static func slixPresentPassword(_ session: NFCTagReaderSession, _ tag: NFCTag, identifier: SLIXPassword, password: Data) async throws {
        let iso15693 = try iso15693Target(tag)
        session.alertMessage = "Presenting the password."
        try await ISO15693Commands.slixSetPassword(iso15693, identifier: identifier, password: password)
    }

    static func slixSetPrivacy(_ session: NFCTagReaderSession, _ tag: NFCTag, enabled: Bool, password: Data) async throws {
        let iso15693 = try iso15693Target(tag)
        session.alertMessage = "Presenting the privacy password."
        try await ISO15693Commands.slixSetPassword(iso15693, identifier: .privacy, password: password)
        if enabled {
            session.alertMessage = "Turning privacy mode on."
            try await ISO15693Commands.slixEnablePrivacy(iso15693)
        }
    }

    static func slixSetEAS(_ session: NFCTagReaderSession, _ tag: NFCTag, enabled: Bool) async throws {
        let iso15693 = try iso15693Target(tag)
        if enabled {
            session.alertMessage = "Turning EAS on."
            try await ISO15693Commands.slixSetEAS(iso15693)
        } else {
            session.alertMessage = "Turning EAS off."
            try await ISO15693Commands.slixResetEAS(iso15693)
        }
    }

    static func slixEASAlarm(_ session: NFCTagReaderSession, _ tag: NFCTag) async throws -> Bool {
        let iso15693 = try iso15693Target(tag)
        session.alertMessage = "Checking the EAS alarm."
        let alarm = try await ISO15693Commands.slixEASAlarm(iso15693)
        return !alarm.isEmpty
    }

    static func slixDestroy(_ session: NFCTagReaderSession, _ tag: NFCTag, password: Data) async throws {
        let iso15693 = try iso15693Target(tag)
        session.alertMessage = "Destroying the tag."
        try await ISO15693Commands.slixDestroy(iso15693, password: password)
    }

    // MARK: ST25TV

    static func stPresentPassword(_ session: NFCTagReaderSession, _ tag: NFCTag, number: UInt8, password: Data) async throws {
        let iso15693 = try iso15693Target(tag)
        session.alertMessage = "Presenting the password."
        try await ISO15693Commands.stPresentPassword(iso15693, number: number, password: password)
    }

    static func stWritePassword(_ session: NFCTagReaderSession, _ tag: NFCTag, number: UInt8, password: Data) async throws {
        let iso15693 = try iso15693Target(tag)
        session.alertMessage = "Writing the password."
        try await ISO15693Commands.stWritePassword(iso15693, number: number, password: password)
    }

    // MARK: FeliCa

    static func feliCaRead(_ session: NFCTagReaderSession, _ tag: NFCTag, serviceCode: UInt16, blocks: [Int]) async throws -> [Data] {
        let feliCa = try feliCaTarget(tag)
        session.alertMessage = "Reading the blocks."
        return try await FeliCaCommands.readWithoutEncryption(feliCa, serviceCode: serviceCode, blocks: blocks)
    }

    static func feliCaWrite(_ session: NFCTagReaderSession, _ tag: NFCTag, serviceCode: UInt16, block: Int, data: Data) async throws {
        let feliCa = try feliCaTarget(tag)
        session.alertMessage = "Writing block \(block)."
        try await FeliCaCommands.writeWithoutEncryption(feliCa, serviceCode: serviceCode, block: block, data: data)
    }

    static func feliCaServices(_ session: NFCTagReaderSession, _ tag: NFCTag, serviceCodes: [UInt16]) async throws -> [UInt16] {
        let feliCa = try feliCaTarget(tag)
        session.alertMessage = "Checking the services."
        return try await FeliCaCommands.requestService(feliCa, serviceCodes: serviceCodes)
    }

    // MARK: Tag kind helpers

    private static func mifareType2(_ tag: NFCTag) throws -> NFCMiFareTag {
        guard case .miFare(let mifare) = tag, mifare.mifareFamily != .desfire else {
            throw NFCEditorError.notSupportedOnChip("This feature needs an NTAG or Ultralight tag.")
        }
        return mifare
    }

    private static func desfireTag(_ tag: NFCTag) throws -> NFCMiFareTag {
        guard case .miFare(let mifare) = tag, mifare.mifareFamily == .desfire else {
            throw NFCEditorError.notSupportedOnChip("This feature needs a DESFire tag.")
        }
        return mifare
    }

    private static func iso15693Target(_ tag: NFCTag) throws -> NFCISO15693Tag {
        guard case .iso15693(let iso15693) = tag else {
            throw NFCEditorError.notSupportedOnChip("This feature needs an ISO 15693 (Type 5) tag.")
        }
        return iso15693
    }

    private static func feliCaTarget(_ tag: NFCTag) throws -> NFCFeliCaTag {
        guard case .feliCa(let feliCa) = tag else {
            throw NFCEditorError.notSupportedOnChip("This feature needs a FeliCa tag.")
        }
        return feliCa
    }

    private static func checkUltralightCKey(_ key: Data) throws {
        guard key.count == 16 else {
            throw NFCEditorError.invalidInput("An Ultralight C key is 16 bytes.")
        }
    }

    // MARK: Identification helpers

    private static func identifyType2(_ session: NFCTagReaderSession, _ tag: NFCMiFareTag) async throws -> (ChipSpec, Data?) {
        if tag.mifareFamily == .plus {
            var spec = ChipIdentifier.unknownType2()
            spec.name = "MIFARE Plus"
            spec.family = .mifarePlus
            spec.supportsRawPages = false
            spec.notes = "MIFARE Plus memory cannot be read by iOS."
            return (spec, nil)
        }

        if let version = try await probe(session, tag, { try await MiFareCommands.getVersion(tag) }) {
            if let spec = ChipIdentifier.fromGetVersion(version) {
                return (spec, version)
            }
            var spec = ChipIdentifier.unknownType2()
            spec.notes = "The GET_VERSION response was not recognized."
            return (spec, version)
        }

        guard try await canRead(session, tag, page: 0) else {
            var spec = ChipIdentifier.unknownType2()
            spec.name = "Unsupported MIFARE tag"
            spec.supportsRawPages = false
            spec.notes = "iOS cannot read this tag. MIFARE Classic is not supported."
            return (spec, nil)
        }
        let canReadPage16 = try await canRead(session, tag, page: 0x10)
        var canReadPage42 = false
        if canReadPage16 {
            canReadPage42 = try await canRead(session, tag, page: 0x2A)
        }
        return (ChipIdentifier.legacyType2(canReadPage16: canReadPage16, canReadPage42: canReadPage42), nil)
    }

    private static func canRead(_ session: NFCTagReaderSession, _ tag: NFCMiFareTag, page: Int) async throws -> Bool {
        let data = try await probe(session, tag, { try await MiFareCommands.read(tag, page: page) })
        return data != nil
    }

    private static func desfireSpec(_ tag: NFCMiFareTag) async throws -> (ChipSpec, DESFireCommands.Version?) {
        if let version = try await attempt({ try await DESFireCommands.getVersion(tag) }) {
            if let spec = ChipIdentifier.fromDESFireVersion(hardware: version.hardware) {
                return (spec, version)
            }
            return (genericDESFire(), version)
        }
        return (genericDESFire(), nil)
    }

    private static func genericDESFire() -> ChipSpec {
        var spec = ChipIdentifier.iso7816Generic()
        spec.name = "MIFARE DESFire"
        spec.manufacturer = "NXP"
        spec.family = .desfire
        spec.nfcForumType = 4
        spec.isoStandard = "ISO 14443-4A"
        spec.supportsRawPages = false
        spec.atqa = 0x0344
        spec.sak = 0x20
        return spec
    }

    private static func iso15693Spec(_ tag: NFCISO15693Tag, _ system: ISO15693Commands.SystemInfo) -> ChipSpec {
        let bytes = system.uid.bytes
        var manufacturer = tag.icManufacturerCode
        if manufacturer <= 0, bytes.count > 1 {
            manufacturer = Int(bytes[1])
        }
        return ChipIdentifier.iso15693(
            uid: system.uid,
            icManufacturerCode: manufacturer,
            icReference: system.icReference,
            blockSize: system.blockSize,
            totalBlocks: system.totalBlocks
        )
    }

    // MARK: Dump helpers

    private static func dumpType2(_ session: NFCTagReaderSession, _ tag: NFCMiFareTag, _ spec: ChipSpec) async throws -> [MemoryPage] {
        guard let total = spec.totalPages, total > 0 else {
            return try await readType2UntilNAK(session, tag)
        }
        let count = min(total, maxProbePages)
        session.alertMessage = "Reading page 0 of \(count)."
        return try await MiFareCommands.readPages(tag, from: 0, to: count - 1, pageSize: 4) { done in
            if done % 8 == 0 || done == count {
                session.alertMessage = "Reading page \(min(done, count)) of \(count)."
            }
        }
    }

    private static func readType2UntilNAK(_ session: NFCTagReaderSession, _ tag: NFCMiFareTag) async throws -> [MemoryPage] {
        var pages: [MemoryPage] = []
        var page = 0
        while page < maxProbePages {
            let current = page
            guard let data = try await probe(session, tag, { try await MiFareCommands.read(tag, page: current) }) else { break }
            let bytes = data.bytes
            for offset in 0..<4 where current + offset < maxProbePages {
                let start = offset * 4
                guard bytes.count >= start + 4 else { break }
                pages.append(MemoryPage(index: current + offset, bytes: Data(bytes[start..<start + 4]), readable: true))
            }
            page += 4
            session.alertMessage = "Reading page \(page)."
        }
        return pages
    }

    private static func dumpISO15693(_ session: NFCTagReaderSession, _ tag: NFCISO15693Tag, _ system: ISO15693Commands.SystemInfo) async throws -> [MemoryPage] {
        guard let total = system.totalBlocks, total > 0 else {
            return try await readISO15693UntilFailure(session, tag)
        }
        let count = min(total, maxProbePages)
        session.alertMessage = "Reading block 0 of \(count)."
        return try await ISO15693Commands.readBlocks(tag, from: 0, to: count - 1) { done in
            if done % 8 == 0 || done == count {
                session.alertMessage = "Reading block \(min(done, count)) of \(count)."
            }
        }
    }

    private static func readISO15693UntilFailure(_ session: NFCTagReaderSession, _ tag: NFCISO15693Tag) async throws -> [MemoryPage] {
        var pages: [MemoryPage] = []
        for block in 0..<maxProbePages {
            let result = try await ISO15693Commands.readBlocks(tag, from: block, to: block, progress: nil)
            guard let page = result.first, page.readable else { break }
            pages.append(page)
            if block % 8 == 7 {
                session.alertMessage = "Reading block \(block + 1)."
            }
        }
        return pages
    }

    private static func type4Dump(spec: ChipSpec, send: @escaping (NFCISO7816APDU) async throws -> (Data, UInt8, UInt8)) async throws -> MemoryDump {
        guard let bytes = try await DESFireCommands.readNDEFFile(send: send) else {
            throw NFCEditorError.notSupportedOnChip("No NDEF application was found on this tag.")
        }
        var dumpSpec = spec
        dumpSpec.pageSize = 16
        return MemoryDump(flatBytes: bytes, pageSize: 16, chip: dumpSpec)
    }

    private static func fallbackRange(for dump: MemoryDump) -> ClosedRange<Int> {
        let highest = dump.pages.map { $0.index }.max() ?? 4
        return 4...max(4, highest)
    }

    // MARK: Format helpers

    private static func formatIfBlank(_ session: NFCTagReaderSession, _ tag: NFCMiFareTag) async throws -> Bool {
        let (spec, _) = try await identifyType2(session, tag)
        guard spec.supportsRawPages, spec.capabilityContainer != nil, spec.userPageRange != nil else { return false }
        guard let header = try await probe(session, tag, { try await MiFareCommands.read(tag, page: 0) }), header.count >= 16 else { return false }
        let page3 = Array(header.bytes[12..<16])
        guard page3.allSatisfy({ $0 == 0 }) else { return false }
        try await formatType2(session, tag, spec)
        return true
    }

    private static func formatType2(_ session: NFCTagReaderSession, _ tag: NFCMiFareTag, _ spec: ChipSpec) async throws {
        guard spec.supportsRawPages, let range = spec.userPageRange else {
            throw NFCEditorError.notSupportedOnChip("The memory layout of \(spec.name) is not known, so it cannot be formatted.")
        }
        session.alertMessage = "Checking the capability container."
        let header = try await MiFareCommands.read(tag, page: 0).bytes
        guard header.count >= 16 else {
            throw NFCEditorError.commandFailed("The tag returned a short response.")
        }
        let page3 = Array(header[12..<16])
        if page3.allSatisfy({ $0 == 0 }) {
            guard let container = spec.capabilityContainer else {
                throw NFCEditorError.notSupportedOnChip("No capability container is known for \(spec.name).")
            }
            session.alertMessage = "Writing the capability container."
            try await MiFareCommands.write(tag, page: 3, bytes: container)
        } else if page3[0] != 0xE1 {
            // Page 3 is one time programmable, so a wrong value there cannot be repaired.
            throw NFCEditorError.failed("Page 3 holds data that is not a capability container, and it cannot be changed.")
        }
        session.alertMessage = "Formatting."
        try await MiFareCommands.write(tag, page: range.lowerBound, bytes: emptyTLV)
        try await zeroPages(session, tag, from: range.lowerBound + 1, to: range.upperBound)
    }

    private static func zeroPages(_ session: NFCTagReaderSession, _ tag: NFCMiFareTag, from: Int, to: Int) async throws {
        // Pages above 255 need a sector select that iOS does not expose, so NTAG I2C 2k stops at the first sector.
        let last = min(to, 255)
        guard from <= last else { return }
        let total = last - from + 1
        for (done, page) in (from...last).enumerated() {
            if done % 4 == 0 || done == total - 1 {
                session.alertMessage = "Writing page \(done + 1) of \(total)."
            }
            do {
                try await MiFareCommands.write(tag, page: page, bytes: zeroPage)
            } catch let error as NFCEditorError {
                throw writeFailure(error, page: page, written: done)
            }
        }
    }

    /// Lays out a Type 5 tag: capability container (kept when present), an empty NDEF TLV, zeros everywhere else.
    private static func layoutISO15693(_ session: NFCTagReaderSession, _ tag: NFCISO15693Tag, writeCapabilityContainer: Bool) async throws {
        session.alertMessage = "Identifying the tag."
        let system = try await ISO15693Commands.systemInfo(tag)
        guard let blockSize = system.blockSize, let total = system.totalBlocks, blockSize > 0, total > 0 else {
            throw NFCEditorError.notSupportedOnChip("The memory size of this tag is not known.")
        }
        let blockCount = min(total, maxProbePages)
        let memoryBytes = blockCount * blockSize

        session.alertMessage = "Checking the capability container."
        let first = try await ISO15693Commands.readBlocks(tag, from: 0, to: min(1, blockCount - 1), progress: nil)
        let existing = first.flatMap { $0.readable ? $0.bytes.bytes : [UInt8](repeating: 0, count: blockSize) }

        // Block 0 is not one time programmable on Type 5 tags, so a fresh CC replaces anything that is not already one.
        var image: [UInt8] = []
        if existing.first == 0xE2 {
            image = Array(existing.prefix(8)) + emptyTLV.bytes
        } else if existing.first == 0xE1 {
            image = Array(existing.prefix(4)) + emptyTLV.bytes
        } else if writeCapabilityContainer {
            image = [0xE1, 0x40, UInt8(min(memoryBytes / 8, 0xFF)), 0x00] + emptyTLV.bytes
        }
        if image.count < memoryBytes {
            image.append(contentsOf: [UInt8](repeating: 0, count: memoryBytes - image.count))
        }

        for block in 0..<blockCount {
            let start = block * blockSize
            let end = min(start + blockSize, image.count)
            guard start < end else { break }
            let bytes = Data(image[start..<end])
            if block < first.count, first[block].readable, first[block].bytes == bytes {
                continue
            }
            if block % 4 == 0 || block == blockCount - 1 {
                session.alertMessage = "Writing block \(block + 1) of \(blockCount)."
            }
            do {
                try await ISO15693Commands.writeBlock(tag, index: block, bytes: bytes)
            } catch let error as NFCEditorError {
                throw writeFailure(error, page: block, written: block)
            }
        }
    }

    // MARK: Password helpers

    private static func passwordLayout(_ spec: ChipSpec) throws -> PasswordLayout {
        guard spec.supportsPassword, let cfg0 = spec.cfg0Page, let cfg1 = spec.cfg1Page, let pwd = spec.pwdPage, let pack = spec.packPage else {
            throw NFCEditorError.notSupportedOnChip("\(spec.name) does not support password protection.")
        }
        return PasswordLayout(cfg0: cfg0, cfg1: cfg1, pwd: pwd, pack: pack)
    }

    /// Returns the 4 bytes of CFG0 and CFG1. One READ at CFG0 covers both pages.
    private static func readConfigPages(_ tag: NFCMiFareTag, _ layout: PasswordLayout) async throws -> ([UInt8], [UInt8]) {
        let data: Data
        do {
            data = try await MiFareCommands.read(tag, page: layout.cfg0)
        } catch let error as NFCEditorError {
            if case .nak = error {
                throw NFCEditorError.failed("The tag refused to show its configuration. If it is already protected, enter the current password.")
            }
            throw error
        }
        let bytes = data.bytes
        guard bytes.count >= 8 else {
            throw NFCEditorError.commandFailed("The configuration pages could not be read.")
        }
        return (Array(bytes[0..<4]), Array(bytes[4..<8]))
    }

    private static func authenticate(_ tag: NFCMiFareTag, password: Data) async throws {
        guard password.count == 4 else {
            throw NFCEditorError.invalidInput("The password must be 4 bytes.")
        }
        _ = try await MiFareCommands.pwdAuth(tag, password: password)
    }

    // MARK: NDEF helpers

    private static func ndefTag(for tag: NFCTag) throws -> any NFCNDEFTag {
        switch tag {
        case .miFare(let mifare):
            return mifare
        case .iso15693(let iso15693):
            return iso15693
        case .feliCa(let feliCa):
            return feliCa
        case .iso7816(let iso7816):
            return iso7816
        @unknown default:
            throw NFCEditorError.unsupportedTag("This tag type is not supported.")
        }
    }

    private static func queryStatus(_ tag: any NFCNDEFTag) async throws -> (NFCNDEFStatus, Int) {
        do {
            return try await tag.queryNDEFStatus()
        } catch {
            throw NFCEditorError.map(error)
        }
    }

    private static func writeMessage(_ tag: any NFCNDEFTag, _ records: [NDEFRecord]) async throws {
        do {
            try await tag.writeNDEF(records.nfcMessage)
        } catch {
            throw NFCEditorError.map(error)
        }
    }

    private static func readMessage(_ tag: any NFCNDEFTag) async throws -> [NDEFRecord] {
        do {
            let message = try await tag.readNDEF()
            return [NDEFRecord](message: message)
        } catch {
            throw NFCEditorError.map(error)
        }
    }

    private static func readNDEFContent(_ tag: any NFCNDEFTag) async throws -> NDEFContent {
        var content = NDEFContent(status: .notSupported, capacity: nil, records: [])
        guard let queried = try await attempt({ try await tag.queryNDEFStatus() }) else { return content }
        switch queried.0 {
        case .notSupported:
            return content
        case .readWrite:
            content.status = .readWrite
        case .readOnly:
            content.status = .readOnly
        @unknown default:
            content.status = .unknown
        }
        content.capacity = queried.1 > 0 ? queried.1 : nil
        // An empty but formatted tag throws a zero length error here; that just means no records.
        if let message = try await attempt({ try await tag.readNDEF() }) {
            content.records = [NDEFRecord](message: message)
        }
        return content
    }

    private static func apply(_ content: NDEFContent, to info: inout TagInfo) {
        info.ndefStatus = content.status
        info.ndefCapacity = content.capacity
        info.records = content.records
        if content.status == .notSupported {
            info.ndefUsedBytes = nil
        } else {
            info.ndefUsedBytes = content.records.isEmpty ? 0 : NDEFMessageCodec.byteCount(content.records)
        }
    }

    // MARK: Raw helpers

    private static func send(_ command: RawCommand, to tag: NFCTag) async throws -> RawResponse {
        guard !command.bytes.isEmpty else {
            throw NFCEditorError.invalidInput("The command is empty.")
        }
        switch command.transport {
        case .mifare:
            guard case .miFare(let mifare) = tag else {
                throw NFCEditorError.notSupportedOnChip("MIFARE commands need an NTAG, Ultralight or DESFire tag.")
            }
            let data = try await MiFareCommands.transceive(mifare, command.bytes, expectAck: false)
            return RawResponse(bytes: data, sw1: nil, sw2: nil, elapsedMS: 0)
        case .apdu:
            guard let apdu = NFCISO7816APDU(data: command.bytes) else {
                throw NFCEditorError.invalidInput("Enter a valid APDU: CLA INS P1 P2, then optional data and Le.")
            }
            switch tag {
            case .miFare(let mifare):
                let (data, sw1, sw2) = try await DESFireCommands.apdu(mifare, apdu)
                return RawResponse(bytes: data, sw1: sw1, sw2: sw2, elapsedMS: 0)
            case .iso7816(let iso7816):
                let (data, sw1, sw2) = try await DESFireCommands.apdu(iso7816, apdu)
                return RawResponse(bytes: data, sw1: sw1, sw2: sw2, elapsedMS: 0)
            default:
                throw NFCEditorError.notSupportedOnChip("APDUs need an ISO 14443-4 tag such as DESFire.")
            }
        case .iso15693:
            guard case .iso15693(let iso15693) = tag else {
                throw NFCEditorError.notSupportedOnChip("ISO 15693 commands need a Type 5 tag.")
            }
            let bytes = command.bytes.bytes
            guard bytes.count >= 2 else {
                throw NFCEditorError.invalidInput("Enter the request flags byte and the command code.")
            }
            let flags = NFCISO15693RequestFlag(rawValue: bytes[0])
            let parameters = Data(bytes.dropFirst(2))
            let data = try await ISO15693Commands.custom(iso15693, flags: flags, code: Int(bytes[1]), parameters: parameters)
            return RawResponse(bytes: data, sw1: nil, sw2: nil, elapsedMS: 0)
        case .feliCa:
            guard case .feliCa(let feliCa) = tag else {
                throw NFCEditorError.notSupportedOnChip("FeliCa commands need a FeliCa tag.")
            }
            let data = try await FeliCaCommands.raw(feliCa, packet: command.bytes)
            return RawResponse(bytes: data, sw1: nil, sw2: nil, elapsedMS: 0)
        }
    }

    // MARK: Shared helpers

    /// Runs `body` and returns nil when it fails for a tag-level reason; session-level failures are rethrown.
    private static func attempt<T>(_ body: () async throws -> T) async throws -> T? {
        do {
            return try await body()
        } catch {
            let mapped = NFCEditorError.map(error)
            if isSessionError(mapped) { throw mapped }
            return nil
        }
    }

    /// `attempt` for Type 2 chips. A refused command drops NTAG and Ultralight into the idle state, so the tag is selected
    /// again before the caller sends anything else; a tag that cannot be selected again really is lost.
    private static func probe<T>(_ session: NFCTagReaderSession, _ tag: NFCMiFareTag, _ body: () async throws -> T) async throws -> T? {
        do {
            return try await body()
        } catch {
            let mapped = NFCEditorError.map(error)
            if isSessionError(mapped) && mapped != .tagLost { throw mapped }
            do {
                try await session.connect(to: .miFare(tag))
            } catch {
                throw mapped == .tagLost ? mapped : NFCEditorError.map(error)
            }
            return nil
        }
    }

    private static func reselect(_ session: NFCTagReaderSession, _ tag: NFCMiFareTag) async {
        try? await session.connect(to: .miFare(tag))
    }

    private static func writeFailure(_ error: NFCEditorError, page: Int, written: Int) -> NFCEditorError {
        if case .nak = error {
            return NFCEditorError.commandFailed("The tag refused page \(page). \(written) pages were written before that.")
        }
        return error
    }

    private static func field(_ label: String, _ value: String, _ systemImage: String) -> TagField {
        TagField(label: label, value: value, systemImage: systemImage)
    }

    private static func isNTAG21x(_ spec: ChipSpec) -> Bool {
        spec.family == .ntag21x || spec.family == .ntag21xF
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
