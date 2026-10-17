import Foundation

enum ChipFamily: String, Codable, CaseIterable, Sendable {
    case ntag21x, ntag21xF, ntagI2C, ntag210, ntag203, ultralight, ultralightC, ultralightEV1,
         desfire, ntagDNA, mifarePlus, mifareClassic, icodeSLI, icodeSLIX, icodeSLIX2, icodeDNA,
         st25TV, st25TA, iso15693Generic, iso7816Generic, feliCa, unknown
}

struct ChipSpec: Codable, Hashable, Sendable {
    var name: String
    var manufacturer: String
    var family: ChipFamily
    var nfcForumType: Int?
    var isoStandard: String
    var pageSize: Int
    var totalPages: Int?
    var userPageRange: ClosedRange<Int>?
    var userMemoryBytes: Int?
    var configPage: Int?
    var dynamicLockPage: Int?
    var capabilityContainer: Data?
    var supportsPassword: Bool = false
    var supportsCounter: Bool = false
    var counterCount: Int = 0
    var supportsSignature: Bool = false
    var supportsRawPages: Bool = false
    var atqa: UInt16?
    var sak: UInt8?
    var notes: String?

    var totalMemoryBytes: Int? {
        totalPages.map { $0 * pageSize }
    }

    var cfg0Page: Int? {
        configPage
    }

    var cfg1Page: Int? {
        configPage.map { $0 + 1 }
    }

    var pwdPage: Int? {
        configPage.map { $0 + 2 }
    }

    var packPage: Int? {
        configPage.map { $0 + 3 }
    }
}

enum ChipIdentifier {
    static let ntag213 = type2(
        "NTAG213", family: .ntag21x, totalPages: 45, userPages: 4...39, userBytes: 144,
        configPage: 0x29, dynamicLockPage: 0x28, cc: [0xE1, 0x10, 0x12, 0x00],
        password: true, counters: 1, signature: true
    )

    static let ntag215 = type2(
        "NTAG215", family: .ntag21x, totalPages: 135, userPages: 4...129, userBytes: 504,
        configPage: 0x83, dynamicLockPage: 0x82, cc: [0xE1, 0x10, 0x3E, 0x00],
        password: true, counters: 1, signature: true
    )

    static let ntag216 = type2(
        "NTAG216", family: .ntag21x, totalPages: 231, userPages: 4...225, userBytes: 888,
        configPage: 0xE3, dynamicLockPage: 0xE2, cc: [0xE1, 0x10, 0x6D, 0x00],
        password: true, counters: 1, signature: true
    )

    static let ultralightEV1_11 = type2(
        "MIFARE Ultralight EV1 (MF0UL11)", family: .ultralightEV1, totalPages: 20, userPages: 4...15, userBytes: 48,
        configPage: 0x10, dynamicLockPage: nil, cc: [0xE1, 0x10, 0x06, 0x00],
        password: true, counters: 3, signature: true
    )

    static let ultralightEV1_21 = type2(
        "MIFARE Ultralight EV1 (MF0UL21)", family: .ultralightEV1, totalPages: 41, userPages: 4...35, userBytes: 128,
        configPage: 0x25, dynamicLockPage: 0x24, cc: [0xE1, 0x10, 0x10, 0x00],
        password: true, counters: 3, signature: true
    )

    private static let ntag210 = type2(
        "NTAG210", family: .ntag210, totalPages: 20, userPages: 4...15, userBytes: 48,
        configPage: 0x10, dynamicLockPage: nil, cc: [0xE1, 0x10, 0x06, 0x00],
        password: true, counters: 0, signature: true
    )

    private static let ntag212 = type2(
        "NTAG212", family: .ntag210, totalPages: 41, userPages: 4...35, userBytes: 128,
        configPage: 0x25, dynamicLockPage: 0x24, cc: [0xE1, 0x10, 0x10, 0x00],
        password: true, counters: 0, signature: true
    )

    private static let ntagI2C1k = type2(
        "NTAG I2C 1k", family: .ntagI2C, totalPages: 231, userPages: 4...225, userBytes: 888,
        configPage: nil, dynamicLockPage: nil, cc: [0xE1, 0x10, 0x6D, 0x00],
        password: false, counters: 0, signature: false
    )

