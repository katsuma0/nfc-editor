import Foundation
import SwiftUI
import UIKit

/// Everything the app learned about a scanned tag, laid out like a native settings list.
struct TagDetailView: View {
    @Environment(AppState.self) private var app
    @State private var alert: AlertItem?
    @State private var showingSavePrompt = false
    @State private var saveName = ""

    private let info: TagInfo

    init(info: TagInfo) {
        self.info = info
    }

    var body: some View {
        List {
            tagSection
            recordsSection
            if let dump = info.dump {
                memorySection(dump)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(info.chip.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        saveName = defaultSaveName
                        showingSavePrompt = true
                    } label: {
                        Label("Save tag", systemImage: "folder.badge.plus")
                    }
                    Button {
                        app.sendToWrite(records: info.records)
                    } label: {
                        Label("Edit in Write tab", systemImage: "square.and.pencil")
                    }
                    .disabled(info.records.isEmpty)
                    ShareLink(item: exportText) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    Button {
                        copy(info.serialLine)
                    } label: {
                        Label("Copy serial", systemImage: "doc.on.doc")
                    }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
            }
        }
        .alert("Save tag", isPresented: $showingSavePrompt) {
            TextField("Name", text: $saveName)
            Button("Save") {
                saveTag()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(info.dump == nil
                 ? "The tag details and records are kept in the Saved tab."
                 : "The tag details, records and memory dump are kept in the Saved tab.")
        }
        .alertItem($alert)
    }

    // MARK: Sections

    private var tagSection: some View {
        Section {
            Group {
                row("Tag type", value: info.chipLine, systemImage: "cpu")
                row("Technology", value: info.typeLine, systemImage: "antenna.radiowaves.left.and.right")
                LabeledContent {
                    Text(info.serialLine)
                        .font(.body.monospaced())
                } label: {
                    Label("Serial number", systemImage: "number")
                }
                .contextMenu {
                    Button {
                        copy(info.serialLine)
                    } label: {
                        Label("Copy serial", systemImage: "doc.on.doc")
                    }
                }
                if let atqa = info.atqaLine {
                    row("ATQA", value: atqa, systemImage: "number.square")
                }
                if let sak = info.sakLine {
                    row("SAK", value: sak, systemImage: "number.circle")
                }
            }
            Group {
                if let password = passwordLine {
                    row("Password protected", value: password, systemImage: info.passwordProtected == true ? "lock" : "lock.open")
                }
                if let memory = info.memoryLine {
                    row("Memory", value: memory, systemImage: "memorychip")
                }
                row("Data format", value: dataFormatLine, systemImage: "doc.badge.gearshape")
                if let size = info.sizeLine {
                    row("Size", value: size, systemImage: "chart.pie")
                }
                row("Writable", value: info.writableLine, systemImage: "pencil")
            }
            Group {
                if let counter = counterLine {
                    row("Counter", value: counter, systemImage: "arrow.clockwise.circle")
                }
                if let signature = info.signature {
                    signatureRow(signature)
                }
                if let tamper = info.tamperStatus {
                    tamperRow(tamper)
                }
                if let mirror = mirrorField {
                    row("Mirror", value: mirror.value, systemImage: mirror.systemImage)
                }
                // Extras are keyed by position so two fields with the same label never collide.
                ForEach(Array(otherExtras.enumerated()), id: \.offset) { entry in
                    row(entry.element.label, value: entry.element.value, systemImage: entry.element.systemImage)
                }
                row("Scanned", value: info.scannedAt.formatted(date: .abbreviated, time: .shortened), systemImage: "clock")
            }
        } header: {
            Text("Tag")
        } footer: {
            if let notes = info.chip.notes, !notes.isEmpty {
                Text(notes)
            }
        }
    }

    private var recordsSection: some View {
        Section {
            if info.records.isEmpty {
                Label("No records", systemImage: "tray")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(info.records) { record in
                    NavigationLink {
                        RecordDetailView(record: record)
                    } label: {
                        RecordRowView(record: record)
                    }
                }
            }
        } header: {
            Text("Records")
        } footer: {
            if !info.records.isEmpty {
                Text(recordsFooter)
            }
        }
    }

    private func memorySection(_ dump: MemoryDump) -> some View {
        Section("Memory") {
            NavigationLink {
                MemoryDumpView(dump: dump)
            } label: {
                Label("View memory dump", systemImage: "memorychip")
            }
            row("Pages read", value: pagesReadLine(dump), systemImage: "square.grid.3x3")
        }
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

    private func signatureRow(_ signature: Data) -> some View {
        LabeledContent {
            VStack(alignment: .trailing, spacing: 4) {
                if let verdict = info.signatureVerdict {
                    Text(TagDetailView.verdictText(verdict))
                        .foregroundStyle(TagDetailView.verdictColor(verdict))
                        .multilineTextAlignment(.trailing)
                }
                HStack(spacing: 12) {
                    Text(signaturePreview(signature))
                        .font(.body.monospaced())
                        .lineLimit(1)
                    Button("Copy") {
                        copy(signature.hexString(separator: " "))
                    }
                    .buttonStyle(.borderless)
                }
            }
        } label: {
            Label("Signature", systemImage: signatureImage)
        }
    }

    private func tamperRow(_ status: Data) -> some View {
        LabeledContent {
            VStack(alignment: .trailing, spacing: 4) {
                Text(TagDetailView.tamperText(status))
                    .foregroundStyle(TagDetailView.tamperColor(status))
                    .multilineTextAlignment(.trailing)
                Text(status.hexString(separator: " "))
                    .font(.footnote.monospaced())
                    .foregroundStyle(.secondary)
            }
        } label: {
            Label("Tamper", systemImage: "bolt.shield")
        }
    }

    // MARK: Derived text

    private var passwordLine: String? {
        if let protected = info.passwordProtected {
            return protected ? "Yes" : "No"
        }
        return info.chip.supportsPassword ? "Unknown" : nil
    }

    private var dataFormatLine: String {
        if let type = info.chip.nfcForumType {
            return "NFC Forum Type \(type)"
        }
        return "Unknown"
    }

    private var counterLine: String? {
        if let value = info.counter {
            if let enabled = info.counterEnabled {
                return "\(value) (\(enabled ? "enabled" : "disabled"))"
            }
            return "\(value)"
        }
        if let enabled = info.counterEnabled {
            return enabled ? "Enabled" : "Disabled"
        }
        return nil
    }

    private var signatureImage: String {
        switch info.signatureVerdict {
        case .genuine?:
            return "checkmark.seal.fill"
        case .notGenuine?:
            return "xmark.seal"
        case .noKey?, nil:
            return "checkmark.seal"
        }
    }

    static func verdictText(_ verdict: SignatureVerdict) -> String {
        switch verdict {
        case .genuine:
            return "Genuine NXP chip"
        case .notGenuine:
            return "Signature does not match NXP's key"
        case .noKey:
            return "No public key for this chip"
        }
    }

    static func verdictFooter(_ verdict: SignatureVerdict) -> String {
        switch verdict {
        case .genuine:
            return "The signature matches NXP's public key for this serial number."
        case .notGenuine:
            return "The signature does not match NXP's public key for this serial number. The chip is likely a clone."
        case .noKey:
            return "NXP has not published a public key for this chip, so the signature cannot be checked."
        }
    }

    static func verdictColor(_ verdict: SignatureVerdict) -> Color {
        switch verdict {
        case .genuine:
            return .green
        case .notGenuine:
            return .red
        case .noKey:
            return .secondary
        }
    }

    /// READ_TT_STATUS answers a 4-byte message and a status byte: "C" for a closed loop, "O" for an open one,
    /// "I" when the chip could not tell, for example because tamper detection is off.
    static func tamperText(_ status: Data) -> String {
        guard status.count >= 5 else { return "Unknown" }
        switch status[status.startIndex + 4] {
        case 0x43:
            return "Wire intact"
        case 0x4F:
            return "Wire open, the tag was tampered with"
        case 0x49:
            return "Not determined"
        default:
            return "Unknown"
        }
    }

    static func tamperColor(_ status: Data) -> Color {
        guard status.count >= 5 else { return .secondary }
        switch status[status.startIndex + 4] {
        case 0x43:
            return .green
        case 0x4F:
            return .red
        default:
            return .secondary
        }
    }

    /// The mirror setting gets its own row next to the counter instead of sitting among the other extras.
    private var mirrorField: TagField? {
        info.extras.first { $0.label == "Mirror" }
    }

    private var otherExtras: [TagField] {
        info.extras.filter { $0.label != "Mirror" }
    }

    private var recordsFooter: String {
        let count = info.records.count
        let used = info.ndefUsedBytes ?? NDEFMessageCodec.byteCount(info.records)
        let records = count == 1 ? "1 record" : "\(count) records"
        return "\(records), \(ByteFormatter.bytes(used))"
    }

    private func pagesReadLine(_ dump: MemoryDump) -> String {
        let readable = dump.pages.filter { $0.readable }.count
        return "\(readable) of \(dump.pages.count)"
    }

    private func signaturePreview(_ signature: Data) -> String {
        let shown = signature.prefix(4).hexString(separator: " ")
        return signature.count > 4 ? shown + " ..." : shown
    }

    private var defaultSaveName: String {
        "\(info.chip.name) \(info.serialLine)"
    }

    @MainActor
    private var exportText: String {
        app.store.exportText(for: SavedItem.tag(name: defaultSaveName, info: info))
    }

    // MARK: Actions

    @MainActor
    private func saveTag() {
        let trimmed = saveName.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmed.isEmpty ? defaultSaveName : trimmed
        app.store.add(SavedItem.tag(name: name, info: info))
        Haptics.success()
        // The name prompt is still animating away, so the confirmation needs a moment before it can show.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            alert = AlertItem.success("Saved as \(name).")
        }
    }

    @MainActor
    private func copy(_ text: String) {
        UIPasteboard.general.string = text
        Haptics.tap()
    }
}

/// Monospaced page by page view of a memory dump.
private struct MemoryDumpView: View {
    let dump: MemoryDump

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(summaryLine)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
                .padding(.vertical, 8)
            Divider()
            ScrollView([.vertical, .horizontal]) {
                Text(text)
                    .font(.system(.footnote, design: .monospaced))
                    .textSelection(.enabled)
                    .padding()
            }
        }
        .navigationTitle("Memory dump")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    UIPasteboard.general.string = text
                    Haptics.tap()
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .disabled(dump.pages.isEmpty)
            }
        }
    }

    private var text: String {
        if dump.pages.isEmpty {
            return "No pages were read."
        }
        return ByteFormatter.hexDump(dump.flatBytes, pageSize: dump.pageSize, startIndex: dump.pages.first?.index ?? 0)
    }

    private var summaryLine: String {
        let pages = dump.pages.count == 1 ? "1 page" : "\(dump.pages.count) pages"
        let each = dump.pageSize == 1 ? "1 byte each" : "\(dump.pageSize) bytes each"
        let unreadable = dump.pages.filter { !$0.readable }.count
        if unreadable == 0 {
            return "\(pages), \(each). All pages were read."
        }
        let skipped = unreadable == 1 ? "1 page" : "\(unreadable) pages"
        return "\(pages), \(each). \(skipped) could not be read and are shown as zeros."
    }
}
