import Foundation
import Observation

enum AppTab: String, Hashable {
    case read, write, tools, saved
}

@MainActor @Observable
final class AppState {
    /// The one instance the app and the App Intents share, so a Shortcut run shows up in the Read tab
    /// and writes the same saved profiles the user sees.
    static let shared = AppState()

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

    func clearScanHistory() {
        scanHistory = []
        lastScan = nil
    }

    /// The scan log as CSV, newest first: serial number, chip, record count and scan time (ISO 8601).
    /// Lines end in CRLF as RFC 4180 asks, which spreadsheet apps on every platform accept.
    func exportScanLogCSV() -> String {
        var lines = ["Serial,Chip,Records,Scanned at"]
        for info in scanHistory {
            let fields = [
                info.serialLine,
                info.chipLine,
                String(info.records.count),
                info.scannedAt.ISO8601Format(),
            ]
            lines.append(fields.map(AppState.csvField).joined(separator: ","))
        }
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    nonisolated private static func csvField(_ value: String) -> String {
        let needsQuotes = value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r")
        guard needsQuotes else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
