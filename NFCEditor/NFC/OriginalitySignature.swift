import Foundation

/// The verdict of an NXP originality signature check.
enum SignatureVerdict: String, Codable {
    case genuine, notGenuine, noKey
}

/// Verifies the ECDSA originality signature that NXP writes into NTAG21x and Ultralight EV1
/// chips at the factory. The curve is secp128r1 and the message is the raw UID with no hash,
/// so neither CryptoKit (which lacks the curve) nor CommonCrypto is usable; the field and
/// curve arithmetic is done with a small fixed size unsigned big integer below.
enum OriginalitySignature {
    static let ntag21xPublicKey = Data(hexString: "04494E1A386D3D3CFE3DC10E5DE68A499B1C202DB5B132393E89ED19FE5BE8BC61")!
    static let ultralightEV1PublicKey = Data(hexString: "0490933BDCD6E99B4E255E3DA55389A827564E11718E017292FAF23226A96614B8")!

    static func publicKey(for chip: ChipSpec) -> Data? {
        switch chip.family {
        case .ntag21x, .ntag21xF, .ntag210, .ntagI2C:
            return ntag21xPublicKey
        case .ultralightEV1:
            return ultralightEV1PublicKey
        default:
            return nil
        }
    }

    static func verify(signature: Data, uid: Data, chip: ChipSpec) -> SignatureVerdict {
        guard let key = publicKey(for: chip) else { return .noKey }
        return verify(signature: signature, uid: uid, publicKey: key) ? .genuine : .notGenuine
    }

    static func verify(signature: Data, uid: Data, publicKey: Data) -> Bool {
        let key = [UInt8](publicKey)
        guard key.count == 33, key[0] == 0x04 else { return false }
        let sig = [UInt8](signature)
        guard sig.count == 32 else { return false }

        let curve = Secp128r1.self
        let qx = OSBigUInt(bigEndian: Array(key[1..<17]))
        let qy = OSBigUInt(bigEndian: Array(key[17..<33]))
        let publicPoint = OSPoint(x: qx, y: qy)

        let r = OSBigUInt(bigEndian: Array(sig[0..<16]))
        let s = OSBigUInt(bigEndian: Array(sig[16..<32]))
        guard !r.isZero, r < curve.n, !s.isZero, s < curve.n else { return false }

        // The UID is only 56 bits, well under the 128 bit order, so it is used whole.
        let z = OSBigUInt(bigEndian: [UInt8](uid))
        let w = s.modInverse(curve.n)
        let u1 = OSBigUInt.mulMod(z, w, curve.n)
        let u2 = OSBigUInt.mulMod(r, w, curve.n)

        let point1 = OSPoint.scalarMultiply(u1, curve.g, p: curve.p, a: curve.a)
        let point2 = OSPoint.scalarMultiply(u2, publicPoint, p: curve.p, a: curve.a)
        let sum = OSPoint.add(point1, point2, p: curve.p, a: curve.a)
        guard !sum.isInfinity else { return false }

        return (sum.x % curve.n) == r
    }
}

// MARK: - secp128r1 domain parameters

private enum Secp128r1 {
    static let p = OSBigUInt(bigEndian: "FFFFFFFDFFFFFFFFFFFFFFFFFFFFFFFF")
    static let a = OSBigUInt(bigEndian: "FFFFFFFDFFFFFFFFFFFFFFFFFFFFFFFC")
    static let n = OSBigUInt(bigEndian: "FFFFFFFE0000000075A30D1B9038A115")
    static let g = OSPoint(
        x: OSBigUInt(bigEndian: "161FF7528B899B2D0C28607CA52C5B86"),
        y: OSBigUInt(bigEndian: "CF5AC8395BAFEB13C02DA292DDED7A83")
    )
}

// MARK: - Affine point arithmetic over the prime field

private struct OSPoint {
    var x: OSBigUInt
    var y: OSBigUInt
    var isInfinity: Bool

    init(x: OSBigUInt, y: OSBigUInt) {
        self.x = x
        self.y = y
        self.isInfinity = false
    }

    private init(infinity: Bool) {
        self.x = OSBigUInt()
        self.y = OSBigUInt()
        self.isInfinity = infinity
    }

    static let infinity = OSPoint(infinity: true)

    static func add(_ lhs: OSPoint, _ rhs: OSPoint, p: OSBigUInt, a: OSBigUInt) -> OSPoint {
        if lhs.isInfinity { return rhs }
        if rhs.isInfinity { return lhs }
        if lhs.x == rhs.x {
            if OSBigUInt.addMod(lhs.y, rhs.y, p).isZero { return .infinity }
            return double(lhs, p: p, a: a)
        }
        let numerator = OSBigUInt.subMod(rhs.y, lhs.y, p)
        let denominator = OSBigUInt.subMod(rhs.x, lhs.x, p)
        let lambda = OSBigUInt.mulMod(numerator, denominator.modInverse(p), p)
        let x3 = OSBigUInt.subMod(OSBigUInt.subMod(OSBigUInt.mulMod(lambda, lambda, p), lhs.x, p), rhs.x, p)
        let y3 = OSBigUInt.subMod(OSBigUInt.mulMod(lambda, OSBigUInt.subMod(lhs.x, x3, p), p), lhs.y, p)
        return OSPoint(x: x3, y: y3)
    }

