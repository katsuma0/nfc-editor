import Foundation

struct BluetoothOOB: Codable, Hashable {
    var address: String
    var name: String?

    static let mimeType = "application/vnd.bluetooth.ep.oob"

    private static let eirCompleteLocalName: UInt8 = 0x09
    private static let eirShortenedLocalName: UInt8 = 0x08
    private static let adLEAddress: UInt8 = 0x1B

    func encode() -> Data {
        let addressBytes = BluetoothOOB.addressBytes(address) ?? [UInt8](repeating: 0, count: 6)
        var body = Data()
        // The OOB block carries the address least significant byte first.
        body.append(contentsOf: addressBytes.reversed())

        if let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty {
            let nameBytes = Array(trimmed.utf8.prefix(248))
            body.append(UInt8(nameBytes.count + 1))
            body.append(BluetoothOOB.eirCompleteLocalName)
            body.append(contentsOf: nameBytes)
        }

        let total = body.count + 2
        var out = Data()
        out.append(UInt8(total & 0xFF))
        out.append(UInt8((total >> 8) & 0xFF))
        out.append(body)
        return out
    }

    static func decode(_ data: Data) -> BluetoothOOB? {
        let bytes = [UInt8](data)
        guard bytes.count >= 8 else { return nil }

        let declaredLength = Int(bytes[0]) | Int(bytes[1]) << 8
        // A Low Energy OOB payload has no length prefix; it is a bare list of AD structures.
        if declaredLength != bytes.count, let lowEnergy = decodeLowEnergy(bytes) {
            return lowEnergy
        }

        let addressBytes = Array(bytes[2..<8].reversed())
        let end = declaredLength > 0 ? min(declaredLength, bytes.count) : bytes.count
        var completeName: String?
        var shortName: String?
        var offset = 8
        while offset + 1 < end {
            let length = Int(bytes[offset])
            if length == 0 { break }
            let type = bytes[offset + 1]
            let valueStart = offset + 2
            let valueEnd = min(offset + 1 + length, end)
            if valueEnd >= valueStart {
                let value = bytes[valueStart..<valueEnd]
                if type == eirCompleteLocalName {
                    completeName = String(decoding: value, as: UTF8.self)
                } else if type == eirShortenedLocalName {
                    shortName = String(decoding: value, as: UTF8.self)
                }
            }
            offset += 1 + length
        }

        return BluetoothOOB(address: formatAddress(addressBytes), name: cleanName(completeName ?? shortName))
    }

    private static func decodeLowEnergy(_ bytes: [UInt8]) -> BluetoothOOB? {
        var foundAddress: [UInt8]?
        var completeName: String?
        var shortName: String?
        var offset = 0
        while offset < bytes.count {
            let length = Int(bytes[offset])
            if length == 0 { break }
            let end = offset + 1 + length
            guard end <= bytes.count else { return nil }
            let type = bytes[offset + 1]
            let value = bytes[(offset + 2)..<end]
            switch type {
            case adLEAddress:
                // Six address bytes least significant first, then one address type byte.
                guard value.count == 7 else { return nil }
                foundAddress = Array(value.prefix(6).reversed())
            case eirCompleteLocalName:
                completeName = String(decoding: value, as: UTF8.self)
            case eirShortenedLocalName:
                shortName = String(decoding: value, as: UTF8.self)
            default:
                break
            }
            offset = end
        }
        guard let foundAddress else { return nil }
        return BluetoothOOB(address: formatAddress(foundAddress), name: cleanName(completeName ?? shortName))
    }

    private static func formatAddress(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02X", $0) }.joined(separator: ":")
    }

    private static func cleanName(_ name: String?) -> String? {
        guard let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }

    static func isValidAddress(_ s: String) -> Bool {
        addressBytes(s) != nil
    }

    private static func addressBytes(_ s: String) -> [UInt8]? {
        let separators: Set<Character> = [":", "-", ".", " "]
        let cleaned = Array(s.uppercased().filter { !separators.contains($0) })
        guard cleaned.count == 12, cleaned.allSatisfy({ $0.isHexDigit }) else { return nil }
        var result: [UInt8] = []
        for index in stride(from: 0, to: 12, by: 2) {
            guard let byte = UInt8(String(cleaned[index...index + 1]), radix: 16) else { return nil }
            result.append(byte)
        }
        return result
    }
}
