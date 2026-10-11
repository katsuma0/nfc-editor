import Foundation
import Observation

enum AppTab: String, Hashable {
    case read, write, tools, saved
}

@MainActor @Observable
final class AppState {
    let nfc = NFCSessionManager.shared
    let settings = AppSettings()
    let store = SavedStore()
    let writeQueue = WriteQueue()

    var selectedTab: AppTab = .read

    /// Most recent read result; ReadView shows it.
    var lastScan: TagInfo?

    /// Newest first, at most `historyLimit` entries, in memory only.
    var scanHistory: [TagInfo] = []

    private static let historyLimit = 20

    init() {}

    /// Puts records into the Write tab (replacing the queue) and switches to it.
    func sendToWrite(records: [NDEFRecord]) {
        writeQueue.replace(with: records)
        selectedTab = .write
    }

    func sendToWrite(drafts: [RecordDraft]) {
        writeQueue.replace(with: drafts)
        selectedTab = .write
    }

    func recordScan(_ info: TagInfo) {
        lastScan = info
        scanHistory.removeAll { $0.id == info.id }
        scanHistory.insert(info, at: 0)
        if scanHistory.count > AppState.historyLimit {
            scanHistory.removeLast(scanHistory.count - AppState.historyLimit)
        }
    }
}
