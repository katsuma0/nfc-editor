import Foundation

struct WiFiCredential: Codable, Hashable {
    enum Auth: String, Codable, CaseIterable, Identifiable {
        case open = "Open"
        case wpaPSK = "WPA Personal"
        case wpa2PSK = "WPA2 Personal"
        case wpaWpa2PSK = "WPA/WPA2 Personal"
        case wpa3SAE = "WPA3 Personal"

        var id: String { rawValue }

        /// WPA3 is written as WPA2 Personal because readers reject the newer SAE code.
        var wscValue: UInt16 {
            switch self {
            case .open: return 0x0001
            case .wpaPSK: return 0x0002
            case .wpa2PSK: return 0x0020
            case .wpaWpa2PSK: return 0x0022
            case .wpa3SAE: return 0x0020
            }
        }
    }

    enum Encryption: String, Codable, CaseIterable, Identifiable {
        case none = "None"
        case aes = "AES"
        case tkip = "TKIP"
        case aesTKIP = "AES/TKIP"

        var id: String { rawValue }

        var wscValue: UInt16 {
            switch self {
            case .none: return 0x0001
            case .aes: return 0x0008
            case .tkip: return 0x0004
            case .aesTKIP: return 0x000C
            }
        }
    }

    var ssid: String
    var password: String
    var auth: Auth
    var encryption: Encryption
    var hidden: Bool

    static let mimeType = "application/vnd.wfa.wsc"

    private static let attributeCredential: UInt16 = 0x100E
    private static let attributeNetworkIndex: UInt16 = 0x1026
    private static let attributeSSID: UInt16 = 0x1045
    private static let attributeAuthType: UInt16 = 0x1003
    private static let attributeEncryptionType: UInt16 = 0x100F
    private static let attributeNetworkKey: UInt16 = 0x1027
    private static let attributeMACAddress: UInt16 = 0x1020

    func encode() -> Data {
        let isOpen = auth == .open
        let encryptionValue = isOpen ? Encryption.none.wscValue : encryption.wscValue
        let key = isOpen ? "" : password

        var inner = Data()
        WiFiCredential.append(&inner, id: WiFiCredential.attributeNetworkIndex, value: Data([0x01]))
        WiFiCredential.append(&inner, id: WiFiCredential.attributeSSID, value: Data(ssid.utf8))
        WiFiCredential.append(&inner, id: WiFiCredential.attributeAuthType, value: WiFiCredential.bigEndian(auth.wscValue))
        WiFiCredential.append(&inner, id: WiFiCredential.attributeEncryptionType, value: WiFiCredential.bigEndian(encryptionValue))
        WiFiCredential.append(&inner, id: WiFiCredential.attributeNetworkKey, value: Data(key.utf8))
        WiFiCredential.append(&inner, id: WiFiCredential.attributeMACAddress, value: Data(repeating: 0xFF, count: 6))

        var out = Data()
        WiFiCredential.append(&out, id: WiFiCredential.attributeCredential, value: inner)
        return out
    }

    static func decode(_ data: Data) -> WiFiCredential? {
        let top = parseAttributes(data)
        let attributes: [(id: UInt16, value: Data)]
        if let credential = top.first(where: { $0.id == attributeCredential }) {
            attributes = parseAttributes(credential.value)
        } else {
            attributes = top
        }

        guard let ssidData = attributes.first(where: { $0.id == attributeSSID })?.value else { return nil }
        let ssid = String(decoding: ssidData, as: UTF8.self)
        let keyData = attributes.first(where: { $0.id == attributeNetworkKey })?.value ?? Data()
        let password = String(decoding: keyData, as: UTF8.self)

        let authValue = attributes.first(where: { $0.id == attributeAuthType }).flatMap { readUInt16($0.value) }
        let encryptionValue = attributes.first(where: { $0.id == attributeEncryptionType }).flatMap { readUInt16($0.value) }

        let auth: Auth
        switch authValue ?? 0 {
        case 0x0001: auth = .open
        case 0x0002: auth = .wpaPSK
        case 0x0020: auth = .wpa2PSK
        case 0x0022: auth = .wpaWpa2PSK
        case 0x0040: auth = .wpa3SAE
        default: auth = password.isEmpty ? .open : .wpa2PSK
        }

        let encryption: Encryption
        switch encryptionValue ?? 0 {
        case 0x0001: encryption = .none
        case 0x0004: encryption = .tkip
        case 0x0008: encryption = .aes
        case 0x000C: encryption = .aesTKIP
        default: encryption = (auth == .open || password.isEmpty) ? .none : .aes
        }

        return WiFiCredential(ssid: ssid, password: password, auth: auth, encryption: encryption, hidden: false)
    }

    private static func append(_ out: inout Data, id: UInt16, value: Data) {
        let length = UInt16(truncatingIfNeeded: min(value.count, 0xFFFF))
        out.append(bigEndian(id))
        out.append(bigEndian(length))
        out.append(value.prefix(Int(length)))
    }

    private static func bigEndian(_ value: UInt16) -> Data {
        Data([UInt8(value >> 8), UInt8(value & 0xFF)])
    }

    private static func readUInt16(_ data: Data) -> UInt16? {
        let bytes = [UInt8](data)
        guard bytes.count >= 2 else { return nil }
        return UInt16(bytes[0]) << 8 | UInt16(bytes[1])
    }

    private static func parseAttributes(_ data: Data) -> [(id: UInt16, value: Data)] {
        let bytes = [UInt8](data)
        var result: [(id: UInt16, value: Data)] = []
        var offset = 0
        while offset + 4 <= bytes.count {
            let id = UInt16(bytes[offset]) << 8 | UInt16(bytes[offset + 1])
            let length = Int(bytes[offset + 2]) << 8 | Int(bytes[offset + 3])
            offset += 4
            let end = min(offset + length, bytes.count)
            result.append((id, Data(bytes[offset..<end])))
            offset = end
        }
        return result
    }
}
