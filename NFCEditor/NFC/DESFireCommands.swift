import Foundation
import CoreNFC

enum DESFireCommands {
    struct Version {
        var hardware: Data
        var software: Data
        var production: Data
        var raw: Data
    }

    private static let nativeClass: UInt8 = 0x90
    private static let nativeStatusClass: UInt8 = 0x91
    private static let additionalFrame: UInt8 = 0xAF
    private static let operationOK: UInt8 = 0x00
    private static let ndefApplicationID = Data([0xD2, 0x76, 0x00, 0x00, 0x85, 0x01, 0x01])
    private static let capabilityContainerFileID = Data([0xE1, 0x03])
    private static let maxReadChunk = 240

    /// Native-wrapped GetVersion (90 60 00 00 00) with the two AF continuations. Works on NFCMiFareTag (family .desfire) via sendMiFareISO7816Command.
    static func getVersion(_ tag: NFCMiFareTag) async throws -> Version {
        let first = nativeAPDU(instruction: 0x60)
        let (hardware, sw1a, sw2a) = try await apdu(tag, first)
        guard sw1a == nativeStatusClass, sw2a == additionalFrame else {
            throw NFCEditorError.commandFailed("GetVersion was refused (status \(sw1a.hex) \(sw2a.hex)).")
        }

        let next = nativeAPDU(instruction: additionalFrame)
        let (software, sw1b, sw2b) = try await apdu(tag, next)
        guard sw1b == nativeStatusClass, sw2b == additionalFrame else {
            throw NFCEditorError.commandFailed("GetVersion stopped after the first frame (status \(sw1b.hex) \(sw2b.hex)).")
        }

        let (production, sw1c, sw2c) = try await apdu(tag, next)
        guard sw1c == nativeStatusClass, sw2c == operationOK else {
            throw NFCEditorError.commandFailed("GetVersion stopped after the second frame (status \(sw1c.hex) \(sw2c.hex)).")
        }

        var raw = Data()
        raw.append(hardware)
        raw.append(software)
        raw.append(production)
        return Version(hardware: Data(hardware), software: Data(software), production: Data(production), raw: raw)
    }

    /// Sends an APDU to NFCMiFareTag (desfire family) and returns (data, sw1, sw2).
    static func apdu(_ tag: NFCMiFareTag, _ apdu: NFCISO7816APDU) async throws -> (Data, UInt8, UInt8) {
        do {
            let (data, sw1, sw2) = try await tag.sendMiFareISO7816Command(apdu)
            return (Data(data), sw1, sw2)
        } catch {
            throw NFCEditorError.map(error)
        }
    }

    static func apdu(_ tag: NFCISO7816Tag, _ apdu: NFCISO7816APDU) async throws -> (Data, UInt8, UInt8) {
        do {
            let (data, sw1, sw2) = try await tag.sendCommand(apdu: apdu)
            return (Data(data), sw1, sw2)
        } catch {
            throw NFCEditorError.map(error)
        }
    }

    /// Reads the Type 4 NDEF file via ISO select/read binary (AID D2760000850101, CC file E103, NDEF file from CC). Returns raw NDEF file bytes (length-prefixed) or nil if no NDEF app.
    static func readNDEFFile(send: @escaping (NFCISO7816APDU) async throws -> (Data, UInt8, UInt8)) async throws -> Data? {
        guard try await selectApplication(send) else { return nil }

        try await selectFile(send, fileID: capabilityContainerFileID, name: "capability container")
        let cc = try await readBinary(send, offset: 0, length: 15).bytes
        guard cc.count >= 15 else {
            throw NFCEditorError.commandFailed("The capability container is only \(cc.count) bytes long.")
        }
        guard cc[7] == 0x04 else {
            throw NFCEditorError.commandFailed("The capability container has no NDEF file entry.")
        }

        let maxReadLength = Int(cc[3]) << 8 | Int(cc[4])
        let chunk = min(max(maxReadLength, 16), maxReadChunk)
        let ndefFileID = Data([cc[9], cc[10]])

        try await selectFile(send, fileID: ndefFileID, name: "NDEF file")
        let lengthBytes = try await readBinary(send, offset: 0, length: 2).bytes
        guard lengthBytes.count >= 2 else {
            throw NFCEditorError.commandFailed("The NDEF file length could not be read.")
        }
        let messageLength = Int(lengthBytes[0]) << 8 | Int(lengthBytes[1])

        var out = Data(lengthBytes[0..<2])
        var offset = 2
        let end = messageLength + 2
        while offset < end {
            let wanted = min(chunk, end - offset)
            let part = try await readBinary(send, offset: offset, length: wanted)
            guard !part.isEmpty else {
                throw NFCEditorError.commandFailed("Reading the NDEF file stopped at byte \(offset).")
            }
            out.append(part)
            offset += part.count
        }
        return out
    }