    private static let ntagI2C2k = type2(
        "NTAG I2C 2k", family: .ntagI2C, totalPages: 485, userPages: 4...479, userBytes: 1904,
        configPage: nil, dynamicLockPage: nil, cc: [0xE1, 0x10, 0xEA, 0x00],
        password: false, counters: 0, signature: false,
        notes: "Pages above 255 need a sector select and may not be readable."
    )

    /// Parses an 8-byte GET_VERSION response (0x60) from an NTAG/Ultralight EV1 tag. nil if not 8 bytes or vendor != 0x04.
    static func fromGetVersion(_ response: Data) -> ChipSpec? {
        let bytes = [UInt8](response)
        guard bytes.count == 8, bytes[1] == 0x04 else { return nil }
        let productType = bytes[2]
        let subtype = bytes[3]
        let storage = bytes[6]

        switch productType {
        case 0x03:
            switch storage {
            case 0x0B:
                return ultralightEV1_11
            case 0x0E:
                return ultralightEV1_21
            default:
                return type2(
                    "MIFARE Ultralight EV1", family: .ultralightEV1, totalPages: nil, userPages: nil, userBytes: nil,
                    configPage: nil, dynamicLockPage: nil, cc: nil,
                    password: true, counters: 3, signature: true,
                    notes: "Memory size is not known for this version."
                )
            }
        case 0x04:
            if subtype == 0x05 {
                switch storage {
                case 0x13:
                    return ntagI2C1k
                case 0x15:
                    return ntagI2C2k
                default:
                    return type2(
                        "NTAG I2C", family: .ntagI2C, totalPages: nil, userPages: nil, userBytes: nil,
                        configPage: nil, dynamicLockPage: nil, cc: nil,
                        password: false, counters: 0, signature: false,
                        notes: "Memory size is not known for this version."
                    )
                }
            }
            // The NTAG 213 TT uses subtype 0x03 and the same memory layout as a plain NTAG213.
            if subtype == 0x03, storage == 0x0F {
                return ttVariant(of: ntag213)
            }
            let isFVariant = subtype == 0x04
            switch storage {
            case 0x0B:
                return ntag210
            case 0x0E:
                return ntag212
            case 0x0F:
                return isFVariant ? fVariant(of: ntag213) : ntag213
            case 0x11:
                return isFVariant ? fVariant(of: ntag215) : ntag215
            case 0x13:
                return isFVariant ? fVariant(of: ntag216) : ntag216
            default:
                return type2(
                    "NTAG", family: .ntag21x, totalPages: nil, userPages: nil, userBytes: nil,
                    configPage: nil, dynamicLockPage: nil, cc: nil,
                    password: true, counters: 1, signature: true,
                    notes: "Memory size is not known for this version."
                )
            }
        default:
            return type2(
                "NXP Type 2 tag", family: .unknown, totalPages: nil, userPages: nil, userBytes: nil,
                configPage: nil, dynamicLockPage: nil, cc: nil,
                password: false, counters: 0, signature: false
            )
        }
    }

    /// Fallback for Type 2 tags that NAK GET_VERSION. `canReadPage16` = READ 0x10 succeeded, `canReadPage42` = READ 0x2A succeeded.
    static func legacyType2(canReadPage16: Bool, canReadPage42: Bool) -> ChipSpec {
        if !canReadPage16 {
            return type2(
                "MIFARE Ultralight", family: .ultralight, totalPages: 16, userPages: 4...15, userBytes: 48,
                configPage: nil, dynamicLockPage: nil, cc: [0xE1, 0x10, 0x06, 0x00],
                password: false, counters: 0, signature: false
            )
        }
        if !canReadPage42 {
            return type2(
                "NTAG203", family: .ntag203, totalPages: 42, userPages: 4...39, userBytes: 144,
                configPage: nil, dynamicLockPage: 0x28, cc: [0xE1, 0x10, 0x12, 0x00],
                password: false, counters: 0, signature: false
            )
        }
        return type2(
            "MIFARE Ultralight C", family: .ultralightC, totalPages: 48, userPages: 4...39, userBytes: 144,
            configPage: nil, dynamicLockPage: 0x28, cc: [0xE1, 0x10, 0x12, 0x00],
            password: false, counters: 0, signature: false,
            notes: "3DES authentication is not supported by iOS."
        )
    }

