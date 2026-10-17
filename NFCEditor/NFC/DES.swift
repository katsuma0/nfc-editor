import Foundation

/// Pure Swift DES and Triple DES. iOS ships CommonCrypto and CryptoKit, but neither is
/// available when this layer is type checked on Linux, and the MIFARE Ultralight C and
/// DESFire legacy authentication flows need raw single and triple DES blocks anyway.
/// Parity bits in the key are ignored, as every real reader does.
enum DES {
    // MARK: Public block and stream operations

    static func encryptBlock(_ block: Data, key: Data) -> Data {
        let subkeys = schedule(from: load64(key))
        return store64(crypt(load64(block), subkeys: subkeys))
    }

    static func decryptBlock(_ block: Data, key: Data) -> Data {
        let subkeys = schedule(from: load64(key))
        return store64(crypt(load64(block), subkeys: subkeys.reversed()))
    }

    static func tdeaEncryptBlock(_ block: Data, key: Data) -> Data {
        let (k1, k2, k3) = tripleKeys(key)
        let c1 = encryptBlock(block, key: k1)
        let c2 = decryptBlock(c1, key: k2)
        return encryptBlock(c2, key: k3)
    }

    static func tdeaDecryptBlock(_ block: Data, key: Data) -> Data {
        let (k1, k2, k3) = tripleKeys(key)
        let d1 = decryptBlock(block, key: k3)
        let d2 = encryptBlock(d1, key: k2)
        return decryptBlock(d2, key: k1)
    }

    static func cbcEncrypt(_ data: Data, key: Data, iv: Data) -> Data {
        let single = key.count == 8
        var previous = padBlock(iv)
        var output = Data()
        output.reserveCapacity(data.count)
        for block in wholeBlocks(data) {
            let input = xor(block, previous)
            let cipher = single ? encryptBlock(input, key: key) : tdeaEncryptBlock(input, key: key)
            output.append(cipher)
            previous = cipher
        }
        return output
    }

    static func cbcDecrypt(_ data: Data, key: Data, iv: Data) -> Data {
        let single = key.count == 8
        var previous = padBlock(iv)
        var output = Data()
        output.reserveCapacity(data.count)
        for block in wholeBlocks(data) {
            let plain = single ? decryptBlock(block, key: key) : tdeaDecryptBlock(block, key: key)
            output.append(xor(plain, previous))
            previous = block
        }
        return output
    }

    static func xor(_ a: Data, _ b: Data) -> Data {
        let count = Swift.min(a.count, b.count)
        var out = Data(capacity: count)
        let ab = [UInt8](a), bb = [UInt8](b)
        for i in 0..<count {
            out.append(ab[i] ^ bb[i])
        }
        return out
    }

    static func rotateLeft(_ d: Data) -> Data {
        guard d.count > 1 else { return d }
        var bytes = [UInt8](d)
        let first = bytes.removeFirst()
        bytes.append(first)
        return Data(bytes)
    }

    // MARK: Key splitting

    private static func tripleKeys(_ key: Data) -> (Data, Data, Data) {
        let bytes = [UInt8](key)
        if bytes.count >= 24 {
            return (Data(bytes[0..<8]), Data(bytes[8..<16]), Data(bytes[16..<24]))
        }
        if bytes.count >= 16 {
            let k1 = Data(bytes[0..<8])
            return (k1, Data(bytes[8..<16]), k1)
        }
        let k1 = padBlock(key)
        return (k1, k1, k1)
    }

    // MARK: Block helpers

    private static func padBlock(_ d: Data) -> Data {
        var bytes = [UInt8](d.prefix(8))
        while bytes.count < 8 { bytes.append(0) }
        return Data(bytes)
    }

    private static func wholeBlocks(_ data: Data) -> [Data] {
        let bytes = [UInt8](data)
        var blocks: [Data] = []
        var offset = 0
        while offset + 8 <= bytes.count {
            blocks.append(Data(bytes[offset..<offset + 8]))
            offset += 8
        }
        return blocks
    }

    private static func load64(_ d: Data) -> UInt64 {
        var value: UInt64 = 0
        for byte in padBlock(d) {
            value = (value << 8) | UInt64(byte)
        }
        return value
    }

    private static func store64(_ value: UInt64) -> Data {
        var bytes = [UInt8]()
        bytes.reserveCapacity(8)
        for shift in stride(from: 56, through: 0, by: -8) {
            bytes.append(UInt8((value >> UInt64(shift)) & 0xFF))
        }
        return Data(bytes)
    }

    // MARK: Core DES