    /// Native wrapped command: CLA 90, INS, P1 P2 00, no data, Le 00.
    private static func nativeAPDU(instruction: UInt8) -> NFCISO7816APDU {
        NFCISO7816APDU(
            instructionClass: nativeClass,
            instructionCode: instruction,
            p1Parameter: 0x00,
            p2Parameter: 0x00,
            data: Data(),
            expectedResponseLength: 256
        )
    }

    /// Returns false when the tag answers that no NDEF application exists.
    private static func selectApplication(_ send: (NFCISO7816APDU) async throws -> (Data, UInt8, UInt8)) async throws -> Bool {
        let withLe = NFCISO7816APDU(instructionClass: 0x00, instructionCode: 0xA4, p1Parameter: 0x04, p2Parameter: 0x00, data: ndefApplicationID, expectedResponseLength: 256)
        let (_, sw1, sw2) = try await send(withLe)
        if sw1 == 0x90, sw2 == 0x00 { return true }
        if sw1 == 0x67 || sw1 == 0x6C {
            // Some cards reject the trailing Le byte; retry without it.
            let withoutLe = NFCISO7816APDU(instructionClass: 0x00, instructionCode: 0xA4, p1Parameter: 0x04, p2Parameter: 0x00, data: ndefApplicationID, expectedResponseLength: -1)
            let (_, retrySW1, retrySW2) = try await send(withoutLe)
            return retrySW1 == 0x90 && retrySW2 == 0x00
        }
        return false
    }

    private static func selectFile(_ send: (NFCISO7816APDU) async throws -> (Data, UInt8, UInt8), fileID: Data, name: String) async throws {
        let apdu = NFCISO7816APDU(instructionClass: 0x00, instructionCode: 0xA4, p1Parameter: 0x00, p2Parameter: 0x0C, data: fileID, expectedResponseLength: -1)
        let (_, sw1, sw2) = try await send(apdu)
        guard sw1 == 0x90, sw2 == 0x00 else {
            throw NFCEditorError.commandFailed("The \(name) could not be selected (status \(sw1.hex) \(sw2.hex)).")
        }
    }

    private static func readBinary(_ send: (NFCISO7816APDU) async throws -> (Data, UInt8, UInt8), offset: Int, length: Int) async throws -> Data {
        guard offset >= 0, offset <= 0x7FFF else {
            throw NFCEditorError.invalidInput("The read offset is out of range.")
        }
        guard length >= 1, length <= 256 else {
            throw NFCEditorError.invalidInput("The read length must be between 1 and 256 bytes.")
        }
        let apdu = NFCISO7816APDU(
            instructionClass: 0x00,
            instructionCode: 0xB0,
            p1Parameter: UInt8((offset >> 8) & 0x7F),
            p2Parameter: UInt8(offset & 0xFF),
            data: Data(),
            expectedResponseLength: length
        )
        let (data, sw1, sw2) = try await send(apdu)
        guard sw1 == 0x90, sw2 == 0x00 else {
            throw NFCEditorError.commandFailed("Read binary failed at offset \(offset) (status \(sw1.hex) \(sw2.hex)).")
        }
        return Data(data)
    }
}