    static func double(_ point: OSPoint, p: OSBigUInt, a: OSBigUInt) -> OSPoint {
        if point.isInfinity { return point }
        if point.y.isZero { return .infinity }
        let xSquared = OSBigUInt.mulMod(point.x, point.x, p)
        let numerator = OSBigUInt.addMod(OSBigUInt.mulMod(OSBigUInt(3), xSquared, p), a, p)
        let denominator = OSBigUInt.mulMod(OSBigUInt(2), point.y, p)
        let lambda = OSBigUInt.mulMod(numerator, denominator.modInverse(p), p)
        let x3 = OSBigUInt.subMod(OSBigUInt.mulMod(lambda, lambda, p), OSBigUInt.mulMod(OSBigUInt(2), point.x, p), p)
        let y3 = OSBigUInt.subMod(OSBigUInt.mulMod(lambda, OSBigUInt.subMod(point.x, x3, p), p), point.y, p)
        return OSPoint(x: x3, y: y3)
    }

    static func scalarMultiply(_ k: OSBigUInt, _ point: OSPoint, p: OSBigUInt, a: OSBigUInt) -> OSPoint {
        var result = OSPoint.infinity
        var addend = point
        let width = k.bitWidth
        var i = 0
        while i < width {
            if k.bit(i) == 1 {
                result = add(result, addend, p: p, a: a)
            }
            addend = double(addend, p: p, a: a)
            i += 1
        }
        return result
    }
}

// MARK: - Minimal unsigned big integer, little-endian UInt32 limbs

private struct OSBigUInt: Comparable {
    var limbs: [UInt32]

    init() {
        limbs = []
    }

    init(_ value: UInt32) {
        limbs = value == 0 ? [] : [value]
    }

    init(limbs: [UInt32]) {
        self.limbs = limbs
        normalize()
    }

    init(bigEndian bytes: [UInt8]) {
        var built: [UInt32] = []
        var current: UInt32 = 0
        var shift: UInt32 = 0
        var index = bytes.count - 1
        while index >= 0 {
            current |= UInt32(bytes[index]) << shift
            shift += 8
            if shift == 32 {
                built.append(current)
                current = 0
                shift = 0
            }
            index -= 1
        }
        if shift != 0 { built.append(current) }
        self.limbs = built
        normalize()
    }

    init(bigEndian hex: String) {
        self.init(bigEndian: [UInt8](Data(hexString: hex) ?? Data()))
    }

    private mutating func normalize() {
        while let last = limbs.last, last == 0 {
            limbs.removeLast()
        }
    }

    var isZero: Bool { limbs.isEmpty }

    var bitWidth: Int {
        guard let last = limbs.last else { return 0 }
        return (limbs.count - 1) * 32 + (32 - last.leadingZeroBitCount)
    }

    func bit(_ index: Int) -> UInt32 {
        let limbIndex = index >> 5
        guard limbIndex < limbs.count else { return 0 }
        return (limbs[limbIndex] >> UInt32(index & 31)) & 1
    }

    func toData(count: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        for position in 0..<count {
            let bitOffset = position * 8
            let limbIndex = bitOffset >> 5
            guard limbIndex < limbs.count else { break }
            let value = UInt64(limbs[limbIndex]) >> UInt64(bitOffset & 31)
            // Spanning two limbs happens only when the limb boundary falls inside a byte,
            // which never occurs here because 32 is a multiple of 8, so one limb is enough.
            bytes[count - 1 - position] = UInt8(value & 0xFF)
        }
        return Data(bytes)
    }

    static func == (lhs: OSBigUInt, rhs: OSBigUInt) -> Bool {
        lhs.limbs == rhs.limbs
    }

    static func < (lhs: OSBigUInt, rhs: OSBigUInt) -> Bool {
        if lhs.limbs.count != rhs.limbs.count {
            return lhs.limbs.count < rhs.limbs.count
        }
        var i = lhs.limbs.count - 1
        while i >= 0 {
            if lhs.limbs[i] != rhs.limbs[i] {
                return lhs.limbs[i] < rhs.limbs[i]
            }
            i -= 1
        }
        return false
    }

