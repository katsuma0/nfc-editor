import Foundation
import CoreNFC

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
        guard from >= 0, to <= 255, from <= to else {
            throw NFCEditorError.invalidInput("The block range must be within 0 to 255.")
        }

        var pages: [MemoryPage] = []
        var current = from
        var multipleWorks = true

        while current <= to {
            if multipleWorks {
                let chunkEnd = min(current + multipleBlockChunk - 1, to)
                let count = chunkEnd - current + 1
                do {
                    let blocks = try await tag.readMultipleBlocks(requestFlags: defaultFlags, blockRange: NSRange(location: current, length: count))
                    if blocks.count == count {
                        for (offset, block) in blocks.enumerated() {
                            pages.append(MemoryPage(index: current + offset, bytes: Data(block), readable: true))
                        }
                        current = chunkEnd + 1
                        progress?(pages.count)
                        continue
                    }
                    multipleWorks = false
                } catch {
                    let mapped = NFCEditorError.map(error)
                    if mapped == .cancelled || mapped == .timeout { throw mapped }
                    // Fall back to single block reads; a tag that ignores the multiple block command looks lost to Core NFC.
                    multipleWorks = false
                }
            }

            do {
                let block = try await tag.readSingleBlock(requestFlags: defaultFlags, blockNumber: UInt8(current))
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
        let block = try blockByte(index)
        guard !bytes.isEmpty, bytes.count <= 32 else {
            throw NFCEditorError.invalidInput("Enter between 1 and 32 bytes for the block.")
        }
        do {
            try await tag.writeSingleBlock(requestFlags: defaultFlags, blockNumber: block, dataBlock: bytes)
        } catch {
            let mapped = NFCEditorError.map(error)
            if mapped == .cancelled || mapped == .timeout { throw mapped }
            // Tags from ST and TI only answer a write when the option flag is set.
            do {
                try await tag.writeSingleBlock(requestFlags: defaultFlags.union(.option), blockNumber: block, dataBlock: bytes)
            } catch {
                throw NFCEditorError.map(error)
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
        let block = try blockByte(index)
        do {
            try await tag.lockBlock(requestFlags: defaultFlags, blockNumber: block)
        } catch {
            let mapped = NFCEditorError.map(error)
            if mapped == .cancelled || mapped == .timeout { throw mapped }
            do {
                try await tag.lockBlock(requestFlags: defaultFlags.union(.option), blockNumber: block)
            } catch {
                throw NFCEditorError.map(error)
            }
        }
    }

    private static func blockByte(_ index: Int) throws -> UInt8 {
        guard (0...255).contains(index) else {
            throw NFCEditorError.invalidInput("Block \(index) is out of range (0 to 255).")
        }
        return UInt8(index)
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