/// A read only snapshot of a DESFire card: version, applications, free memory, and the
/// master key settings. Built by TagOperations.desfireOverview for the DESFire tool.
struct DESFireOverview: Hashable {
    var version: Data?
    var applications: [Data]
    var freeMemory: Int?
    var keySettings: UInt8?
    var maxKeys: UInt8?
    var hasNDEFApplication: Bool
}

extension DESFireCommands {
    /// Sends one native DESFire command wrapped in an ISO 7816 APDU and gathers every
    /// additional frame the card returns. Throws on any status other than success, so
    /// callers that need to inspect a non success status use the private nativeRaw helper.
    static func native(_ tag: NFCMiFareTag, command: UInt8, data: Data) async throws -> (status: UInt8, data: Data) {
        let result = try await nativeRaw(tag, command: command, data: data)
        guard result.status == operationOK else {
            throw NFCEditorError.commandFailed(statusName(result.status))
        }
        return result
    }

    /// Human readable name for a DESFire native status byte.
    static func statusName(_ status: UInt8) -> String {
        switch status {
        case 0x00: return "OK"
        case 0x0C: return "No changes"
        case 0x0E: return "Out of EEPROM"
        case 0x1C: return "Illegal command"
        case 0x1E: return "Integrity error"
        case 0x40: return "No such key"
        case 0x7E: return "Length error"
        case 0x9D: return "Permission denied"
        case 0x9E: return "Parameter error"
        case 0xA0: return "Application not found"
        case 0xA1: return "Application integrity error"
        case 0xAE: return "Authentication error"
        case 0xAF: return "Additional frame"
        case 0xBE: return "Boundary error"
        case 0xC1: return "PICC integrity error"
        case 0xCA: return "Command aborted"
        case 0xCD: return "PICC disabled"
        case 0xCE: return "Count error"
        case 0xDE: return "Duplicate"
        case 0xEE: return "EEPROM error"
        case 0xF0: return "File not found"
        case 0xF1: return "File integrity error"
        default: return "Status 0x\(status.hex)"
        }
    }

    static func selectApplication(_ tag: NFCMiFareTag, aid: Data) async throws {
        guard aid.count == 3 else {
            throw NFCEditorError.invalidInput("A DESFire application ID is 3 bytes.")
        }
        _ = try await native(tag, command: 0x5A, data: aid)
    }

    static func getApplicationIDs(_ tag: NFCMiFareTag) async throws -> [Data] {
        let (_, data) = try await native(tag, command: 0x6A, data: Data())
        let bytes = [UInt8](data)
        var aids: [Data] = []
        var index = 0
        while index + 3 <= bytes.count {
            aids.append(Data(bytes[index..<index + 3]))
            index += 3
        }
        return aids
    }

    static func getFreeMemory(_ tag: NFCMiFareTag) async throws -> Int? {
        let result = try await nativeRaw(tag, command: 0x6E, data: Data())
        // DESFire D40 has no GetFreeMemory command and answers illegal command.
        if result.status == 0x1C { return nil }
        guard result.status == operationOK else {
            throw NFCEditorError.commandFailed(statusName(result.status))
        }
        guard result.data.count >= 3 else { return nil }
        let bytes = [UInt8](result.data)
        return Int(bytes[0]) | Int(bytes[1]) << 8 | Int(bytes[2]) << 16
    }

    static func getFileIDs(_ tag: NFCMiFareTag) async throws -> [UInt8] {
        let (_, data) = try await native(tag, command: 0x6F, data: Data())
        return [UInt8](data)
    }

    static func getKeySettings(_ tag: NFCMiFareTag) async throws -> (settings: UInt8, maxKeys: UInt8) {
        let (_, data) = try await native(tag, command: 0x45, data: Data())
        guard data.count >= 2 else {
            throw NFCEditorError.commandFailed("The key settings answer was too short.")
        }
        let bytes = [UInt8](data)
        // The low nibble of the second byte is the number of keys the application holds.
        return (bytes[0], bytes[1] & 0x0F)
    }