    /// Permutes the low `inBits` bits of `input`, numbering bit 1 as the most significant.
    private static func permute(_ input: UInt64, _ table: [Int], inBits: Int) -> UInt64 {
        var output: UInt64 = 0
        for position in table {
            let bit = (input >> UInt64(inBits - position)) & 1
            output = (output << 1) | bit
        }
        return output
    }

    private static func rotl28(_ value: UInt32, _ amount: Int) -> UInt32 {
        let mask: UInt32 = 0x0FFF_FFFF
        return ((value << UInt32(amount)) | (value >> UInt32(28 - amount))) & mask
    }

    private static func schedule(from key: UInt64) -> [UInt64] {
        let permuted = permute(key, pc1, inBits: 64)
        var c = UInt32((permuted >> 28) & 0x0FFF_FFFF)
        var d = UInt32(permuted & 0x0FFF_FFFF)
        var subkeys: [UInt64] = []
        subkeys.reserveCapacity(16)
        for shift in shifts {
            c = rotl28(c, shift)
            d = rotl28(d, shift)
            let cd = (UInt64(c) << 28) | UInt64(d)
            subkeys.append(permute(cd, pc2, inBits: 56))
        }
        return subkeys
    }

    private static func feistel(_ half: UInt32, _ subkey: UInt64) -> UInt32 {
        let expanded = permute(UInt64(half), expansion, inBits: 32) ^ subkey
        var combined: UInt32 = 0
        for box in 0..<8 {
            let six = UInt8((expanded >> UInt64(42 - 6 * box)) & 0x3F)
            let row = Int(((six & 0x20) >> 4) | (six & 0x01))
            let column = Int((six >> 1) & 0x0F)
            combined = (combined << 4) | UInt32(sboxes[box][row * 16 + column])
        }
        return UInt32(permute(UInt64(combined), permutationP, inBits: 32))
    }

    private static func crypt(_ block: UInt64, subkeys: [UInt64]) -> UInt64 {
        let permuted = permute(block, initialPermutation, inBits: 64)
        var left = UInt32((permuted >> 32) & 0xFFFF_FFFF)
        var right = UInt32(permuted & 0xFFFF_FFFF)
        for subkey in subkeys {
            let next = left ^ feistel(right, subkey)
            left = right
            right = next
        }
        let preoutput = (UInt64(right) << 32) | UInt64(left)
        return permute(preoutput, finalPermutation, inBits: 64)
    }

    // MARK: Standard tables

    private static let initialPermutation: [Int] = [
        58, 50, 42, 34, 26, 18, 10, 2, 60, 52, 44, 36, 28, 20, 12, 4,
        62, 54, 46, 38, 30, 22, 14, 6, 64, 56, 48, 40, 32, 24, 16, 8,
        57, 49, 41, 33, 25, 17, 9, 1, 59, 51, 43, 35, 27, 19, 11, 3,
        61, 53, 45, 37, 29, 21, 13, 5, 63, 55, 47, 39, 31, 23, 15, 7
    ]

    private static let finalPermutation: [Int] = [
        40, 8, 48, 16, 56, 24, 64, 32, 39, 7, 47, 15, 55, 23, 63, 31,
        38, 6, 46, 14, 54, 22, 62, 30, 37, 5, 45, 13, 53, 21, 61, 29,
        36, 4, 44, 12, 52, 20, 60, 28, 35, 3, 43, 11, 51, 19, 59, 27,
        34, 2, 42, 10, 50, 18, 58, 26, 33, 1, 41, 9, 49, 17, 57, 25
    ]

    private static let expansion: [Int] = [
        32, 1, 2, 3, 4, 5, 4, 5, 6, 7, 8, 9, 8, 9, 10, 11,
        12, 13, 12, 13, 14, 15, 16, 17, 16, 17, 18, 19, 20, 21, 20, 21,
        22, 23, 24, 25, 24, 25, 26, 27, 28, 29, 28, 29, 30, 31, 32, 1
    ]

    private static let permutationP: [Int] = [
        16, 7, 20, 21, 29, 12, 28, 17, 1, 15, 23, 26, 5, 18, 31, 10,
        2, 8, 24, 14, 32, 27, 3, 9, 19, 13, 30, 6, 22, 11, 4, 25
    ]

    private static let pc1: [Int] = [
        57, 49, 41, 33, 25, 17, 9, 1, 58, 50, 42, 34, 26, 18,
        10, 2, 59, 51, 43, 35, 27, 19, 11, 3, 60, 52, 44, 36,
        63, 55, 47, 39, 31, 23, 15, 7, 62, 54, 46, 38, 30, 22,
        14, 6, 61, 53, 45, 37, 29, 21, 13, 5, 28, 20, 12, 4
    ]

