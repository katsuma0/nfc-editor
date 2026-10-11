import Foundation

extension Data {
    /// "04:58:3A" style when separator = ":"; "04583A" when separator = "". Uppercase.
    func hexString(separator: String = "") -> String {
        let digits: [Character] = Array("0123456789ABCDEF")
        var out = ""
        out.reserveCapacity(count * (2 + separator.count))
        var isFirst = true
        for byte in self {
            if isFirst {
                isFirst = false
            } else if !separator.isEmpty {
                out.append(separator)
            }
            out.append(digits[Int(byte >> 4)])
            out.append(digits[Int(byte & 0x0F)])
        }
        return out
    }

    /// Parses "04 58 3a", "04:58:3A", "04583a", "0x04...". Returns nil if odd length or non-hex.
    init?(hexString: String) {
        let scalars = Array(hexString.normalizedHex.unicodeScalars)
        guard scalars.count % 2 == 0 else { return nil }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(scalars.count / 2)
        var position = 0
        while position < scalars.count {
            guard let high = Data.hexNibble(scalars[position]),
                  let low = Data.hexNibble(scalars[position + 1]) else {
                return nil
            }
            bytes.append(high << 4 | low)
            position += 2
        }
        self.init(bytes)
    }

    private static func hexNibble(_ scalar: Unicode.Scalar) -> UInt8? {
        switch scalar.value {
        case 0x30...0x39: return UInt8(scalar.value - 0x30)
        case 0x41...0x46: return UInt8(scalar.value - 0x41 + 10)
        case 0x61...0x66: return UInt8(scalar.value - 0x61 + 10)
        default: return nil
        }
    }

    /// Bytes as "ABC." style printable ASCII (non-printables become ".").
    var asciiPreview: String {
        var out = ""
        out.reserveCapacity(count)
        for byte in self {
            if byte >= 0x20 && byte <= 0x7E {
                out.append(Character(Unicode.Scalar(byte)))
            } else {
                out.append(".")
            }
        }
        return out
    }

    var bytes: [UInt8] {
        [UInt8](self)
    }

    /// Big-endian UInt16 from first two bytes; nil if count < 2.
    var uint16BE: UInt16? {
        guard count >= 2 else { return nil }
        let first = self[startIndex]
        let second = self[index(after: startIndex)]
        return UInt16(first) << 8 | UInt16(second)
    }

    subscript(safe index: Int) -> UInt8? {
        guard index >= 0, index < count else { return nil }
        return self[startIndex + index]
    }
}

extension FixedWidthInteger {
    /// Zero-padded uppercase hex of the full width, e.g. UInt8 0x4 -> "04", UInt16 -> "0044".
    var hex: String {
        let width = Swift.max(Self.bitWidth / 4, 1)
        let raw = String(UInt64(truncatingIfNeeded: self), radix: 16, uppercase: true)
        if raw.count >= width {
            return String(raw.suffix(width))
        }
        return String(repeating: "0", count: width - raw.count) + raw
    }
}

extension Array where Element == UInt8 {
    var data: Data {
        Data(self)
    }
}

extension String {
    /// Removes spaces, colons, dashes, commas and "0x" prefixes; uppercases. Used to normalize hex input.
    var normalizedHex: String {
        let separators = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ":-,"))
        var out = ""
        for token in components(separatedBy: separators) where !token.isEmpty {
            if token.hasPrefix("0x") || token.hasPrefix("0X") {
                out.append(contentsOf: token.dropFirst(2))
            } else {
                out.append(token)
            }
        }
        return out.uppercased()
    }

    /// normalizedHex is non-empty, even length and only 0-9A-F.
    var isValidHex: Bool {
        let normalized = normalizedHex
        guard !normalized.isEmpty, normalized.count % 2 == 0 else { return false }
        for scalar in normalized.unicodeScalars {
            switch scalar.value {
            case 0x30...0x39, 0x41...0x46:
                continue
            default:
                return false
            }
        }
        return true
    }
}