    /// DESFire / NTAG DNA from the ISO7816 GetVersion first frame (7 bytes of hardware info after status). nil if unparseable.
    static func fromDESFireVersion(hardware: Data) -> ChipSpec? {
        let bytes = [UInt8](hardware)
        guard bytes.count >= 6, bytes[0] == 0x04 else { return nil }
        let type = bytes[1]
        let major = bytes[3]
        let storage = bytes[5]

        let exactSize = storage & 0x01 == 0
        let size = 1 << min(Int(storage >> 1), 30)
        var sizeSuffix = ""
        if exactSize && size >= 64 {
            sizeSuffix = size % 1024 == 0 ? " \(size / 1024)K" : " \(size)B"
        }

        let name: String
        let family: ChipFamily
        switch type {
        case 0x01:
            let base: String
            switch major {
            case 0x00: base = "MIFARE DESFire D40"
            case 0x01: base = "MIFARE DESFire EV1"
            case 0x12: base = "MIFARE DESFire EV2"
            case 0x33: base = "MIFARE DESFire EV3"
            case 0x22: base = "MIFARE DESFire Light"
            default: base = "MIFARE DESFire"
            }
            name = base + sizeSuffix
            family = .desfire
        case 0x08:
            name = "MIFARE DESFire Light"
            family = .desfire
        case 0x04:
            switch major {
            case 0x30: name = "NTAG 424 DNA"
            case 0x10: name = "NTAG 413 DNA"
            default: name = "NTAG DNA"
            }
            family = .ntagDNA
        case 0x02:
            name = "MIFARE Plus" + sizeSuffix
            family = .mifarePlus
        default:
            name = "NXP ISO 14443-4 tag"
            family = .iso7816Generic
        }

        return ChipSpec(
            name: name,
            manufacturer: "NXP",
            family: family,
            nfcForumType: 4,
            isoStandard: "ISO 14443-4A",
            pageSize: 1,
            totalPages: nil,
            userPageRange: nil,
            userMemoryBytes: exactSize ? size : nil,
            configPage: nil,
            dynamicLockPage: nil,
            capabilityContainer: nil,
            supportsPassword: false,
            supportsCounter: false,
            counterCount: 0,
            supportsSignature: false,
            supportsRawPages: false,
            atqa: 0x0344,
            sak: 0x20,
            notes: nil
        )
    }

    /// ISO15693 from UID (8 bytes, E0 first) and system info. A UID still in Core NFC's LSB-first order is reversed here.
    static func iso15693(uid: Data, icManufacturerCode: Int, icReference: Int?, blockSize: Int?, totalBlocks: Int?) -> ChipSpec {
        var bytes = [UInt8](uid)
        if bytes.count == 8, bytes[0] != 0xE0, bytes[7] == 0xE0 {
            bytes.reverse()
        }
        let manufacturerCode = icManufacturerCode > 0 ? icManufacturerCode : (bytes.count > 1 ? Int(bytes[1]) : 0)
        let icType = bytes.count > 2 ? Int(bytes[2]) : 0
        let effectiveBlockSize = blockSize ?? 4
        let totalBytes = (totalBlocks ?? 0) * effectiveBlockSize

        var name = "ISO 15693 tag"
        var family = ChipFamily.iso15693Generic
        switch manufacturerCode {
        case 0x04:
            switch icType {
            case 0x01:
                if totalBytes >= 316 {
                    name = "ICODE SLIX2"
                    family = .icodeSLIX2
                } else {
                    name = "ICODE SLIX"
                    family = .icodeSLIX
                }
            case 0x02:
                name = "ICODE SLIX-S"
                family = .icodeSLIX
            case 0x03:
                name = "ICODE SLIX-L"
                family = .icodeSLIX
            default:
                name = "ICODE"
                family = .icodeSLI
            }
        case 0x02:
            family = .st25TV
            switch totalBytes {
            case 64: name = "ST25TV512"
            case 256: name = "ST25TV02K"
            case 2048: name = "ST25TV16K"
            case 8192: name = "ST25TV64K"
            default: name = "ST25TV"
            }
        case 0x07:
            name = "Tag-it HF-I"
        default:
            break
        }

        var userRange: ClosedRange<Int>? = nil
        if let blocks = totalBlocks, blocks > 0 {
            userRange = 0...(blocks - 1)
        }

        return ChipSpec(
            name: name,
            manufacturer: manufacturerName(code: manufacturerCode),
            family: family,
            nfcForumType: 5,
            isoStandard: "ISO 15693",
            pageSize: effectiveBlockSize,
            totalPages: totalBlocks,
            userPageRange: userRange,
            userMemoryBytes: totalBlocks.map { $0 * effectiveBlockSize },
            configPage: nil,
            dynamicLockPage: nil,
            capabilityContainer: nil,
            supportsPassword: false,
            supportsCounter: false,
            counterCount: 0,
            supportsSignature: false,
            supportsRawPages: true,
            atqa: nil,
            sak: nil,
            notes: nil
        )
    }

