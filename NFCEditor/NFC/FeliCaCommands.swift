import Foundation
import CoreNFC

enum FeliCaCommands {
    struct Info {
        var idm: Data
        var pmm: Data?
        var systemCode: Data
        var systemCodes: [Data]
    }

    private static let wildcardSystemCode = Data([0xFF, 0xFF])

    static func info(_ tag: NFCFeliCaTag) async throws -> Info {
        let idm = Data(tag.currentIDm)
        let current = Data(tag.currentSystemCode)
        let systemCode = current.count == 2 ? current : wildcardSystemCode

        var pmm: Data?
        // Core NFC refuses the wildcard system code in polling, so the PMm is only asked for when a real one is known.
        if systemCode != wildcardSystemCode {
            do {
                let (manufacturerParameter, _) = try await tag.polling(
                    systemCode: systemCode,
                    requestCode: NFCFeliCaPollingRequestCode.systemCode,
                    timeSlot: NFCFeliCaPollingTimeSlot.max1
                )
                if !manufacturerParameter.isEmpty {
                    pmm = Data(manufacturerParameter)
                }
            } catch {
                let mapped = NFCEditorError.map(error)
                if isSessionError(mapped) { throw mapped }
            }
        }

        var codes: [Data] = []
        do {
            codes = try await tag.requestSystemCode().map { Data($0) }
        } catch {
            let mapped = NFCEditorError.map(error)
            if isSessionError(mapped) { throw mapped }
        }
        if codes.isEmpty, systemCode != wildcardSystemCode {
            codes = [systemCode]
        }

        return Info(idm: idm, pmm: pmm, systemCode: systemCode, systemCodes: codes)
    }

