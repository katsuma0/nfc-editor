import Foundation
import SwiftUI
import CoreNFC

/// Write tab: build a list of records, then write them all to a tag in one go.
@MainActor
struct WriteView: View {
    @Environment(AppState.self) private var app
    @State private var sheet: WriteSheet?
    @State private var pendingKind: RecordKind?
    @State private var alert: AlertItem?
    @State private var showingSavePrompt = false
    @State private var profileName = ""
    @State private var showingClearConfirmation = false
    @State private var showingLockConfirmation = false
    @State private var writeSeveral = false

    var body: some View {
        NavigationStack {
            List {
                recordsSection
                optionsSection
                writeSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Write")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    EditButton()
                        .disabled(app.writeQueue.drafts.isEmpty)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            profileName = defaultProfileName
                            showingSavePrompt = true
                        } label: {
                            Label("Save as profile", systemImage: "folder.badge.plus")
                        }
                        .disabled(app.writeQueue.drafts.isEmpty)
                        Button(role: .destructive) {
                            showingClearConfirmation = true
                        } label: {
                            Label("Clear all", systemImage: "trash")
                        }
                        .disabled(app.writeQueue.drafts.isEmpty)
                    } label: {
                        Label("More", systemImage: "ellipsis.circle")
                    }
                }
            }
            .sheet(item: $sheet, onDismiss: { openEditorForPendingKind() }) { item in
                switch item {
                case .add:
                    AddRecordView { kind in
                        pendingKind = kind
                    }
                case .edit(let draft):
                    RecordEditorView(draft: draft) { updated in
                        save(updated)
                    }
                }
            }
            .alert("Save as profile", isPresented: $showingSavePrompt) {
                TextField("Name", text: $profileName)
                Button("Save") {
                    saveProfile()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The records are kept in the Saved tab so you can write them again later.")
            }
            .confirmationDialog(
                "Remove all records from the queue?",
                isPresented: $showingClearConfirmation,
                titleVisibility: .visible
            ) {
                Button("Clear all", role: .destructive) {
                    app.writeQueue.clear()
                }
                Button("Cancel", role: .cancel) {}
            }
            .alertItem($alert)
        }
    }

    // MARK: Sections

    private var recordsSection: some View {
        Section {
            ForEach(app.writeQueue.drafts) { draft in
                Button {
                    sheet = .edit(draft)
                } label: {
                    DraftRow(draft: draft)
                }
            }
            .onDelete { offsets in
                app.writeQueue.remove(at: offsets)
            }
            .onMove { from, to in
                app.writeQueue.move(from: from, to: to)
            }

            Button {
                sheet = .add
            } label: {
                Label("Add a record", systemImage: "plus.circle.fill")
            }
            .deleteDisabled(true)
            .moveDisabled(true)
        } header: {
            Text("Records")
        } footer: {
            Text(recordsFooter)
        }
    }

    private var optionsSection: some View {
        Section {
            NavigationLink {
                WriteOptionsView()
            } label: {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Write options")
                        Text(optionsSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "slider.horizontal.3")
                        .foregroundStyle(Color.accentColor)
                }
            }
            Toggle(isOn: $writeSeveral) {
                Label {
                    Text("Write to several tags")
                } icon: {
                    Image(systemName: "square.stack.3d.up")
                        .foregroundStyle(Color.accentColor)
                }
            }
        } header: {
            Text("Options")
        } footer: {
            if writeSeveral {
                Text("The NFC sheet stays open after each tag. Hold the tags one after another, then tap Cancel when you are done. iOS closes the sheet after 60 seconds.")
            }
        }
    }

    private var writeSection: some View {
        Section {
            VStack(spacing: 12) {
                ScanButton(writeSeveral ? "Write to tags" : "Write to tag") {
                    startWrite()
                }
                .disabled(app.writeQueue.drafts.isEmpty)
                .confirmationDialog(
                    "Lock the tag after writing?",
                    isPresented: $showingLockConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("Write and lock", role: .destructive) {
                        write()
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text(writeSeveral ? "Every tag you write in this session is locked. A locked tag can never be written or erased again." : "A locked tag can never be written or erased again.")
                }
                if app.writeQueue.options.lockAfterWrite {
                    Label(writeSeveral ? "Every tag will be locked permanently." : "The tag will be locked permanently.", systemImage: "lock.fill")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
            .padding(.vertical, 8)
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets())
    }

    // MARK: Derived text

    private var recordsFooter: String {
        let count = app.writeQueue.drafts.count
        if count == 0 {
            return "Add records to write them to a tag. The list is kept until you clear it."
        }
        let records = count == 1 ? "1 record" : "\(count) records"
        return "\(records), \(ByteFormatter.bytes(app.writeQueue.totalBytes))"
    }

    private var optionsSummary: String {
        let options = app.writeQueue.options
        var parts: [String] = []
        if options.verifyAfterWrite { parts.append("Verify after write") }
        if options.eraseFirst { parts.append("Erase first") }
        if options.lockAfterWrite { parts.append("Lock after write") }
        return parts.isEmpty ? "No extra steps" : parts.joined(separator: ", ")
    }

    private var defaultProfileName: String {
        app.writeQueue.drafts.first?.summary ?? "New profile"
    }

    // MARK: Editing

    private func newDraft(for kind: RecordKind) -> RecordDraft {
        var draft = RecordDraft(kind: kind)
        if kind == .text || kind == .smartPoster {
            let language = app.settings.defaultLanguage
            if !language.isEmpty {
                draft[DraftKey.language] = language
            }
        }
        return draft
    }

    /// Runs when the add sheet closes. Presenting the editor from here avoids two sheets fighting over the screen.
    private func openEditorForPendingKind() {
        guard let kind = pendingKind else { return }
        pendingKind = nil
        let draft = newDraft(for: kind)
        if kind == .empty {
            app.writeQueue.add(draft)
            Haptics.tap()
            return
        }
        sheet = .edit(draft)
    }

    private func save(_ draft: RecordDraft) {
        if let index = app.writeQueue.drafts.firstIndex(where: { $0.id == draft.id }) {
            app.writeQueue.drafts[index] = draft
        } else {
            app.writeQueue.add(draft)
        }
        Haptics.tap()
    }

    // MARK: Writing

    private func startWrite() {
        if app.writeQueue.options.lockAfterWrite {
            showingLockConfirmation = true
        } else {
            write()
        }
    }

    private func write() {
        let records: [NDEFRecord]
        do {
            records = try app.writeQueue.builtRecords()
        } catch {
            alert = AlertItem(error: error)
            return
        }
        let options = app.writeQueue.options
        if writeSeveral {
            writeBatch(records: records, options: options)
            return
        }
        Task { @MainActor in
            do {
                let result = try await app.nfc.run(
                    alertMessage: "Hold your iPhone near the tag.",
                    successMessage: "Tag written."
                ) { session, tag in
                    try await TagOperations.writeRecords(session, tag, records: records, options: options)
                }
                Haptics.success()
                if options.lockAfterWrite {
                    // Locking is a one-time decision; the next write must not inherit it by accident.
                    app.writeQueue.options.lockAfterWrite = false
                }
                alert = AlertItem.success(WriteView.successMessage(for: result))
            } catch {
                if NFCEditorError.map(error).isCancellation { return }
                Haptics.error()
                alert = AlertItem(error: error)
            }
        }
    }

    /// One session for many tags: after each tag the sheet shows the running count and waits for the next one.
    private func writeBatch(records: [NDEFRecord], options: WriteOptions) {
        Task { @MainActor in
            do {
                let count = try await app.nfc.runBatch(alertMessage: "Hold your iPhone near the first tag.") { session, tag, handled in
                    _ = try await TagOperations.writeRecords(session, tag, records: records, options: options)
                    return "\(WriteView.writtenToTags(handled + 1)) Hold the next one."
                }
                if options.lockAfterWrite {
                    app.writeQueue.options.lockAfterWrite = false
                }
                if count > 0 {
                    Haptics.success()
                }
                alert = AlertItem.success(WriteView.writtenToTags(count))
            } catch {
                if NFCEditorError.map(error).isCancellation { return }
                Haptics.error()
                alert = AlertItem(error: error)
            }
        }
    }

    /// Nonisolated because the batch callback runs off the main actor.
    nonisolated private static func writtenToTags(_ count: Int) -> String {
        count == 1 ? "Written to 1 tag." : "Written to \(count) tags."
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
        if result.locked {
            parts.append("The tag is now locked.")
        }
        return parts.joined(separator: " ")
    }

    private func saveProfile() {
        let trimmed = profileName.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmed.isEmpty ? defaultProfileName : trimmed
        app.store.add(SavedItem.profile(name: name, drafts: app.writeQueue.drafts))
        Haptics.success()
        // The name prompt is still animating away, so the confirmation needs a moment before it can show.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            alert = AlertItem.success("Saved as \(name).")
        }
    }
}

// MARK: - Sheets

private enum WriteSheet: Identifiable {
    case add
    case edit(RecordDraft)

    var id: String {
        switch self {
        case .add:
            return "add"
        case .edit(let draft):
            return draft.id.uuidString
        }
    }
}

// MARK: - Rows

/// One queued draft: icon, kind, summary and its size, or a warning when it cannot be built yet.
private struct DraftRow: View {
    let draft: RecordDraft

    var body: some View {
        HStack(spacing: 12) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(draft.kind.displayName)
                        .font(.caption.smallCaps().weight(.medium))
                        .foregroundStyle(.secondary)
                    Text(draft.summary)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                }
            } icon: {
                Image(systemName: draft.kind.systemImage)
                    .foregroundStyle(Color.accentColor)
            }
            Spacer(minLength: 8)
            if draft.validate() != nil {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .accessibilityLabel("Needs attention")
            } else {
                Text(ByteFormatter.bytes(draft.encodedSize))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
