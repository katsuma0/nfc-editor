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