    static func feliCa(systemCode: Data) -> ChipSpec {
        let code = systemCode.uint16BE ?? 0
        let name: String
        switch code {
        case 0x12FC: name = "FeliCa (NDEF)"
        case 0x0003: name = "FeliCa (Suica family)"
        case 0xFE00: name = "FeliCa (common area)"
        case 0x8008: name = "FeliCa (Octopus)"
        default: name = "FeliCa"
        }
        return ChipSpec(
            name: name,
            manufacturer: "Sony",
            family: .feliCa,
            nfcForumType: 3,
            isoStandard: "ISO 18092 (JIS X 6319-4)",
            pageSize: 16,
            totalPages: nil,
            userPageRange: nil,
            userMemoryBytes: nil,
            configPage: nil,
            dynamicLockPage: nil,
            capabilityContainer: nil,
            supportsPassword: false,
            supportsCounter: false,
            counterCount: 0,
            supportsSignature: false,
            supportsRawPages: false,
            atqa: nil,
            sak: nil,
            notes: nil
        )
    }

    static func iso7816Generic() -> ChipSpec {
        ChipSpec(
            name: "ISO 14443-4 tag",
            manufacturer: "Unknown",
            family: .iso7816Generic,
            nfcForumType: 4,
            isoStandard: "ISO 14443-4",
            pageSize: 1,
            totalPages: nil,
            userPageRange: nil,
            userMemoryBytes: nil,
            configPage: nil,
            dynamicLockPage: nil,
            capabilityContainer: nil,
            supportsPassword: false,
            supportsCounter: false,
            counterCount: 0,
            supportsSignature: false,
            supportsRawPages: false,
            atqa: nil,
            sak: nil,
            notes: nil
        )
    }

    /// NTAG/UL-like, unknown size, raw pages allowed, no config.
    static func unknownType2() -> ChipSpec {
        ChipSpec(
            name: "NFC Forum Type 2 tag",
            manufacturer: "Unknown",
            family: .unknown,
            nfcForumType: 2,
            isoStandard: "ISO 14443-3A",
            pageSize: 4,
            totalPages: nil,
            userPageRange: nil,
            userMemoryBytes: nil,
            configPage: nil,
            dynamicLockPage: nil,
            capabilityContainer: nil,
            supportsPassword: false,
            supportsCounter: false,
            counterCount: 0,
            supportsSignature: false,
            supportsRawPages: true,
            atqa: 0x0044,
            sak: 0x00,
            notes: nil
        )
    }

    // MARK: Helpers

    private static func type2(
        _ name: String,
        family: ChipFamily,
        totalPages: Int?,
        userPages: ClosedRange<Int>?,
        userBytes: Int?,
        configPage: Int?,
        dynamicLockPage: Int?,
        cc: [UInt8]?,
        password: Bool,
        counters: Int,
        signature: Bool,
        notes: String? = nil
    ) -> ChipSpec {
        ChipSpec(
            name: name,
            manufacturer: "NXP",
            family: family,
            nfcForumType: 2,
            isoStandard: "ISO 14443-3A",
            pageSize: 4,
            totalPages: totalPages,
            userPageRange: userPages,
            userMemoryBytes: userBytes,
            configPage: configPage,
            dynamicLockPage: dynamicLockPage,
            capabilityContainer: cc.map { Data($0) },
            supportsPassword: password,
            supportsCounter: counters > 0,
            counterCount: counters,
            supportsSignature: signature,
            supportsRawPages: true,
            atqa: 0x0044,
            sak: 0x00,
            notes: notes
        )
    }

    private static func fVariant(of spec: ChipSpec) -> ChipSpec {
        var copy = spec
        copy.name = spec.name + "F"
        copy.family = .ntag21xF
        return copy
    }

