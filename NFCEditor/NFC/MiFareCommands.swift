import Foundation
import CoreNFC

/// Low-level NTAG / Ultralight helpers. All throw NFCEditorError.
enum MiFareCommands {
    private static let ackByte: UInt8 = 0x0A
    private static let nakCodes: Set<UInt8> = [0x00, 0x01, 0x04, 0x05, 0x07]
    private static let fastReadChunk = 32

    static func getVersion(_ tag: NFCMiFareTag) async throws -> Data {
        let response = try await transceive(tag, Data([0x60]), expectAck: false)
        guard response.count >= 8 else {
            throw NFCEditorError.commandFailed("GET_VERSION returned \(response.count) bytes instead of 8.")
        }
        return Data(response.prefix(8))
    }

    static func read(_ tag: NFCMiFareTag, page: Int) async throws -> Data {
        let index = try pageByte(page)
        let response = try await transceive(tag, Data([0x30, index]), expectAck: false)
        guard response.count >= 4 else {
            throw NFCEditorError.commandFailed("READ returned a short response for page \(page).")
        }
        return Data(response)
    }

    static func fastRead(_ tag: NFCMiFareTag, from: Int, to: Int) async throws -> Data {
        let start = try pageByte(from)
        let end = try pageByte(to)
        guard from <= to else {
            throw NFCEditorError.invalidInput("The start page must not be after the end page.")
        }
        let response = try await transceive(tag, Data([0x3A, start, end]), expectAck: false)
        return Data(response)
    }

    static func write(_ tag: NFCMiFareTag, page: Int, bytes: Data) async throws {
        let index = try pageByte(page)
        guard bytes.count == 4 else {
            throw NFCEditorError.invalidInput("A page holds exactly 4 bytes.")
        }
        var packet = Data([0xA2, index])
        packet.append(bytes)
        _ = try await transceive(tag, packet, expectAck: true)
    }

    static func pwdAuth(_ tag: NFCMiFareTag, password: Data) async throws -> Data {
        guard password.count == 4 else {
            throw NFCEditorError.invalidInput("The password must be 4 bytes.")
        }
        var packet = Data([0x1B])
        packet.append(password)
        do {
            let response = try await transceive(tag, packet, expectAck: false)
            guard response.count >= 2 else { throw NFCEditorError.authenticationFailed }
            return Data(response.prefix(2))
        } catch let error as NFCEditorError {
            if case .nak = error { throw NFCEditorError.authenticationFailed }
            throw error
        }
    }

    static func readSignature(_ tag: NFCMiFareTag) async throws -> Data {
        let response = try await transceive(tag, Data([0x3C, 0x00]), expectAck: false)
        guard response.count >= 32 else {
            throw NFCEditorError.commandFailed("READ_SIG returned \(response.count) bytes instead of 32.")
        }
        return Data(response.prefix(32))
    }

    static func readCounter(_ tag: NFCMiFareTag, address: UInt8) async throws -> UInt32 {
        guard address <= 2 else {
            throw NFCEditorError.invalidInput("The counter address must be 0, 1 or 2.")
        }
        let response = try await transceive(tag, Data([0x39, address]), expectAck: false)
        let bytes = response.bytes
        guard bytes.count >= 3 else {
            throw NFCEditorError.commandFailed("READ_CNT returned a short response.")
        }
        return UInt32(bytes[0]) | (UInt32(bytes[1]) << 8) | (UInt32(bytes[2]) << 16)
    }

    /// Reads pages [from, to] inclusive, using FAST_READ in chunks of up to 32 pages and falling back to READ per 4 pages;
    /// pages that cannot be read are returned with readable = false. Calls `progress` with pages done.
    static func readPages(_ tag: NFCMiFareTag, from: Int, to: Int, pageSize: Int, progress: ((Int) -> Void)?) async throws -> [MemoryPage] {
        guard from >= 0, to <= 255, from <= to else {
            throw NFCEditorError.invalidInput("The page range must be within 0 to 255.")
        }
        guard pageSize > 0 else {
            throw NFCEditorError.invalidInput("The page size must be at least 1 byte.")
        }

        var pages: [MemoryPage] = []
        var current = from
        var fastReadWorks = true
        var sawNAK = false

        while current <= to {
            if fastReadWorks {
                let chunkEnd = min(current + fastReadChunk - 1, to)
                let expected = (chunkEnd - current + 1) * pageSize
                do {
                    let data = try await fastRead(tag, from: current, to: chunkEnd)
                    if data.count >= expected {
                        let bytes = data.bytes
                        for index in current...chunkEnd {
                            let offset = (index - current) * pageSize
                            pages.append(MemoryPage(index: index, bytes: Data(bytes[offset..<offset + pageSize]), readable: true))
                        }
                        current = chunkEnd + 1
                        progress?(pages.count)
                        continue
                    }
                    fastReadWorks = false
                } catch let error as NFCEditorError {
                    if isSessionError(error) && !sawNAK { throw error }
                    sawNAK = true
                    fastReadWorks = false
                }
            }

            let readEnd = min(current + 3, to)
            do {
                let data = try await read(tag, page: current)
                let bytes = data.bytes
                for index in current...readEnd {
                    let offset = (index - current) * pageSize
                    if bytes.count >= offset + pageSize {
                        pages.append(MemoryPage(index: index, bytes: Data(bytes[offset..<offset + pageSize]), readable: true))
                    } else {
                        pages.append(MemoryPage(index: index, bytes: Data(), readable: false))
                    }
                }
                current = readEnd + 1
                progress?(pages.count)
            } catch let error as NFCEditorError {
                // A NAK puts some chips into an idle state, so a later "tag lost" is a consequence of the refusal, not a real loss.
                if isSessionError(error) && !sawNAK { throw error }
                for index in current...to {
                    pages.append(MemoryPage(index: index, bytes: Data(), readable: false))
                }
                progress?(pages.count)
                return pages
            }
        }
        return pages
    }

    /// Throws .nak(code) when a 1-byte response is not the ACK (0x0A). Longer or empty responses pass. Used internally after transceive.
    static func checkAck(_ response: Data) throws {
        guard response.count == 1, let byte = response.first else { return }
        if byte == ackByte { return }
        throw NFCEditorError.nak(byte)
    }

    /// Sends any raw command; maps errors; a 1-byte NAK (0x00, 0x01, 0x04, 0x05, 0x07) is thrown as .nak(code).
    static func transceive(_ tag: NFCMiFareTag, _ command: Data, expectAck: Bool) async throws -> Data {
        guard !command.isEmpty else {
            throw NFCEditorError.invalidInput("Enter a command.")
        }
        let response: Data
        do {
            response = try await tag.sendMiFareCommand(commandPacket: command)
        } catch {
            throw NFCEditorError.map(error)
        }
        if expectAck {
            try checkAck(response)
            return Data(response)
        }
        if response.count == 1, let byte = response.first, nakCodes.contains(byte) {
            throw NFCEditorError.nak(byte)
        }
        return Data(response)
    }

    private static func pageByte(_ page: Int) throws -> UInt8 {
        guard (0...255).contains(page) else {
            throw NFCEditorError.invalidInput("Page \(page) is out of range (0 to 255).")
        }
        return UInt8(page)
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
