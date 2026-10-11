import Foundation
import Observation

@MainActor @Observable
final class AppSettings {
    @ObservationIgnored private let defaults = UserDefaults.standard

    var hapticsEnabled: Bool {
        didSet { defaults.set(hapticsEnabled, forKey: Keys.hapticsEnabled) }
    }

    var verifyAfterWrite: Bool {
        didSet { defaults.set(verifyAfterWrite, forKey: Keys.verifyAfterWrite) }
    }

    var defaultLanguage: String {
        didSet { defaults.set(defaultLanguage, forKey: Keys.defaultLanguage) }
    }

    var readFullMemoryOnScan: Bool {
        didSet { defaults.set(readFullMemoryOnScan, forKey: Keys.readFullMemoryOnScan) }
    }

    var keepScreenAwake: Bool {
        didSet { defaults.set(keepScreenAwake, forKey: Keys.keepScreenAwake) }
    }

    /// Advanced commands history, newest first, at most `historyLimit` hex strings.
    var commandHistory: [String] {
        didSet { defaults.set(commandHistory, forKey: Keys.commandHistory) }
    }

    init() {
        let stored = UserDefaults.standard
        hapticsEnabled = stored.object(forKey: Keys.hapticsEnabled) as? Bool ?? true
        verifyAfterWrite = stored.object(forKey: Keys.verifyAfterWrite) as? Bool ?? true
        let language = stored.string(forKey: Keys.defaultLanguage) ?? "en"
        defaultLanguage = language.isEmpty ? "en" : language
        readFullMemoryOnScan = stored.object(forKey: Keys.readFullMemoryOnScan) as? Bool ?? true
        keepScreenAwake = stored.bool(forKey: Keys.keepScreenAwake)
        let history = stored.stringArray(forKey: Keys.commandHistory) ?? []
        commandHistory = Array(history.prefix(AppSettings.historyLimit))
    }

    func addCommandToHistory(_ hex: String) {
        let trimmed = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var history = commandHistory.filter { $0 != trimmed }
        history.insert(trimmed, at: 0)
        if history.count > AppSettings.historyLimit {
            history.removeLast(history.count - AppSettings.historyLimit)
        }
        commandHistory = history
    }

    func clearCommandHistory() {
        commandHistory = []
    }

    private static let historyLimit = 50

    private enum Keys {
        static let hapticsEnabled = "settings.hapticsEnabled"
        static let verifyAfterWrite = "settings.verifyAfterWrite"
        static let defaultLanguage = "settings.defaultLanguage"
        static let readFullMemoryOnScan = "settings.readFullMemoryOnScan"
        static let keepScreenAwake = "settings.keepScreenAwake"
        static let commandHistory = "settings.commandHistory"
    }
}
