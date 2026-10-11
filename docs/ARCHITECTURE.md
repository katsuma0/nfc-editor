# Architecture

Four layers, each a folder, each only talking downward.

NDEF (Foundation only). `NDEFRecord` is our own Codable record. `NDEFMessageCodec` turns an array of them into bytes and back. `RecordBuilders` makes records from typed inputs (text, URL, vCard, Wi-Fi credential, Bluetooth OOB, and so on). `RecordParsers.parse` turns any record into a `RecordSummary` the UI can show, with actions like open, copy, join Wi-Fi. `RecordDraft` is the editable form model: a kind plus a string dictionary keyed by `DraftKey`, with `build()` to produce a record and `from(record:)` to go back. Nothing in here imports CoreNFC, so it can move to a package with tests later.

NFC (Core NFC). `NFCSessionManager.run` is the only way the app touches a tag. It opens an `NFCTagReaderSession`, waits for exactly one tag, connects, runs the closure you gave it, and closes the session with a success or error message. Every screen calls it the same way:

```swift
let info = try await app.nfc.run(alertMessage: "Hold your iPhone near the tag.") { session, tag in
    try await TagOperations.readTag(session, tag, includeDump: true)
}
```

`TagOperations` holds every high level operation (read, write, erase, lock, format, memory, passwords, counters, signature, raw commands) and switches on the `NFCTag` enum to pick a path. `MiFareCommands`, `ISO15693Commands`, `DESFireCommands` and `FeliCaCommands` wrap the raw transceive calls. `ChipSpec` and `ChipIdentifier` turn a GET_VERSION response or an ISO 15693 system info block into a chip name, page count, user memory range and config page numbers, which is what every write-side tool needs to avoid touching OTP or lock pages. `TagInfo` is the Codable result of a scan and is what gets saved.

App state. `AppState` lives in the SwiftUI environment and owns the session manager, settings, the saved-item store and the write queue. Tabs talk to each other through it: Read can push records into Write, Saved can push a profile into Write, and both switch the selected tab.

UI. One folder per tab plus Settings and Shared. Every tool screen is the same shape: a sentence that says what the tool does, the inputs, a `ScanButton`, and an alert for the result. A user cancelling the system NFC sheet is never shown as an error.

Persistence is two JSON files in the app's Documents folder (saved items) and UserDefaults (settings, write queue, command history). No database.

Things iOS does not allow and the app therefore does not pretend to do: MIFARE Classic data, tag emulation, background writing.
