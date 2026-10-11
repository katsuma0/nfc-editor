import Foundation

enum TagTechnology: String, Codable, Sendable {
    case iso14443A = "ISO 14443-3A"
    case iso14443_4 = "ISO 14443-4"
    case iso15693 = "ISO 15693"
    case feliCa = "FeliCa (ISO 18092)"
}

enum NDEFStatus: String, Codable, Sendable {
    case notSupported, readWrite, readOnly, unknown

    var label: String {
        switch self {
        case .notSupported: return "Not supported"
        case .readWrite: return "Read and write"
        case .readOnly: return "Read only"
        case .unknown: return "Unknown"
        }
    }
}

struct MemoryPage: Codable, Hashable, Identifiable, Sendable {
    var index: Int
    var bytes: Data
    var readable: Bool

    var id: Int { index }

    init(index: Int, bytes: Data, readable: Bool = true) {
        self.index = index
        self.bytes = bytes
        self.readable = readable
    }
}

struct MemoryDump: Codable, Hashable, Sendable {
    var pageSize: Int
    var pages: [MemoryPage]
    var chip: ChipSpec?
    var readAt: Date

    init(pageSize: Int, pages: [MemoryPage], chip: ChipSpec?, readAt: Date) {
        self.pageSize = max(pageSize, 1)
        self.pages = pages
        self.chip = chip
        self.readAt = readAt
    }

    /// Builds a dump from flat bytes (e.g. an imported .bin) with the given page size.
    init(flatBytes: Data, pageSize: Int, chip: ChipSpec?) {
        let size = max(pageSize, 1)
        let bytes = [UInt8](flatBytes)
        var pages: [MemoryPage] = []
        pages.reserveCapacity((bytes.count + size - 1) / size)
        var offset = 0
        var index = 0
        while offset < bytes.count {
            let end = min(offset + size, bytes.count)
            var chunk = Data(bytes[offset..<end])
            if chunk.count < size {
                chunk.append(Data(repeating: 0, count: size - chunk.count))
            }
            pages.append(MemoryPage(index: index, bytes: chunk, readable: true))
            offset += size
            index += 1
        }
        self.init(pageSize: size, pages: pages, chip: chip, readAt: Date())
    }

    var readableByteCount: Int {
        pages.reduce(0) { $0 + ($1.readable ? $1.bytes.count : 0) }
    }

    /// Concatenated bytes of all readable pages in order (unreadable pages become zeros).
    var flatBytes: Data {
        var out = Data()
        out.reserveCapacity(pages.count * pageSize)
        for page in pages {
            if page.readable && !page.bytes.isEmpty {
                if page.bytes.count >= pageSize {
                    out.append(page.bytes.prefix(pageSize))
                } else {
                    out.append(page.bytes)
                    out.append(Data(repeating: 0, count: pageSize - page.bytes.count))
                }
            } else {
                out.append(Data(repeating: 0, count: pageSize))
            }
        }
        return out
    }
}

struct TagField: Codable, Hashable, Identifiable, Sendable {
    var label: String
    var value: String
    var systemImage: String

    var id: String { label }

    init(label: String, value: String, systemImage: String = "info.circle") {
        self.label = label
        self.value = value
        self.systemImage = systemImage
    }
}

struct TagInfo: Codable, Hashable, Identifiable, Sendable {
    var id: UUID
    var scannedAt: Date
    var technology: TagTechnology
    var chip: ChipSpec
    var uid: Data
    var ndefStatus: NDEFStatus
    var ndefCapacity: Int?
    var ndefUsedBytes: Int?
    var records: [NDEFRecord]
    var passwordProtected: Bool?
    var counter: UInt32?
    var counterEnabled: Bool?
    var signature: Data?
    var versionBytes: Data?
    var dump: MemoryDump?
    var extras: [TagField]

    init(technology: TagTechnology, chip: ChipSpec, uid: Data) {
        self.id = UUID()
        self.scannedAt = Date()
        self.technology = technology
        self.chip = chip
        self.uid = uid
        self.ndefStatus = .unknown
        self.ndefCapacity = nil
        self.ndefUsedBytes = nil
        self.records = []
        self.passwordProtected = nil
        self.counter = nil
        self.counterEnabled = nil
        self.signature = nil
        self.versionBytes = nil
        self.dump = nil
        self.extras = []
    }

    // MARK: Display helpers

    /// "ISO 14443-3A (NFC Forum Type 2)"; the parenthetical is omitted when nfcForumType is nil.
    var typeLine: String {
        if let forumType = chip.nfcForumType {
            return "\(chip.isoStandard) (NFC Forum Type \(forumType))"
        }
        return chip.isoStandard
    }

    /// "NXP NTAG216"
    var chipLine: String {
        let manufacturer = chip.manufacturer.trimmingCharacters(in: .whitespacesAndNewlines)
        if manufacturer.isEmpty || manufacturer == "Unknown" || chip.name.hasPrefix(manufacturer) {
            return chip.name
        }
        return "\(manufacturer) \(chip.name)"
    }

    var serialLine: String {
        uid.hexString(separator: ":")
    }

    /// "924 bytes : 231 pages (4 bytes each)" or nil.
    var memoryLine: String? {
        if let pages = chip.totalPages, let total = chip.totalMemoryBytes, pages > 0 {
            return "\(total) bytes : \(pages) pages (\(TagInfo.eachLabel(chip.pageSize)))"
        }
        if let dump = dump, !dump.pages.isEmpty {
            let total = dump.pages.count * dump.pageSize
            return "\(total) bytes : \(dump.pages.count) pages (\(TagInfo.eachLabel(dump.pageSize)))"
        }
        if let user = chip.userMemoryBytes {
            return "\(user) bytes"
        }
        return nil
    }

    /// "15 / 868 bytes (2%)" when ndefCapacity != nil.
    var sizeLine: String? {
        guard let capacity = ndefCapacity else { return nil }
        let used = ndefUsedBytes ?? 0
        let percent: Int
        if capacity > 0 {
            percent = Int((Double(used) / Double(capacity) * 100).rounded())
        } else {
            percent = 0
        }
        return "\(used) / \(capacity) bytes (\(percent)%)"
    }

    /// "0x0044"
    var atqaLine: String? {
        chip.atqa.map { "0x" + $0.hex }
    }

    /// "0x00"
    var sakLine: String? {
        chip.sak.map { "0x" + $0.hex }
    }

    /// "Yes" / "No" / "Unknown"
    var writableLine: String {
        switch ndefStatus {
        case .readWrite: return "Yes"
        case .readOnly, .notSupported: return "No"
        case .unknown: return "Unknown"
        }
    }

    private static func eachLabel(_ pageSize: Int) -> String {
        pageSize == 1 ? "1 byte each" : "\(pageSize) bytes each"
    }
}