    /// DESFire legacy (D40) authentication. Returns the derived session key on success.
    static func authenticateLegacy(_ tag: NFCMiFareTag, keyNumber: UInt8, key: Data) async throws -> Data {
        guard key.count == 8 || key.count == 16 else {
            throw NFCEditorError.invalidInput("A DESFire DES key must be 8 or 16 bytes.")
        }
        let step1 = try await sendFrame(tag, command: 0x0A, data: Data([keyNumber]))
        guard step1.status == additionalFrame, step1.data.count == 8 else {
            let reason = step1.status == operationOK ? "The card did not start authentication." : statusName(step1.status)
            throw NFCEditorError.commandFailed(reason)
        }
        let rndA = randomBlock()
        guard let exchange = computeLegacyAuth(key: key, piccStep1: Data([additionalFrame]) + step1.data, rndA: rndA) else {
            throw NFCEditorError.failed("The authentication values could not be prepared.")
        }
        let token = Data(exchange.pcdStep2.suffix(16))
        let step2 = try await sendFrame(tag, command: additionalFrame, data: token)
        guard step2.status == operationOK, step2.data.count == 8 else {
            let reason = step2.status == additionalFrame ? "The card asked for another frame." : statusName(step2.status)
            throw NFCEditorError.commandFailed(reason)
        }
        guard Data([operationOK]) + step2.data == exchange.expectedPiccStep3 else {
            throw NFCEditorError.authenticationFailed
        }
        return exchange.sessionKey
    }

    static func formatPICC(_ tag: NFCMiFareTag) async throws {
        _ = try await native(tag, command: 0xFC, data: Data())
    }

    static func createApplication(_ tag: NFCMiFareTag, aid: Data, keySettings1: UInt8, keySettings2: UInt8, isoFileID: UInt16?, dfName: Data?) async throws {
        guard aid.count == 3 else {
            throw NFCEditorError.invalidInput("A DESFire application ID is 3 bytes.")
        }
        var payload = Data(aid)
        payload.append(keySettings1)
        payload.append(keySettings2)
        if let isoFileID = isoFileID {
            payload.append(UInt8(isoFileID & 0xFF))
            payload.append(UInt8((isoFileID >> 8) & 0xFF))
        }
        if let dfName = dfName {
            payload.append(dfName)
        }
        _ = try await native(tag, command: 0xCA, data: payload)
    }

    static func createStandardDataFile(_ tag: NFCMiFareTag, fileNumber: UInt8, isoFileID: UInt16?, communication: UInt8, accessRights: UInt16, size: Int) async throws {
        guard size >= 0, size <= 0xFFFFFF else {
            throw NFCEditorError.invalidInput("The file size is out of range.")
        }
        var payload = Data([fileNumber])
        if let isoFileID = isoFileID {
            payload.append(UInt8(isoFileID & 0xFF))
            payload.append(UInt8((isoFileID >> 8) & 0xFF))
        }
        payload.append(communication)
        payload.append(UInt8(accessRights & 0xFF))
        payload.append(UInt8((accessRights >> 8) & 0xFF))
        payload.append(UInt8(size & 0xFF))
        payload.append(UInt8((size >> 8) & 0xFF))
        payload.append(UInt8((size >> 16) & 0xFF))
        _ = try await native(tag, command: 0xCD, data: payload)
    }