    static func + (lhs: OSBigUInt, rhs: OSBigUInt) -> OSBigUInt {
        var result: [UInt32] = []
        let count = Swift.max(lhs.limbs.count, rhs.limbs.count)
        result.reserveCapacity(count + 1)
        var carry: UInt64 = 0
        for i in 0..<count {
            let a = i < lhs.limbs.count ? UInt64(lhs.limbs[i]) : 0
            let b = i < rhs.limbs.count ? UInt64(rhs.limbs[i]) : 0
            let sum = a + b + carry
            result.append(UInt32(sum & 0xFFFF_FFFF))
            carry = sum >> 32
        }
        if carry != 0 { result.append(UInt32(carry)) }
        return OSBigUInt(limbs: result)
    }

    /// Assumes lhs >= rhs.
    static func - (lhs: OSBigUInt, rhs: OSBigUInt) -> OSBigUInt {
        var result: [UInt32] = []
        result.reserveCapacity(lhs.limbs.count)
        var borrow: Int64 = 0
        for i in 0..<lhs.limbs.count {
            let a = Int64(lhs.limbs[i])
            let b = i < rhs.limbs.count ? Int64(rhs.limbs[i]) : 0
            var diff = a - b - borrow
            if diff < 0 {
                diff += 0x1_0000_0000
                borrow = 1
            } else {
                borrow = 0
            }
            result.append(UInt32(diff))
        }
        return OSBigUInt(limbs: result)
    }

    static func * (lhs: OSBigUInt, rhs: OSBigUInt) -> OSBigUInt {
        if lhs.isZero || rhs.isZero { return OSBigUInt() }
        var result = [UInt32](repeating: 0, count: lhs.limbs.count + rhs.limbs.count)
        for i in 0..<lhs.limbs.count {
            var carry: UInt64 = 0
            let a = UInt64(lhs.limbs[i])
            for j in 0..<rhs.limbs.count {
                let index = i + j
                let current = UInt64(result[index]) + a * UInt64(rhs.limbs[j]) + carry
                result[index] = UInt32(current & 0xFFFF_FFFF)
                carry = current >> 32
            }
            var index = i + rhs.limbs.count
            while carry != 0 {
                let current = UInt64(result[index]) + carry
                result[index] = UInt32(current & 0xFFFF_FFFF)
                carry = current >> 32
                index += 1
            }
        }
        return OSBigUInt(limbs: result)
    }

    private func shiftedLeftByOne() -> OSBigUInt {
        if isZero { return self }
        var result: [UInt32] = []
        result.reserveCapacity(limbs.count + 1)
        var carry: UInt32 = 0
        for limb in limbs {
            result.append((limb << 1) | carry)
            carry = limb >> 31
        }
        if carry != 0 { result.append(carry) }
        return OSBigUInt(limbs: result)
    }

    private func settingBit0() -> OSBigUInt {
        var result = limbs
        if result.isEmpty {
            result = [1]
        } else {
            result[0] |= 1
        }
        return OSBigUInt(limbs: result)
    }

    /// Binary long division by repeated shift and subtract. Returns quotient and remainder.
    static func divMod(_ dividend: OSBigUInt, _ divisor: OSBigUInt) -> (OSBigUInt, OSBigUInt) {
        if dividend < divisor { return (OSBigUInt(), dividend) }
        let width = dividend.bitWidth
        var quotient = [UInt32](repeating: 0, count: (width + 31) / 32)
        var remainder = OSBigUInt()
        var i = width - 1
        while i >= 0 {
            remainder = remainder.shiftedLeftByOne()
            if dividend.bit(i) == 1 {
                remainder = remainder.settingBit0()
            }
            if !(remainder < divisor) {
                remainder = remainder - divisor
                quotient[i >> 5] |= 1 << UInt32(i & 31)
            }
            i -= 1
        }
        return (OSBigUInt(limbs: quotient), remainder)
    }

    static func % (lhs: OSBigUInt, rhs: OSBigUInt) -> OSBigUInt {
        divMod(lhs, rhs).1
    }

    static func addMod(_ a: OSBigUInt, _ b: OSBigUInt, _ m: OSBigUInt) -> OSBigUInt {
        (a + b) % m
    }

    static func subMod(_ a: OSBigUInt, _ b: OSBigUInt, _ m: OSBigUInt) -> OSBigUInt {
        let left = a % m
        let right = b % m
        if !(left < right) { return left - right }
        return (left + m) - right
    }

    static func mulMod(_ a: OSBigUInt, _ b: OSBigUInt, _ m: OSBigUInt) -> OSBigUInt {
        (a * b) % m
    }

    /// Inverse modulo m, found with the extended Euclidean algorithm. The coefficient is kept
    /// reduced modulo m throughout so every value stays unsigned.
    func modInverse(_ m: OSBigUInt) -> OSBigUInt {
        var r = m
        var newR = self % m
        var t = OSBigUInt()
        var newT = OSBigUInt(1)
        while !newR.isZero {
            let (q, rem) = OSBigUInt.divMod(r, newR)
            r = newR
            newR = rem
            let product = OSBigUInt.mulMod(q, newT, m)
            let nextT = OSBigUInt.subMod(t, product, m)
            t = newT
            newT = nextT
        }
        return t % m
    }
}