    private static let pc2: [Int] = [
        14, 17, 11, 24, 1, 5, 3, 28, 15, 6, 21, 10,
        23, 19, 12, 4, 26, 8, 16, 7, 27, 20, 13, 2,
        41, 52, 31, 37, 47, 55, 30, 40, 51, 45, 33, 48,
        44, 49, 39, 56, 34, 53, 46, 42, 50, 36, 29, 32
    ]

    private static let shifts: [Int] = [1, 1, 2, 2, 2, 2, 2, 2, 1, 2, 2, 2, 2, 2, 2, 1]

    private static let sboxes: [[UInt8]] = [
        [14, 4, 13, 1, 2, 15, 11, 8, 3, 10, 6, 12, 5, 9, 0, 7,
         0, 15, 7, 4, 14, 2, 13, 1, 10, 6, 12, 11, 9, 5, 3, 8,
         4, 1, 14, 8, 13, 6, 2, 11, 15, 12, 9, 7, 3, 10, 5, 0,
         15, 12, 8, 2, 4, 9, 1, 7, 5, 11, 3, 14, 10, 0, 6, 13],
        [15, 1, 8, 14, 6, 11, 3, 4, 9, 7, 2, 13, 12, 0, 5, 10,
         3, 13, 4, 7, 15, 2, 8, 14, 12, 0, 1, 10, 6, 9, 11, 5,
         0, 14, 7, 11, 10, 4, 13, 1, 5, 8, 12, 6, 9, 3, 2, 15,
         13, 8, 10, 1, 3, 15, 4, 2, 11, 6, 7, 12, 0, 5, 14, 9],
        [10, 0, 9, 14, 6, 3, 15, 5, 1, 13, 12, 7, 11, 4, 2, 8,
         13, 7, 0, 9, 3, 4, 6, 10, 2, 8, 5, 14, 12, 11, 15, 1,
         13, 6, 4, 9, 8, 15, 3, 0, 11, 1, 2, 12, 5, 10, 14, 7,
         1, 10, 13, 0, 6, 9, 8, 7, 4, 15, 14, 3, 11, 5, 2, 12],
        [7, 13, 14, 3, 0, 6, 9, 10, 1, 2, 8, 5, 11, 12, 4, 15,
         13, 8, 11, 5, 6, 15, 0, 3, 4, 7, 2, 12, 1, 10, 14, 9,
         10, 6, 9, 0, 12, 11, 7, 13, 15, 1, 3, 14, 5, 2, 8, 4,
         3, 15, 0, 6, 10, 1, 13, 8, 9, 4, 5, 11, 12, 7, 2, 14],
        [2, 12, 4, 1, 7, 10, 11, 6, 8, 5, 3, 15, 13, 0, 14, 9,
         14, 11, 2, 12, 4, 7, 13, 1, 5, 0, 15, 10, 3, 9, 8, 6,
         4, 2, 1, 11, 10, 13, 7, 8, 15, 9, 12, 5, 6, 3, 0, 14,
         11, 8, 12, 7, 1, 14, 2, 13, 6, 15, 0, 9, 10, 4, 5, 3],
        [12, 1, 10, 15, 9, 2, 6, 8, 0, 13, 3, 4, 14, 7, 5, 11,
         10, 15, 4, 2, 7, 12, 9, 5, 6, 1, 13, 14, 0, 11, 3, 8,
         9, 14, 15, 5, 2, 8, 12, 3, 7, 0, 4, 10, 1, 13, 11, 6,
         4, 3, 2, 12, 9, 5, 15, 10, 11, 14, 1, 7, 6, 0, 8, 13],
        [4, 11, 2, 14, 15, 0, 8, 13, 3, 12, 9, 7, 5, 10, 6, 1,
         13, 0, 11, 7, 4, 9, 1, 10, 14, 3, 5, 12, 2, 15, 8, 6,
         1, 4, 11, 13, 12, 3, 7, 14, 10, 15, 6, 8, 0, 5, 9, 2,
         6, 11, 13, 8, 1, 4, 10, 7, 9, 5, 0, 15, 14, 2, 3, 12],
        [13, 2, 8, 4, 6, 15, 11, 1, 10, 9, 3, 14, 5, 0, 12, 7,
         1, 15, 13, 8, 10, 3, 7, 4, 12, 5, 6, 11, 0, 14, 9, 2,
         7, 11, 4, 1, 9, 12, 14, 2, 0, 6, 10, 13, 15, 3, 5, 8,
         2, 1, 14, 7, 4, 10, 8, 13, 15, 12, 9, 0, 3, 5, 6, 11]
    ]
}