    static func writeData(_ tag: NFCMiFareTag, fileNumber: UInt8, offset: Int, data: Data) async throws {
        guard offset >= 0, offset <= 0xFFFFFF else {
            throw NFCEditorError.invalidInput("The write offset is out of range.")
        }
        let length = data.count
        guard length <= 0xFFFFFF else {
            throw NFCEditorError.invalidInput("That is too much data for one write.")
        }
        let chunkSize = 52
        var header = Data([fileNumber])
        header.append(UInt8(offset & 0xFF))
        header.append(UInt8((offset >> 8) & 0xFF))
        header.append(UInt8((offset >> 16) & 0xFF))
        header.append(UInt8(length & 0xFF))
        header.append(UInt8((length >> 8) & 0xFF))
        header.append(UInt8((length >> 16) & 0xFF))

        let bytes = [UInt8](data)
        let firstChunk = min(chunkSize, bytes.count)
        var payload = header
        payload.append(contentsOf: bytes[0..<firstChunk])
        var sent = firstChunk
        var frame = try await sendFrame(tag, command: 0x3D, data: payload)
        while sent < bytes.count {
            guard frame.status == additionalFrame else {
                throw NFCEditorError.commandFailed(statusName(frame.status))
            }
            let next = min(chunkSize, bytes.count - sent)
            let chunk = Data(bytes[sent..<sent + next])
            sent += next
            frame = try await sendFrame(tag, command: additionalFrame, data: chunk)
        }
        guard frame.status == operationOK else {
            throw NFCEditorError.commandFailed(statusName(frame.status))
        }
    }

    /// Lays down the NXP AN11004 Type 4 NDEF application: an application with an ISO file
    /// identifier, a capability container file, and an empty NDEF file. The master key must
    /// be the factory default or the key already on the card.
    static func createNDEFApplication(_ session: NFCTagReaderSession, _ tag: NFCMiFareTag, masterKey: Data, formatFirst: Bool, ndefFileSize: Int) async throws {
        guard ndefFileSize >= 0, ndefFileSize <= 0xFFFF else {
            throw NFCEditorError.invalidInput("The NDEF file size must fit in two bytes.")
        }
        session.alertMessage = "Selecting the card."
        try await selectApplication(tag, aid: Data([0x00, 0x00, 0x00]))
        session.alertMessage = "Authenticating with the master key."
        _ = try await authenticateLegacy(tag, keyNumber: 0, key: masterKey)
        if formatFirst {
            session.alertMessage = "Formatting the card."
            try await formatPICC(tag)
        }
        session.alertMessage = "Creating the NDEF application."
        try await createApplication(tag, aid: Data([0x01, 0x00, 0x00]), keySettings1: 0x0F, keySettings2: 0x21, isoFileID: 0xE110, dfName: Data([0xD2, 0x76, 0x00, 0x00, 0x85, 0x01, 0x01]))
        try await selectApplication(tag, aid: Data([0x01, 0x00, 0x00]))
        session.alertMessage = "Authenticating with the application."
        _ = try await authenticateLegacy(tag, keyNumber: 0, key: masterKey)
        session.alertMessage = "Writing the capability container."
        try await createStandardDataFile(tag, fileNumber: 1, isoFileID: 0xE103, communication: 0x00, accessRights: 0xEEEE, size: 15)
        var cc = Data([0x00, 0x0F, 0x20, 0x00, 0x3B, 0x00, 0x34, 0x04, 0x06, 0xE1, 0x04])
        cc.append(UInt8((ndefFileSize >> 8) & 0xFF))
        cc.append(UInt8(ndefFileSize & 0xFF))
        cc.append(0x00)
        cc.append(0x00)
        try await writeData(tag, fileNumber: 1, offset: 0, data: cc)
        session.alertMessage = "Creating the NDEF file."
        try await createStandardDataFile(tag, fileNumber: 2, isoFileID: 0xE104, communication: 0x00, accessRights: 0xEEEE, size: ndefFileSize)
        try await writeData(tag, fileNumber: 2, offset: 0, data: Data([0x00, 0x00]))
        session.alertMessage = "The NDEF application is ready."
    }