    static func raw(_ tag: NFCFeliCaTag, packet: Data) async throws -> Data {
        guard !packet.isEmpty else {
            throw NFCEditorError.invalidInput("Enter a command.")
        }
        do {
            let response = try await tag.sendFeliCaCommand(commandPacket: packet)
            return Data(response)
        } catch {
            throw NFCEditorError.map(error)
        }
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

// MARK: Read, write and request service

extension FeliCaCommands {
    /// FeliCa Lite and Lite-S accept at most four blocks per read, which every other card also accepts.
    static let maxBlocksPerRead = 4
    /// Request Service takes up to 32 node codes in one command.
    static let maxNodesPerRequest = 32
    static let blockLength = 16
    static let absentKeyVersion: UInt16 = 0xFFFF

    /// Reads the given blocks of one service and returns one 16 byte block per requested block, in the same order.
    static func readWithoutEncryption(_ tag: NFCFeliCaTag, serviceCode: UInt16, blocks: [Int]) async throws -> [Data] {
        guard !blocks.isEmpty else {
            throw NFCEditorError.invalidInput("Enter at least one block number.")
        }
        for block in blocks {
            try checkBlockNumber(block)
        }
        let serviceList = [serviceCodeData(serviceCode)]
        var result: [Data] = []
        var start = 0
        while start < blocks.count {
            let end = min(start + maxBlocksPerRead, blocks.count)
            let chunk = Array(blocks[start..<end])
            let response: (Int, Int, [Data])
            do {
                response = try await tag.readWithoutEncryption(serviceCodeList: serviceList, blockList: chunk.map { blockListElement(block: $0) })
            } catch {
                throw NFCEditorError.map(error)
            }
            if let failure = statusError(response.0, response.1) {
                throw failure
            }
            guard response.2.count == chunk.count else {
                throw NFCEditorError.commandFailed("The card returned \(response.2.count) blocks instead of \(chunk.count).")
            }
            result.append(contentsOf: response.2.map { Data($0) })
            start = end
        }
        return result
    }

    /// Writes one 16 byte block of a service that allows writing without encryption.
    static func writeWithoutEncryption(_ tag: NFCFeliCaTag, serviceCode: UInt16, block: Int, data: Data) async throws {
        try checkBlockNumber(block)
        guard data.count == blockLength else {
            throw NFCEditorError.invalidInput("A FeliCa block is exactly 16 bytes.")
        }
        let response: (Int, Int)
        do {
            response = try await tag.writeWithoutEncryption(
                serviceCodeList: [serviceCodeData(serviceCode)],
                blockList: [blockListElement(block: block)],
                blockData: [data]
            )
        } catch {
            throw NFCEditorError.map(error)
        }
        if let failure = statusError(response.0, response.1) {
            throw failure
        }
    }

    /// Asks the card which services exist. Returns one key version per code, 0xFFFF when the service is absent.
    static func requestService(_ tag: NFCFeliCaTag, serviceCodes: [UInt16]) async throws -> [UInt16] {
        guard !serviceCodes.isEmpty else {
            throw NFCEditorError.invalidInput("Enter at least one service code.")
        }
        var versions: [UInt16] = []
        var start = 0
        while start < serviceCodes.count {
            let end = min(start + maxNodesPerRequest, serviceCodes.count)
            let chunk = Array(serviceCodes[start..<end])
            let response: [Data]
            do {
                response = try await tag.requestService(nodeCodeList: chunk.map { serviceCodeData($0) })
            } catch {
                throw NFCEditorError.map(error)
            }
            guard response.count == chunk.count else {
                throw NFCEditorError.commandFailed("The card answered for \(response.count) services instead of \(chunk.count).")
            }
            versions.append(contentsOf: response.map { keyVersion(Data($0)) })
            start = end
        }
        return versions
    }

    /// Service and node codes travel least significant byte first.
    static func serviceCodeData(_ code: UInt16) -> Data {
        Data([UInt8(code & 0xFF), UInt8(code >> 8)])
    }

    /// Two byte element for blocks below 256 (bit 7 set, service list index 0), three byte element above.
    static func blockListElement(block: Int) -> Data {
        if block <= 0xFF {
            return Data([0x80, UInt8(block)])
        }
        return Data([0x00, UInt8(block & 0xFF), UInt8((block >> 8) & 0xFF)])
    }

    /// Key versions come back least significant byte first; anything shorter than two bytes counts as absent.
    static func keyVersion(_ data: Data) -> UInt16 {
        let bytes = data.bytes
        guard bytes.count >= 2 else { return absentKeyVersion }
        return UInt16(bytes[0]) | (UInt16(bytes[1]) << 8)
    }

    /// Status flag 1 is zero when the card accepted the command; status flag 2 then says why it did not.
    static func statusError(_ status1: Int, _ status2: Int) -> NFCEditorError? {
        guard status1 != 0 else { return nil }
        let code1 = UInt8(truncatingIfNeeded: status1)
        let code2 = UInt8(truncatingIfNeeded: status2)
        var message = "Status 0x\(code1.hex) 0x\(code2.hex)"
        if let reason = statusReason(code2) {
            message += " (\(reason))"
        }
        return .commandFailed(message)
    }

    private static func statusReason(_ status2: UInt8) -> String? {
        switch status2 {
        case 0x01: return "purse balance too low"
        case 0x02: return "cashback limit reached"
        case 0x70: return "memory error"
        case 0x71: return "memory warning"
        case 0xA1: return "too many services"
        case 0xA2: return "too many blocks"
        case 0xA3: return "bad block list"
        case 0xA4: return "service type not allowed"
        case 0xA5: return "access not allowed"
        case 0xA6: return "service code not allowed"
        case 0xA7: return "access mode not allowed"
        case 0xA8: return "block number out of range"
        case 0xA9: return "write failed"
        case 0xAA: return "key change failed"
        case 0xAB: return "card busy"
        case 0xAC: return "service does not exist"
        case 0xB0: return "authentication required"
        case 0xB1: return "authentication failed"
        case 0xB2: return "unknown command"
        case 0xC0: return "card locked"
        default: return nil
        }
    }

    private static func checkBlockNumber(_ block: Int) throws {
        guard (0...0xFFFF).contains(block) else {
            throw NFCEditorError.invalidInput("Block \(block) is out of range (0 to 65535).")
        }
    }
}
