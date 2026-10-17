import Foundation
import CoreNFC

/// What the NTAG mirrors into the user memory while the tag is read: nothing, the UID,
/// the NFC counter, or both separated by an "x".
enum MirrorKind: String, Codable, CaseIterable {
    case none, uid, counter, both

    var placeholder: String {
        switch self {
        case .none: return ""
        case .uid: return "00000000000000"
        case .counter: return "000000"
        case .both: return "00000000000000x000000"
        }
    }

    var length: Int { placeholder.utf8.count }
}

struct MirrorConfig: Hashable, Codable {
    var kind: MirrorKind
    var page: Int
    var byte: Int
}

enum NTAGMirror {
    /// Reads MIRROR_CONF, MIRROR_BYTE and MIRROR_PAGE out of CFG0.
    static func read(_ tag: NFCMiFareTag, chip: ChipSpec) async throws -> MirrorConfig {
        guard supportsMirroring(chip), let cfg0Page = chip.cfg0Page else {
            throw NFCEditorError.notSupportedOnChip("Mirroring needs an NTAG21x tag.")
        }
        let block = try await MiFareCommands.read(tag, page: cfg0Page)
        let bytes = block.bytes
        guard bytes.count >= 4 else {
            throw NFCEditorError.commandFailed("The configuration page could not be read.")
        }
        let conf = (bytes[0] >> 6) & 0x03
        let mirrorByte = Int((bytes[0] >> 4) & 0x03)
        let mirrorPage = Int(bytes[2])
        let kind: MirrorKind
        switch conf {
        case 1: kind = .uid
        case 2: kind = .counter
        case 3: kind = .both
        default: kind = .none
        }
        return MirrorConfig(kind: kind, page: mirrorPage, byte: mirrorByte)
    }

    /// Writes a URL whose placeholder bytes the chip overwrites with the UID and/or counter, then points CFG0 at them.
    static func writeMirroredURL(_ session: NFCTagReaderSession, _ tag: NFCMiFareTag, chip: ChipSpec, url: String, kind: MirrorKind, password: Data?) async throws -> String {
        guard supportsMirroring(chip) else {
            throw NFCEditorError.notSupportedOnChip("Mirroring needs an NTAG21x tag.")
        }
        guard let cfg0Page = chip.cfg0Page, let userRange = chip.userPageRange else {
            throw NFCEditorError.notSupportedOnChip("This tag does not support mirroring.")
        }

        let mirror = mirroredURL(url: url, kind: kind)
        let record = RecordBuilders.uri(mirror.fullURL)
        let message = NDEFMessageCodec.encode([record])
        let tlvHeaderLength = message.count < 0xFF ? 2 : 4
        let (prefixCode, _) = URIPrefixes.abbreviate(mirror.fullURL)
        let prefixLength = prefixCode == 0 ? 0 : URIPrefixes.table[Int(prefixCode)].utf8.count
        // Record overhead before the URL rest: header 1, type length 1, payload length 1, type 'U' 1, prefix byte 1.
        let byteOffset = tlvHeaderLength + 5 + (mirror.placeholderIndex - prefixLength)
        let start = location(ofOffsetInUserMemory: byteOffset)
        let lastOffset = byteOffset + max(kind.length, 1) - 1
        let lastLocation = location(ofOffsetInUserMemory: lastOffset)
        guard start.page >= 4, lastLocation.page <= userRange.upperBound - 1 else {
            throw NFCEditorError.invalidInput("The mirror does not fit on this tag. Shorten the URL.")
        }

        if let password = password {
            _ = try await MiFareCommands.pwdAuth(tag, password: password)
        }

        session.alertMessage = "Writing the link."
        try await tag.writeNDEF([record].nfcMessage)

        session.alertMessage = "Turning on the mirror."
        let block = try await MiFareCommands.read(tag, page: cfg0Page)
        let config = block.bytes
        guard config.count >= 8 else {
            throw NFCEditorError.commandFailed("The configuration pages could not be read.")
        }

        if kind == .counter || kind == .both {
            var cfg1 = Array(config[4..<8])
            cfg1[0] |= 0x10 // NFC_CNT_EN
            try await MiFareCommands.write(tag, page: cfg0Page + 1, bytes: Data(cfg1))
        }

        var cfg0 = Array(config[0..<4])
        cfg0[0] = (mirrorConfBits(for: kind) << 6) | (UInt8(start.byte) << 4) | (cfg0[0] & 0x04)
        cfg0[2] = UInt8(start.page)
        try await MiFareCommands.write(tag, page: cfg0Page, bytes: Data(cfg0))

        return mirror.fullURL
    }

    /// Clears MIRROR_CONF while keeping the rest of CFG0 (STRG_MOD_EN, MIRROR_BYTE, MIRROR_PAGE, AUTH0).
    static func disable(_ tag: NFCMiFareTag, chip: ChipSpec) async throws {
        guard supportsMirroring(chip), let cfg0Page = chip.cfg0Page else {
            throw NFCEditorError.notSupportedOnChip("Mirroring needs an NTAG21x tag.")
        }
        let block = try await MiFareCommands.read(tag, page: cfg0Page)
        var cfg0 = Array(block.bytes.prefix(4))
        guard cfg0.count == 4 else {
            throw NFCEditorError.commandFailed("The configuration page could not be read.")
        }
        cfg0[0] &= 0x3F
        try await MiFareCommands.write(tag, page: cfg0Page, bytes: Data(cfg0))
    }

    /// User memory starts at page 4; each page is four bytes.
    static func location(ofOffsetInUserMemory offset: Int) -> (page: Int, byte: Int) {
        (page: 4 + offset / 4, byte: offset % 4)
    }

    /// Builds the URL that carries the mirror placeholder, and the UTF-8 offset where the placeholder begins.
    static func mirroredURL(url: String, kind: MirrorKind) -> (fullURL: String, placeholderIndex: Int) {
        let placeholder = kind.placeholder
        if let range = url.range(of: "{mirror}") {
            let prefix = String(url[url.startIndex..<range.lowerBound])
            let suffix = String(url[range.upperBound...])
            return (prefix + placeholder + suffix, prefix.utf8.count)
        }
        return (url + placeholder, url.utf8.count)
    }

    private static func supportsMirroring(_ chip: ChipSpec) -> Bool {
        chip.family == .ntag21x || chip.family == .ntag21xF
    }

    private static func mirrorConfBits(for kind: MirrorKind) -> UInt8 {
        switch kind {
        case .none: return 0
        case .uid: return 1
        case .counter: return 2
        case .both: return 3
        }
    }
}
