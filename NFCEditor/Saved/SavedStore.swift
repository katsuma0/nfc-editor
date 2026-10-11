import Foundation
import Observation

/// Keeps saved tags and profiles in Documents/saved-items.json. Everything stays on the device.
@MainActor @Observable
final class SavedStore {
    /// Sorted by updatedAt, newest first.
    private(set) var items: [SavedItem] = []

    private let fileURL: URL

    init() {
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        fileURL = directory.appendingPathComponent("saved-items.json")
        items = SavedStore.load(from: fileURL)
    }

    // MARK: Changes

    func add(_ item: SavedItem) {
        items.removeAll { $0.id == item.id }
        items.insert(item, at: 0)
        sortAndSave()
    }

    func update(_ item: SavedItem) {
        var updated = item
        updated.updatedAt = Date()
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index] = updated
        } else {
            items.insert(updated, at: 0)
        }
        sortAndSave()
    }

    func delete(ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        items.removeAll { ids.contains($0.id) }
        save()
    }

    func delete(at offsets: IndexSet, in filtered: [SavedItem]) {
        var ids = Set<UUID>()
        for index in offsets where index >= 0 && index < filtered.count {
            ids.insert(filtered[index].id)
        }
        delete(ids: ids)
    }

    func item(id: UUID) -> SavedItem? {
        items.first { $0.id == id }
    }

    // MARK: Export and import

    /// Pretty JSON with ISO 8601 dates, the same format the import accepts.
    func exportText(for item: SavedItem) -> String {
        guard let data = try? SavedStore.makeEncoder().encode(item) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }

    /// Writes the item to a temporary .json file named after it and returns the file.
    func exportFileURL(for item: SavedItem) throws -> URL {
        let data = try SavedStore.makeEncoder().encode(item)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(SavedStore.fileName(for: item))
            .appendingPathExtension("json")
        try data.write(to: url, options: .atomic)
        return url
    }

    /// Reads one item or an array of items from a .json file, gives each a new identity and keeps them. Returns how many were added.
    func importItems(from url: URL) throws -> Int {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw NFCEditorError.failed("The file could not be read.")
        }

        let decoder = SavedStore.makeDecoder()
        var imported: [SavedItem]
        if let list = try? decoder.decode([SavedItem].self, from: data) {
            imported = list
        } else if let single = try? decoder.decode(SavedItem.self, from: data) {
            imported = [single]
        } else {
            throw NFCEditorError.invalidInput("This file is not an NFC Editor export.")
        }
        guard !imported.isEmpty else { return 0 }

        let now = Date()
        for index in imported.indices {
            imported[index].id = UUID()
            imported[index].updatedAt = now
            imported[index].drafts = imported[index].drafts.map { draft in
                var fresh = draft
                fresh.id = UUID()
                return fresh
            }
        }
        items.append(contentsOf: imported)
        sortAndSave()
        return imported.count
    }

    /// Writes the saved memory dump as a flat .bin file and returns it. Throws when the item has no dump.
    func exportDumpFileURL(for item: SavedItem) throws -> URL {
        guard let dump = item.tagInfo?.dump, !dump.pages.isEmpty else {
            throw NFCEditorError.failed("This item has no memory dump.")
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(SavedStore.fileName(for: item))
            .appendingPathExtension("bin")
        try dump.flatBytes.write(to: url, options: .atomic)
        return url
    }

    // MARK: Persistence

    private func sortAndSave() {
        items.sort { $0.updatedAt > $1.updatedAt }
        save()
    }

    private func save() {
        do {
            let data = try SavedStore.makeEncoder().encode(items)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // There is no screen to report this from; the next change tries again.
        }
    }

    /// A missing or corrupt file simply means an empty list.
    private static func load(from url: URL) -> [SavedItem] {
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let decoded = try? makeDecoder().decode([SavedItem].self, from: data) else {
            return []
        }
        return decoded.sorted { $0.updatedAt > $1.updatedAt }
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    /// A file system safe version of the item name, falling back to the kind.
    private static func fileName(for item: SavedItem) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " -_"))
        let cleaned = item.name
            .components(separatedBy: allowed.inverted)
            .joined()
            .trimmingCharacters(in: .whitespaces)
        if cleaned.isEmpty {
            return item.kind == .tag ? "Tag" : "Profile"
        }
        return String(cleaned.prefix(60))
    }
}
