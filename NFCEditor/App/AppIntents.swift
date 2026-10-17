import Foundation
import AppIntents
import UIKit

// Core NFC only works with the app in front, so both intents open the app and run the system
// sheet there. They share AppState.shared with the screens, so a run from Shortcuts shows up in
// the Read tab and writes the profiles the Saved tab shows.

/// Scans one tag and returns its records to Shortcuts as text, one line per record.
struct ReadTagIntent: AppIntent {
    static var title: LocalizedStringResource = "Read NFC tag"
    static var description = IntentDescription("Opens NFC Editor, scans a tag and returns its records as text, one line per record. A tag with no records gives empty text.")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let text: String
        do {
            text = try await IntentRunner.readTag()
        } catch {
            throw IntentFailure(error)
        }
        return .result(value: text)
    }
}

/// A saved profile as Shortcuts and Siri see it.
struct ProfileEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Profile"
    static var defaultQuery = ProfileQuery()

    var id: UUID
    var name: String
    var detail: String

    init(item: SavedItem) {
        id = item.id
        name = item.name
        detail = item.subtitle
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(detail)")
    }

    @MainActor
    static func allProfiles() -> [ProfileEntity] {
        AppState.shared.store.items
            .filter { $0.kind == .profile }
            .map { ProfileEntity(item: $0) }
    }
}

/// Looks profiles up in the saved items, newest first, the same order as the Saved tab.
struct ProfileQuery: EntityQuery {
    func entities(for identifiers: [ProfileEntity.ID]) async throws -> [ProfileEntity] {
        await MainActor.run {
            let profiles = ProfileEntity.allProfiles()
            return identifiers.compactMap { id in
                profiles.first { $0.id == id }
            }
        }
    }

    func suggestedEntities() async throws -> [ProfileEntity] {
        await MainActor.run {
            ProfileEntity.allProfiles()
        }
    }
}

/// Writes the records of a saved profile to the next tag, then reads them back to check.
struct WriteProfileIntent: AppIntent {
    static var title: LocalizedStringResource = "Write profile to tag"
    static var description = IntentDescription("Opens NFC Editor and writes a saved profile to the next tag you hold, then reads the tag back to check it.")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Profile")
    var profile: ProfileEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Write \(\.$profile) to a tag")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let text: String
        do {
            text = try await IntentRunner.writeProfile(id: profile.id)
        } catch {
            throw IntentFailure(error)
        }
        return .result(value: text)
    }
}

/// The phrases Siri and Spotlight offer without any setup.
struct NFCEditorShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ReadTagIntent(),
            phrases: [
                "Read an NFC tag with \(.applicationName)",
                "Scan a tag with \(.applicationName)",
            ],
            shortTitle: "Read NFC tag",
            systemImageName: "wave.3.right"
        )
        AppShortcut(
            intent: WriteProfileIntent(),
            phrases: [
                "Write a profile with \(.applicationName)",
                "Write a tag with \(.applicationName)",
            ],
            shortTitle: "Write profile to tag",
            systemImageName: "square.and.pencil"
        )
    }
}

/// Shortcuts shows the text of an error that conforms to CustomLocalizedStringResourceConvertible,
/// so every failure is rethrown in that shape, with the same message the app's own alerts use.
private struct IntentFailure: Error, CustomLocalizedStringResourceConvertible {
    let message: String

    init(_ error: Error) {
        message = NFCEditorError.map(error).errorDescription ?? "The action failed."
    }

    var localizedStringResource: LocalizedStringResource {
        "\(message)"
    }
}

/// The work behind the intents, kept apart from the App Intents types so it reads like the screens' own code.
@MainActor
private enum IntentRunner {
    static func readTag() async throws -> String {
        let app = AppState.shared
        await waitUntilActive()
        let info = try await app.nfc.run(
            alertMessage: "Hold your iPhone near the tag.",
            successMessage: "Tag read."
        ) { session, tag in
            try await TagOperations.readTag(session, tag, includeDump: false)
        }
        app.recordScan(info)
        app.selectedTab = .read
        Haptics.success()
        return info.records.map { line(for: $0) }.joined(separator: "\n")
    }

    static func writeProfile(id: UUID) async throws -> String {
        let app = AppState.shared
        guard let item = app.store.item(id: id), item.kind == .profile else {
            throw NFCEditorError.invalidInput("This profile no longer exists. Pick another one.")
        }
        let records = try item.drafts.flatMap { try RecordDraft.buildAll($0) }
        guard !records.isEmpty else {
            throw NFCEditorError.invalidInput("\(item.name) has no records to write.")
        }
        var options = WriteOptions()
        options.verifyAfterWrite = true
        options.eraseFirst = false
        options.lockAfterWrite = false
        let writeOptions = options
        await waitUntilActive()
        let result = try await app.nfc.run(
            alertMessage: "Hold your iPhone near the tag.",
            successMessage: "Tag written."
        ) { session, tag in
            try await TagOperations.writeRecords(session, tag, records: records, options: writeOptions)
        }
        Haptics.success()
        var parts = ["Wrote \(item.name) to the tag, \(ByteFormatter.bytes(result.bytesWritten))."]
        if result.verified == true {
            parts.append("Verified.")
        }
        return parts.joined(separator: " ")
    }

    /// The record's main value on one line, so a Shortcut can split the result by lines.
    private static func line(for record: NDEFRecord) -> String {
        let summary = RecordParsers.parse(record)
        let value = summary.detail.isEmpty ? summary.title : summary.detail
        return value
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// The intent can start while the app is still coming to the front, and Core NFC refuses to
    /// begin a session from the background, so give the scene a moment to become active.
    private static func waitUntilActive() async {
        for _ in 0..<30 {
            if UIApplication.shared.applicationState == .active {
                return
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
    }
}
