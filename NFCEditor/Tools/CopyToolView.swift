import Foundation
import SwiftUI
import CoreNFC

/// Reads one tag, then writes what it holds to one or more destination tags.
@MainActor
struct CopyToolView: View {
    @Environment(AppState.self) private var app
    @State private var source: TagInfo?
    @State private var cloneRawMemory = false
    @State private var lastWrite: String?
    @State private var alert: AlertItem?

    var body: some View {
        Form {
            sourceSection
            if let source {
                destinationSections(for: source)
            }
            if let lastWrite {
                Section {
                    Label {
                        Text(lastWrite)
                    } icon: {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                } header: {
                    Text("Last write")
                }
            }
        }
        .navigationTitle("Copy tag")
        .navigationBarTitleDisplayMode(.inline)
        .alertItem($alert)
    }

    // MARK: Sections

    @ViewBuilder
    private var sourceSection: some View {
        if let source {
            Section {
                LabeledContent("Chip", value: source.chipLine)
                LabeledContent("Serial number") {
                    Text(source.serialLine)
                        .font(.body.monospaced())
                }
                LabeledContent("Records", value: CopyToolView.recordsLabel(source.records.count))
                if let used = source.ndefUsedBytes {
                    LabeledContent("Size", value: ByteFormatter.bytes(used))
                }
                if let dump = source.dump {
                    LabeledContent("Memory read", value: CopyToolView.pagesLabel(dump.pages.count))
                }
                Button("Reset", role: .destructive) {
                    reset()
                }
            } header: {
                Text("Source tag")
            } footer: {
                Text("Scanned at \(source.scannedAt.formatted(date: .omitted, time: .shortened)). Reset to copy a different tag.")
            }
        } else {
            Section {
                ScanButton("Scan source tag") {
                    readSource()
                }
            } header: {
                Text("Source tag")
            } footer: {
                Text("Scan the tag you want to copy. Its records and full memory are read into the app, so you can write them to as many tags as you like.")
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
        }
    }

    @ViewBuilder
    private func destinationSections(for source: TagInfo) -> some View {
        Section {
            LabeledContent("Writes", value: payloadDescription(for: source))
            if canCloneRaw(source) {
                Toggle("Clone raw memory instead of records", isOn: $cloneRawMemory)
            }
        } header: {
            Text("Destination tag")
        } footer: {
            Text(destinationFooter(for: source))
        }

        Section {
            ScanButton("Write to destination tag", systemImage: "square.and.pencil") {
                writeDestination(source)
            }
        } footer: {
            Text("Keep the source tag away from your iPhone so it is not overwritten by mistake.")
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets())
    }

    // MARK: Derived text

    private func canCloneRaw(_ source: TagInfo) -> Bool {
        source.dump != nil && source.chip.supportsRawPages
    }

    private func usesRawClone(_ source: TagInfo) -> Bool {
        cloneRawMemory && canCloneRaw(source)
    }

    private func payloadDescription(for source: TagInfo) -> String {
        if usesRawClone(source), let dump = source.dump {
            return "Raw memory, \(ByteFormatter.bytes(dump.readableByteCount))"
        }
        var text = CopyToolView.recordsLabel(source.records.count)
        if let used = source.ndefUsedBytes {
            text += ", \(ByteFormatter.bytes(used))"
        }
        return text
    }

    private func destinationFooter(for source: TagInfo) -> String {
        if usesRawClone(source) {
            return "Every readable user page is written byte for byte, so the destination should be the same chip type as the source. The serial number, lock bytes and configuration pages are skipped."
        }
        return "The records are written as a fresh NDEF message and verified. The destination can be any writable NDEF tag with enough space."
    }

    private static func recordsLabel(_ count: Int) -> String {
        switch count {
        case 0: return "No records"
        case 1: return "1 record"
        default: return "\(count) records"
        }
    }

    private static func pagesLabel(_ count: Int) -> String {
        count == 1 ? "1 page" : "\(count) pages"
    }

    private static func successMessage(for result: WriteResult) -> String {
        var parts = ["Wrote \(ByteFormatter.bytes(result.bytesWritten))."]
        if let capacity = result.capacity {
            let free = max(capacity - result.bytesWritten, 0)
            parts.append("\(ByteFormatter.bytes(free)) free.")
        }
        if result.verified == true {
            parts.append("Verified.")
        }
        return parts.joined(separator: " ")
    }

    // MARK: Actions

    private func reset() {
        source = nil
        cloneRawMemory = false
        lastWrite = nil
        Haptics.tap()
    }

    private func readSource() {
        Task { @MainActor in
            do {
                let info = try await app.nfc.run(
                    alertMessage: "Hold your iPhone near the source tag.",
                    successMessage: "Source tag read."
                ) { session, tag in
                    try await TagOperations.readTag(session, tag, includeDump: true)
                }
                source = info
                cloneRawMemory = false
                lastWrite = nil
                Haptics.success()
            } catch {
                if NFCEditorError.map(error).isCancellation { return }
                Haptics.error()
                alert = AlertItem(error: error)
            }
        }
    }

    private func writeDestination(_ source: TagInfo) {
        if usesRawClone(source), let dump = source.dump {
            writeRaw(dump)
            return
        }
        guard !source.records.isEmpty else {
            var message = "The source tag has no records to copy."
            if canCloneRaw(source) {
                message += " Turn on raw memory cloning to copy its memory instead."
            }
            alert = AlertItem(error: NFCEditorError.invalidInput(message))
            return
        }
        writeRecords(source.records)
    }

    private func writeRecords(_ records: [NDEFRecord]) {
        // Copying always verifies and never locks, whatever the Write tab is set to.
        let options = WriteOptions(lockAfterWrite: false, verifyAfterWrite: true, eraseFirst: false)
        Task { @MainActor in
            do {
                let result = try await app.nfc.run(
                    alertMessage: "Hold your iPhone near the destination tag.",
                    successMessage: "Tag written."
                ) { session, tag in
                    try await TagOperations.writeRecords(session, tag, records: records, options: options)
                }
                Haptics.success()
                let message = CopyToolView.successMessage(for: result)
                lastWrite = message
                alert = AlertItem.success(message)
            } catch {
                if NFCEditorError.map(error).isCancellation { return }
                Haptics.error()
                alert = AlertItem(error: error)
            }
        }
    }

    private func writeRaw(_ dump: MemoryDump) {
        Task { @MainActor in
            do {
                let pages = try await app.nfc.run(
                    alertMessage: "Hold your iPhone near the destination tag.",
                    successMessage: "Memory written."
                ) { session, tag in
                    try await TagOperations.writeDump(session, tag, dump: dump, range: nil, password: nil)
                }
                Haptics.success()
                let message = "Wrote \(CopyToolView.pagesLabel(pages)) of memory."
                lastWrite = message
                alert = AlertItem.success(message)
            } catch {
                if NFCEditorError.map(error).isCancellation { return }
                Haptics.error()
                alert = AlertItem(error: error)
            }
        }
    }
}
