import Foundation
import CoreNFC

/// MIFARE Ultralight C 3DES authentication and key management.
/// Ultralight C uses a 16-byte 2-key Triple DES key; all crypto runs through DES.
enum UltralightC {
    static let defaultKey = Data("BREAKMEIFYOUCAN!".utf8)

    /// Runs the two-pass 3DES handshake. Proves the key or throws .authenticationFailed.
    static func authenticate(_ tag: NFCMiFareTag, key: Data) async throws {
        let step1: Data
        do {
            step1 = try await MiFareCommands.transceive(tag, Data([0x1A, 0x00]), expectAck: false)
        } catch let error as NFCEditorError {
            if case .nak = error { throw NFCEditorError.authenticationFailed }
            throw error
        }
        guard step1.count == 9, step1.first == 0xAF else {
            throw NFCEditorError.authenticationFailed
        }
        let rndA = Data((0..<8).map { _ in UInt8.random(in: 0...UInt8.max) })
        guard let exchange = computeExchange(key: key, piccStep1: step1, rndA: rndA) else {
            throw NFCEditorError.authenticationFailed
        }
        let step3: Data
        do {
            step3 = try await MiFareCommands.transceive(tag, exchange.pcdStep2, expectAck: false)
        } catch let error as NFCEditorError {
            if case .nak = error { throw NFCEditorError.authenticationFailed }
            throw error
        }
        guard step3 == exchange.expectedPiccStep3 else {
            throw NFCEditorError.authenticationFailed
        }
    }

    /// Writes the 16-byte key across pages 2C..2F.
    static func writeKey(_ tag: NFCMiFareTag, key: Data) async throws {
        guard key.count == 16 else {
            throw NFCEditorError.invalidInput("An Ultralight C key is 16 bytes.")
        }
        let pages = keyPages(key)
        try await MiFareCommands.write(tag, page: 0x2C, bytes: pages[0])
        try await MiFareCommands.write(tag, page: 0x2D, bytes: pages[1])
        try await MiFareCommands.write(tag, page: 0x2E, bytes: pages[2])
        try await MiFareCommands.write(tag, page: 0x2F, bytes: pages[3])
    }

    /// Page 2A byte 0 is AUTH0 (first protected page, 3..0x30); page 2B bit 0 is AUTH1 (1 = write access only).
    static func setProtection(_ tag: NFCMiFareTag, firstPage: Int, writeOnly: Bool) async throws {
        let auth0 = UInt8(max(3, min(0x30, firstPage)))
        try await MiFareCommands.write(tag, page: 0x2A, bytes: Data([auth0, 0x00, 0x00, 0x00]))
        let auth1: UInt8 = writeOnly ? 0x01 : 0x00
        try await MiFareCommands.write(tag, page: 0x2B, bytes: Data([auth1, 0x00, 0x00, 0x00]))
    }

    /// AUTH0 at 0x30 sits past the last page, so nothing is protected any more.
    static func removeProtection(_ tag: NFCMiFareTag) async throws {
        try await MiFareCommands.write(tag, page: 0x2A, bytes: Data([0x30, 0x00, 0x00, 0x00]))
    }

    /// The 16-byte key stored as four pages. Each 8-byte half is laid out most significant byte first per page.
    static func keyPages(_ key: Data) -> [Data] {
        let k = key.bytes
        guard k.count == 16 else { return [] }
        let k1 = Array(k[0..<8])
        let k2 = Array(k[8..<16])
        return [
            Data([k1[7], k1[6], k1[5], k1[4]]),
            Data([k1[3], k1[2], k1[1], k1[0]]),
            Data([k2[7], k2[6], k2[5], k2[4]]),
            Data([k2[3], k2[2], k2[1], k2[0]])
        ]
    }

    /// The pure part of the handshake, split out so it can be tested against known vectors.
    /// piccStep1 is the card's AF + ek(RndB); rndA is the reader's 8-byte challenge.
    static func computeExchange(key: Data, piccStep1: Data, rndA: Data) -> (pcdStep2: Data, expectedPiccStep3: Data)? {
        let step1 = piccStep1.bytes
        guard key.count == 16, rndA.count == 8, step1.count == 9, step1[0] == 0xAF else { return nil }
        let encryptedRndB = Data(step1[1...])
        let zeros = Data(repeating: 0, count: 8)
        let rndB = DES.cbcDecrypt(encryptedRndB, key: key, iv: zeros)
        guard rndB.count == 8 else { return nil }
        var token = Data()
        token.append(rndA)
        token.append(DES.rotateLeft(rndB))
        let encrypted = DES.cbcEncrypt(token, key: key, iv: encryptedRndB)
        guard encrypted.count == 16 else { return nil }
        var pcdStep2 = Data([0xAF])
        pcdStep2.append(encrypted)

        let lastBlock = Data(encrypted.suffix(8))
        let encryptedRndARotated = DES.cbcEncrypt(DES.rotateLeft(rndA), key: key, iv: lastBlock)
        guard encryptedRndARotated.count == 8 else { return nil }
        var expected = Data([0x00])
        expected.append(encryptedRndARotated)
        return (pcdStep2, expected)
    }
}
