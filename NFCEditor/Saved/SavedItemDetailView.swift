import Foundation
import SwiftUI
import CoreNFC

/// One saved tag or profile: rename it, review or edit its records, and write it to a tag.
@MainActor
struct SavedItemDetailView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var alert: AlertItem?
    @State private var sheet: SavedDetailSheet?
    @State private var pendingKind: RecordKind?
    @State private var showingDeleteConfirmation = false
    @State private var exportURL: URL?
    @State private var dumpURL: URL?

    private let itemID: UUID

    init(itemID: UUID) {
        self.itemID = itemID
    }

    var body: some View {
        Group {
            if let item = app.store.item(id: itemID) {
                content(item)
            } else {
                ContentUnavailableView(
                    "Item not found",
                    systemImage: "folder.badge.questionmark",
                    description: Text("This item is no longer in the Saved tab.")
                )
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .alertItem($alert)
    }

    private func content(_ item: SavedItem) -> some View {
        List {
            nameSection
            recordsSection(item)
            if let info = item.tagInfo {
                tagSection(info)
            }
            writeSection(item)
            manageSection(item)
        }
        .listStyle(.insetGrouped)
        .navigationTitle(title(for: item))
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if item.kind == .profile {
                    EditButton()
                        .disabled(item.drafts.isEmpty)
                }
                menu(item)
            }
        }
        .sheet(item: $sheet, onDismiss: { openEditorForPendingKind() }) { current in
            switch current {
            case .add:
                AddRecordView { kind in
                    pendingKind = kind
                }
            case .edit(let draft):
                RecordEditorView(draft: draft) { updated in
                    saveDraft(updated)
                }
            }
        }
        .confirmationDialog(
            deleteTitle(for: item),
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                deleteItem()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone.")
        }
        .onAppear {
            name = item.name
            refreshExports(item)
        }
        .onChange(of: item) { _, newValue in
            refreshExports(newValue)
        }
    }

    // MARK: Sections

    private var nameSection: some View {
        Section("Name") {
            TextField("Name", text: $name)
                .submitLabel(.done)
                .onChange(of: name) { _, newValue in
                    rename(newValue)
                }
        }
    }

    private func recordsSection(_ item: SavedItem) -> some View {
        Section {
            switch item.kind {
            case .tag:
                if item.records.isEmpty {
                    Label("No records", systemImage: "tray")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(item.records) { record in
                        NavigationLink {
                            RecordDetailView(record: record)
                        } label: {
                            RecordRowView(record: record)
                        }
                    }
                }
            case .profile:
                ForEach(item.drafts) { draft in
                    Button {
                        sheet = .edit(draft)
                    } label: {
                        SavedDraftRow(draft: draft)
                    }
                }
                .onDelete { offsets in
                    modifyDrafts { $0.remove(atOffsets: offsets) }
                }
                .onMove { from, to in
                    modifyDrafts { $0.move(fromOffsets: from, toOffset: to) }
                }
                Button {
                    sheet = .add
                } label: {
                    Label("Add a record", systemImage: "plus.circle.fill")
                }
                .deleteDisabled(true)
                .moveDisabled(true)
            }
        } header: {
            Text("Records")
        } footer: {
            Text(recordsFooter(item))
        }
    }

    private func tagSection(_ info: TagInfo) -> some View {
        Section("Tag") {
            row("Tag type", value: info.chipLine, systemImage: "cpu")
            row("Technology", value: info.typeLine, systemImage: "antenna.radiowaves.left.and.right")
            LabeledContent {
                Text(info.serialLine)
                    .font(.body.monospaced())
            } label: {
                Label("Serial number", systemImage: "number")
            }
            if let memory = info.memoryLine {
                row("Memory", value: memory, systemImage: "memorychip")
            }
            if let size = info.sizeLine {
                row("Size", value: size, systemImage: "chart.pie")
            }
            row("Writable", value: info.writableLine, systemImage: "pencil")
            row("Scanned", value: info.scannedAt.formatted(date: .abbreviated, time: .shortened), systemImage: "clock")
            NavigationLink {
                TagDetailView(info: info)
            } label: {
                Label("All tag details", systemImage: "info.circle")
            }
        }
    }

    private func writeSection(_ item: SavedItem) -> some View {
        Section {
            VStack(spacing: 8) {
                ScanButton("Write to tag") {
                    write(item)
                }
                .disabled(!canWrite(item))
                Button {
                    app.sendToWrite(drafts: item.drafts)
                } label: {
                    Label("Open in Write tab", systemImage: "square.and.pencil")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(item.drafts.isEmpty)
            }
            .padding(.vertical, 8)
        } footer: {
            Text("Writing replaces everything on the tag with these records and verifies the result.")
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets())
    }

    private func manageSection(_ item: SavedItem) -> some View {
        Section {
            Button {
                duplicate(item)
            } label: {
                Label("Duplicate", systemImage: "plus.square.on.square")
            }
            Button(role: .destructive) {
                showingDeleteConfirmation = true
            } label: {
                Label(item.kind == .tag ? "Delete tag" : "Delete profile", systemImage: "trash")
            }
        }
    }

    private func menu(_ item: SavedItem) -> some View {
        Menu {
            if let url = exportURL {
                ShareLink(item: url) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
            }
            if let url = dumpURL {
                ShareLink(item: url) {
                    Label("Export memory dump", systemImage: "memorychip")
                }
            }
        } label: {
            Label("More", systemImage: "ellipsis.circle")
        }
        .disabled(exportURL == nil && dumpURL == nil)
    }

    // MARK: Rows

    private func row(_ title: String, value: String, systemImage: String) -> some View {
        LabeledContent {
            Text(value)
                .multilineTextAlignment(.trailing)
        } label: {
            Label(title, systemImage: systemImage)
        }
    }

    // MARK: Derived text

    private func title(for item: SavedItem) -> String {
        let trimmed = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return item.kind == .tag ? "Tag" : "Profile"
        }
        return trimmed
    }

    private func deleteTitle(for item: SavedItem) -> String {
        item.kind == .tag ? "Delete this tag?" : "Delete this profile?"
    }

    private func recordsFooter(_ item: SavedItem) -> String {
        switch item.kind {
        case .tag:
            if item.records.isEmpty {
                return "The tag had no records when it was saved."
            }
            return "Records as they were read from the tag. Use Open in Write tab to change them."
        case .profile:
            if item.drafts.isEmpty {
                return "Add records to this profile, then write them to any tag."
            }
            let invalid = item.drafts.filter { $0.validate() != nil }.count
            if invalid == 1 {
                return "1 record needs attention before the profile can be written."
            }
            if invalid > 1 {
                return "\(invalid) records need attention before the profile can be written."
            }
            return item.subtitle
        }
    }

    private func canWrite(_ item: SavedItem) -> Bool {
        switch item.kind {
        case .tag: return !item.records.isEmpty
        case .profile: return !item.drafts.isEmpty
        }
    }

    // MARK: Editing

    private func rename(_ newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, var item = app.store.item(id: itemID), item.name != trimmed else { return }
        item.name = trimmed
        app.store.update(item)
    }

    /// Runs when the add sheet closes. Presenting the editor from here avoids two sheets fighting over the screen.
    private func openEditorForPendingKind() {
        guard let kind = pendingKind else { return }
        pendingKind = nil
        var draft = RecordDraft(kind: kind)
        if kind == .text {
            let language = app.settings.defaultLanguage
            if !language.isEmpty {
                draft[DraftKey.language] = language
            }
        }
        if kind == .empty {
            modifyDrafts { $0.append(draft) }
            Haptics.tap()
            return
        }
        sheet = .edit(draft)
    }

    private func saveDraft(_ draft: RecordDraft) {
        modifyDrafts { drafts in
            if let index = drafts.firstIndex(where: { $0.id == draft.id }) {
                drafts[index] = draft
            } else {
                drafts.append(draft)
            }
        }
        Haptics.tap()
    }

    private func modifyDrafts(_ change: (inout [RecordDraft]) -> Void) {
        guard var item = app.store.item(id: itemID) else { return }
        change(&item.drafts)
        item.rebuildProfileRecords()
        app.store.update(item)
    }

    private func refreshExports(_ item: SavedItem) {
        exportURL = try? app.store.exportFileURL(for: item)
        if item.tagInfo?.dump != nil {
            dumpURL = try? app.store.exportDumpFileURL(for: item)
        } else {
            dumpURL = nil
        }
    }

    private func duplicate(_ item: SavedItem) {
        var copy = item
        copy.id = UUID()
        copy.name = title(for: item) + " copy"
        copy.createdAt = Date()
        copy.updatedAt = copy.createdAt
        copy.drafts = item.drafts.map { draft in
            var fresh = draft
            fresh.id = UUID()
            return fresh
        }
        app.store.add(copy)
        Haptics.success()
        alert = AlertItem.success("Duplicated as \(copy.name).")
    }

    private func deleteItem() {
        app.store.delete(ids: [itemID])
        Haptics.tap()
        dismiss()
    }

    // MARK: Writing

    private func write(_ item: SavedItem) {
        let records: [NDEFRecord]
        do {
            records = try recordsToWrite(item)
        } catch {
            alert = AlertItem(error: error)
            return
        }
        guard !records.isEmpty else {
            alert = AlertItem(error: NFCEditorError.invalidInput("Add a record first."))
            return
        }
        let options = WriteOptions(lockAfterWrite: false, verifyAfterWrite: true, eraseFirst: false)
        Task { @MainActor in
            do {
                let result = try await app.nfc.run(
                    alertMessage: "Hold your iPhone near the tag.",
                    successMessage: "Tag written."
                ) { session, tag in
                    try await TagOperations.writeRecords(session, tag, records: records, options: options)
                }
                Haptics.success()
                alert = AlertItem.success(SavedItemDetailView.successMessage(for: result))
            } catch {
                if NFCEditorError.map(error).isCancellation { return }
                Haptics.error()
                alert = AlertItem(error: error)
            }
        }
    }

    /// Tags are written back exactly as read; profiles are built from their drafts.
    private func recordsToWrite(_ item: SavedItem) throws -> [NDEFRecord] {
        switch item.kind {
        case .tag:
            return item.records
        case .profile:
            return try item.drafts.flatMap { try RecordDraft.buildAll($0) }
        }
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
}

// MARK: - Sheets

private enum SavedDetailSheet: Identifiable {
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

/// One draft of a profile: icon, kind, summary and its size, or a warning when it cannot be built yet.
private struct SavedDraftRow: View {
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