    /// Pure DESFire legacy authentication arithmetic, kept separate so it can be tested
    /// against the libfreefare vectors without a card. piccStep1 and the returned frames
    /// all carry the leading status byte (AF for the continuations, 00 for the final one).
    static func computeLegacyAuth(key: Data, piccStep1: Data, rndA: Data) -> (pcdStep2: Data, expectedPiccStep3: Data, sessionKey: Data)? {
        guard key.count == 8 || key.count == 16 else { return nil }
        guard rndA.count == 8 else { return nil }
        guard piccStep1.count == 9, piccStep1.first == additionalFrame else { return nil }

        let ekRndB = Data(piccStep1.suffix(8))
        let rndB = legacyDecrypt(ekRndB, key: key)
        var iv = ekRndB

        let token = rndA + DES.rotateLeft(rndB)
        let c1 = legacyDecrypt(DES.xor(Data(token.prefix(8)), iv), key: key)
        let c2 = legacyDecrypt(DES.xor(Data(token.suffix(8)), c1), key: key)
        iv = c2
        let pcdStep2 = Data([additionalFrame]) + c1 + c2

        let expectedCipher = legacyEncrypt(DES.xor(DES.rotateLeft(rndA), iv), key: key)
        let expectedPiccStep3 = Data([operationOK]) + expectedCipher

        return (pcdStep2, expectedPiccStep3, legacySessionKey(rndA: rndA, rndB: rndB, key: key))
    }

    /// CRC_A as used by ISO 14443-A, seed 0x6363, returned low byte first.
    static func crc16(_ data: Data) -> Data {
        var crc: UInt32 = 0x6363
        for byte in data {
            var b = UInt32(byte ^ UInt8(crc & 0xFF))
            b = (b ^ (b << 4)) & 0xFF
            crc = ((crc >> 8) ^ (b << 8) ^ (b << 3) ^ (b >> 4)) & 0xFFFF
        }
        return Data([UInt8(crc & 0xFF), UInt8((crc >> 8) & 0xFF)])
    }

    // MARK: Private helpers

    /// One native command exchange plus its additional frames. Unlike native, this returns
    /// the final status instead of throwing, so getFreeMemory can read the D40 refusal.
    private static func nativeRaw(_ tag: NFCMiFareTag, command: UInt8, data: Data) async throws -> (status: UInt8, data: Data) {
        var frame = try await sendFrame(tag, command: command, data: data)
        var accumulated = frame.data
        while frame.status == additionalFrame {
            frame = try await sendFrame(tag, command: additionalFrame, data: Data())
            accumulated.append(frame.data)
        }
        return (frame.status, accumulated)
    }

    /// Sends a single wrapped frame. The DESFire status rides in SW2 under the 0x91 class.
    private static func sendFrame(_ tag: NFCMiFareTag, command: UInt8, data: Data) async throws -> (status: UInt8, data: Data) {
        let frame = NFCISO7816APDU(
            instructionClass: nativeClass,
            instructionCode: command,
            p1Parameter: 0x00,
            p2Parameter: 0x00,
            data: data,
            expectedResponseLength: 256
        )
        let (response, _, sw2) = try await apdu(tag, frame)
        return (sw2, response)
    }

    private static func legacyDecrypt(_ block: Data, key: Data) -> Data {
        key.count == 8 ? DES.decryptBlock(block, key: key) : DES.tdeaDecryptBlock(block, key: key)
    }

    private static func legacyEncrypt(_ block: Data, key: Data) -> Data {
        key.count == 8 ? DES.encryptBlock(block, key: key) : DES.tdeaEncryptBlock(block, key: key)
    }

    private static func legacySessionKey(rndA: Data, rndB: Data, key: Data) -> Data {
        let a = [UInt8](rndA)
        let b = [UInt8](rndB)
        var session = Data()
        session.append(contentsOf: a[0..<4])
        session.append(contentsOf: b[0..<4])
        let halvesEqual = key.count == 16 && Data(key.prefix(8)) == Data(key.suffix(8))
        if key.count == 8 || halvesEqual {
            session.append(contentsOf: a[0..<4])
            session.append(contentsOf: b[0..<4])
        } else {
            session.append(contentsOf: a[4..<8])
            session.append(contentsOf: b[4..<8])
        }
        return session
    }

    private static func randomBlock() -> Data {
        var bytes = [UInt8]()
        bytes.reserveCapacity(8)
        for _ in 0..<8 { bytes.append(UInt8.random(in: 0...255)) }
        return Data(bytes)
    }
}