    private static func ttVariant(of spec: ChipSpec) -> ChipSpec {
        var copy = spec
        copy.name = spec.name + "TT"
        copy.notes = "Tamper detection wire. The tamper status appears in the tag details."
        return copy
    }

    private static func manufacturerName(code: Int) -> String {
        let names: [Int: String] = [
            0x01: "Motorola",
            0x02: "STMicroelectronics",
            0x03: "Hitachi",
            0x04: "NXP",
            0x05: "Infineon",
            0x06: "Cylink",
            0x07: "Texas Instruments",
            0x08: "Fujitsu",
            0x09: "Matsushita",
            0x0A: "NEC",
            0x0B: "Oki",
            0x0C: "Toshiba",
            0x0D: "Mitsubishi",
            0x0E: "Samsung",
            0x0F: "Hynix",
            0x10: "LG",
            0x11: "Emosyn",
            0x12: "Inside Secure",
            0x13: "Orga",
            0x14: "Sharp",
            0x15: "Atmel",
            0x16: "EM Microelectronic",
            0x17: "KSW Microtec",
            0x18: "ZMD",
            0x19: "Xicor",
            0x1A: "Sony",
            0x1B: "Malaysia Microelectronic",
            0x1C: "Emosyn",
            0x1D: "Shanghai Fudan",
            0x1E: "Magellan",
            0x1F: "Melexis",
            0x20: "Renesas",
            0x21: "Tagsys",
            0x22: "Transcore",
            0x23: "Shanghai Belling",
            0x24: "Masktech",
            0x25: "Innovision",
            0x26: "Hitachi ULSI",
            0x27: "Cypak",
            0x28: "Ricoh",
            0x29: "ASK",
            0x2A: "Unicore",
            0x2B: "Maxim",
            0x2C: "Impinj",
            0x2D: "RightPlug",
            0x2E: "Bridgelux",
            0x2F: "Fudan Microelectronics",
            0x30: "BeeDar",
            0x31: "RFIDsec",
            0x32: "Schweizer",
            0x33: "AMIC",
            0x34: "Mikron",
            0x35: "Fraunhofer",
            0x36: "IDS",
            0x37: "Kovio",
            0x38: "HMT",
            0x39: "Silicon Craft",
            0x3A: "Advanced Film Device",
            0x3B: "Nitecrest",
            0x3C: "Verayo",
            0x3D: "HID Global",
            0x3E: "Productivity Engineering",
            0x3F: "ams",
            0x40: "Gemalto",
            0x41: "Renesas",
            0x42: "3Alogics",
            0x43: "Top TroniQ",
            0x44: "Gentag",
            0x45: "Invengo",
            0x46: "Guangzhou Sysur",
            0x47: "CEITEC",
            0x48: "Shanghai Quanray",
            0x49: "MediaTek",
            0x4A: "Angstrem",
            0x4B: "Celisic",
            0x4C: "LEGIC",
            0x4D: "Balluff",
            0x4E: "Oberthur",
            0x4F: "Silterra",
            0x50: "DELTA",
            0x51: "Giesecke+Devrient",
            0x52: "Shenzhen China Vision",
            0x53: "Shanghai Feiju",
            0x54: "Intel",
            0x55: "Microsensys",
            0x56: "Sonix",
            0x57: "Qualcomm",
            0x58: "Realtek",
            0x59: "Freevision",
            0x5A: "Giantec",
            0x5B: "Angstrem-T",
            0x5C: "Starchip",
            0x5D: "Spirtech",
            0x5E: "Gantner",
            0x5F: "Nordic Semiconductor",
            0x60: "Verisiti",
            0x61: "Wearlinks",
            0x62: "Userstar",
            0x63: "Pragmatic",
            0x65: "Tendyron",
            0x66: "MUTO Smart",
            0x67: "ON Semiconductor",
            0x68: "Tubitak",
            0x69: "Huada Semiconductor",
            0x6A: "Seveney",
            0x6B: "ISSM",
            0x6C: "Wisesec",
            0x7E: "Holtek"
        ]
        if let name = names[code] {
            return name
        }
        if code <= 0 {
            return "Unknown"
        }
        return "Manufacturer 0x" + UInt8(truncatingIfNeeded: code).hex
    }
}
