import Foundation

/// A tag kept from a scan, or a profile of records ready to write again. Stored as JSON by SavedStore.
struct SavedItem: Codable, Identifiable, Hashable {
    enum Kind: String, Codable {
        case tag, profile
    }

    var id: UUID
    var name: String
    var kind: Kind
    var createdAt: Date
    var updatedAt: Date
    /// Profiles: the source of truth. Tags: derived from the records with RecordDraft.from.
    var drafts: [RecordDraft]
    /// Tags: as read. Profiles: built when saved, empty when one of the drafts was invalid.
    var records: [NDEFRecord]
    /// Tags only.
    var tagInfo: TagInfo?

    static func tag(name: String, info: TagInfo) -> SavedItem {
        let now = Date()
        return SavedItem(
            id: UUID(),
            name: name,
            kind: .tag,
            createdAt: now,
            updatedAt: now,
            drafts: RecordDraft.from(records: info.records),
            records: info.records,
            tagInfo: info
        )
    }

    static func profile(name: String, drafts: [RecordDraft]) -> SavedItem {
        let now = Date()
        return SavedItem(
            id: UUID(),
            name: name,
            kind: .profile,
            createdAt: now,
            updatedAt: now,
            drafts: drafts,
            records: SavedItem.buildRecords(from: drafts),
            tagInfo: nil
        )
    }

    /// "3 records, 181 bytes, NTAG216" for a tag; "2 records, 90 bytes" for a profile.
    var subtitle: String {
        let count = recordCount
        var parts: [String] = [
            count == 1 ? "1 record" : "\(count) records",
            ByteFormatter.bytes(byteCount),
        ]
        if let chip = tagInfo?.chip.name, !chip.isEmpty {
            parts.append(chip)
        }
        return parts.joined(separator: ", ")
    }

    /// Counts what goes onto the tag, so a Bluetooth draft with handover on counts as two records.
    private var recordCount: Int {
        if kind == .profile, records.isEmpty {
            return drafts.count
        }
        return records.count
    }

    private var byteCount: Int {
        switch kind {
        case .tag:
            if records.isEmpty { return 0 }
            return tagInfo?.ndefUsedBytes ?? NDEFMessageCodec.byteCount(records)
        case .profile:
            if drafts.isEmpty { return 0 }
            if !records.isEmpty {
                return NDEFMessageCodec.byteCount(records)
            }
            // An invalid draft leaves the profile without built records, so add up what each draft would take.
            return drafts.reduce(0) { $0 + $1.encodedSize }
        }
    }

    /// Builds every draft, or nothing at all when one of them is invalid.
    static func buildRecords(from drafts: [RecordDraft]) -> [NDEFRecord] {
        (try? drafts.flatMap { try RecordDraft.buildAll($0) }) ?? []
    }

    /// A profile's records always follow its drafts, so they are rebuilt whenever the profile is stored.
    mutating func rebuildProfileRecords() {
        guard kind == .profile else { return }
        records = SavedItem.buildRecords(from: drafts)
    }
}
