import Foundation
import SwiftUI
import Observation

/// The records queued in the Write tab. Drafts survive a relaunch so a half-built tag is never lost.
@MainActor @Observable
final class WriteQueue {
    var drafts: [RecordDraft] {
        didSet { persist() }
    }

    /// Not persisted on purpose: locking must be chosen again after every launch.
    var options: WriteOptions

    @ObservationIgnored private let defaults = UserDefaults.standard

    private static let draftsKey = "writeQueue.drafts"
    /// Mirrors AppSettings so the Settings toggle acts as the default for a fresh queue.
    private static let verifyDefaultKey = "settings.verifyAfterWrite"

    init() {
        let stored = UserDefaults.standard
        var initialOptions = WriteOptions()
        if let verify = stored.object(forKey: WriteQueue.verifyDefaultKey) as? Bool {
            initialOptions.verifyAfterWrite = verify
        }
        options = initialOptions
        drafts = WriteQueue.loadDrafts(from: stored)
    }

    /// Size of the whole NDEF message when every draft is valid, otherwise the sum of the drafts that can be built.
    var totalBytes: Int {
        if drafts.isEmpty {
            return 0
        }
        if let records = try? builtRecords() {
            return NDEFMessageCodec.byteCount(records)
        }
        return drafts.reduce(0) { $0 + $1.encodedSize }
    }

    /// Builds every draft in order, a draft with handover on giving two records. Throws the first draft's NFCEditorError.invalidInput.
    func builtRecords() throws -> [NDEFRecord] {
        try drafts.flatMap { try RecordDraft.buildAll($0) }
    }

    func replace(with drafts: [RecordDraft]) {
        self.drafts = drafts
    }

    func replace(with records: [NDEFRecord]) {
        drafts = RecordDraft.from(records: records)
    }

    func add(_ draft: RecordDraft) {
        drafts.append(draft)
    }

    func remove(at offsets: IndexSet) {
        drafts.remove(atOffsets: offsets)
    }

    func move(from: IndexSet, to: Int) {
        drafts.move(fromOffsets: from, toOffset: to)
    }

    func clear() {
        drafts.removeAll()
    }

    // MARK: Persistence

    private func persist() {
        if drafts.isEmpty {
            defaults.removeObject(forKey: WriteQueue.draftsKey)
            return
        }
        guard let data = try? JSONEncoder().encode(drafts) else { return }
        defaults.set(data, forKey: WriteQueue.draftsKey)
    }

    private static func loadDrafts(from defaults: UserDefaults) -> [RecordDraft] {
        guard let data = defaults.data(forKey: draftsKey) else { return [] }
        return (try? JSONDecoder().decode([RecordDraft].self, from: data)) ?? []
    }
}
