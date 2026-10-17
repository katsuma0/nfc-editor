import Foundation
import SwiftUI
import UIKit
import CoreNFC

/// Reads the whole memory of a tag and lets you rewrite it one page at a time. On Type 5 tags it also
/// shows which blocks are locked and can lock single blocks.
@MainActor
struct MemoryEditorView: View {
    @Environment(AppState.self) private var app
    @State private var dump: MemoryDump?
    /// Type 5 only: the blocks known to be locked, and whether the tag reported its lock state at all.
    @State private var lockedBlocks: Set<Int> = []
    @State private var lockStateKnown = false
    @State private var password = Data()
    @State private var selectedPage: MemoryPage?
    @State private var exportURL: URL?
    @State private var alert: AlertItem?

    var body: some View {
        List {
            introSection
            readSection
            if let dump {
                summarySection(dump)
                pagesSection(dump)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Memory editor")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if let exportURL {
                        ShareLink(item: exportURL) {
                            Label("Export as .bin", systemImage: "square.and.arrow.up")
                        }
                    }
                    Button {
                        copyHex()
                    } label: {
                        Label("Copy as hex", systemImage: "doc.on.doc")
                    }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
                .disabled(dump == nil)
            }
        }
        .sheet(item: $selectedPage) { page in
            PageEditorSheet(
                page: page,
                pageSize: dump?.pageSize ?? 4,
                warning: warning(for: page.index),
                password: sessionPassword,
                isType5: isType5,
                locked: isLocked(page.index) == true,
                onWritten: { index, bytes in
                    pageWritten(index: index, bytes: bytes)
                },
                onLocked: { index in
                    blockLocked(index: index)
                }
            )
        }
        .alertItem($alert)
    }

    // MARK: Sections

    private var introSection: some View {
        Section {
            Text("Reads every page of the tag. Tap a page to change its bytes and write it back.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            DisclosureGroup("Password") {
                HexTextField("Password", data: $password, byteCount: 4)
                Text("Only needed when the tag is password protected.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var readSection: some View {
        Section {
            ScanButton("Read memory") {
                readMemory()
            }
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets())
    }

    private func summarySection(_ dump: MemoryDump) -> some View {
        Section {
            LabeledContent("Chip", value: dump.chip?.name ?? "Unknown")
            LabeledContent("Pages", value: pagesLabel(dump))
            LabeledContent("Bytes", value: ByteFormatter.bytes(dump.readableByteCount))
            if isType5 && lockStateKnown {
                LabeledContent("Locked blocks", value: "\(lockedBlocks.count)")
            }
            LabeledContent("Read", value: dump.readAt.formatted(date: .abbreviated, time: .shortened))
        } header: {
            Text("Tag")
        }
    }

    private func pagesSection(_ dump: MemoryDump) -> some View {
        Section {
            ForEach(dump.pages) { page in
                if canEdit(dump) {
                    Button {
                        selectedPage = page
                    } label: {
                        PageRow(page: page, pageSize: dump.pageSize, warning: warning(for: page.index), locked: isLocked(page.index))
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(rowBackground(page))
                } else {
                    PageRow(page: page, pageSize: dump.pageSize, warning: warning(for: page.index), locked: isLocked(page.index))
                        .listRowBackground(rowBackground(page))
                }
            }
        } header: {
            Text("Pages")
        } footer: {
            Text(pagesFooter(dump))
        }
    }

    // MARK: Derived values

    private var sessionPassword: Data? {
        password.count == 4 ? password : nil
    }

    private var isType5: Bool {
        dump?.chip?.nfcForumType == 5
    }

    /// Nil when the lock state is unknown, which is always the case for chips other than Type 5.
    private func isLocked(_ index: Int) -> Bool? {
        guard isType5 else { return nil }
        if lockedBlocks.contains(index) { return true }
        return lockStateKnown ? false : nil
    }

    private func pagesLabel(_ dump: MemoryDump) -> String {
        let readable = dump.pages.filter { $0.readable }.count
        if readable == dump.pages.count {
            return "\(dump.pages.count)"
        }
        return "\(dump.pages.count), \(readable) readable"
    }

    /// Unreadable pages get a light red row so they stand out in a long list.
    private func rowBackground(_ page: MemoryPage) -> Color? {
        page.readable ? nil : Color.red.opacity(0.1)
    }

    private func canEdit(_ dump: MemoryDump) -> Bool {
        guard let chip = dump.chip else { return true }
        return chip.supportsRawPages
    }

    private func pagesFooter(_ dump: MemoryDump) -> String {
        if !canEdit(dump) {
            return "This chip does not allow single pages to be written. The pages show the NDEF file as read from the tag."
        }
        if dump.chip?.nfcForumType == 5 {
            if lockStateKnown {
                return "Tap a block to edit or lock it. Block 0 holds the capability container. A lock marks blocks that can no longer be written."
            }
            return "Tap a block to edit it. Block 0 holds the capability container. This tag did not report which blocks are locked."
        }
        return "Tap a page to edit it. Pages 0 to 3 hold the serial number, lock bits and capability container. Pages marked in red could not be read."
    }

    /// Short caution for pages whose bytes do more than store data.
    private func warning(for index: Int) -> String? {
        guard let dump else { return nil }
        let chip = dump.chip
        if chip?.nfcForumType == 5 {
            return index == 0 ? "Capability container. Changing it can make the tag unreadable." : nil
        }
        guard dump.pageSize == 4, chip?.nfcForumType != 4 else { return nil }
        if let chip {
            if index == chip.cfg0Page || index == chip.cfg1Page {
                return "Configuration page. A wrong value can lock the tag for good."
            }
            if index == chip.pwdPage {
                return "Password page. Reads always return zeros."
            }
            if index == chip.packPage {
                return "PACK page. Reads always return zeros."
            }
            if index == chip.dynamicLockPage {
                return "Dynamic lock bytes. Lock bits can never be cleared."
            }
        }
        switch index {
        case 0, 1:
            return "Serial number. Read only."
        case 2:
            return "Serial number and static lock bytes. Lock bits can never be cleared."
        case 3:
            return "Capability container. Bits can only be set, never cleared."
        default:
            return nil
        }
    }

    // MARK: Actions

    private func readMemory() {
        guard password.isEmpty || password.count == 4 else {
            alert = AlertItem(error: NFCEditorError.invalidInput("The password must be 4 bytes. Leave it empty if the tag has none."))
            return
        }
        let key = sessionPassword
        Task { @MainActor in
            do {
                let result = try await app.nfc.run(
                    alertMessage: "Hold your iPhone near the tag.",
                    successMessage: "Memory read."
                ) { session, tag -> MemoryReadResult in
                    let memory = try await TagOperations.readMemory(session, tag, password: key)
                    var locks: [Bool]?
                    if case .iso15693(let iso15693) = tag, let last = memory.pages.map({ $0.index }).max(), last >= 0 {
                        session.alertMessage = "Reading which blocks are locked."
                        // Not every Type 5 tag answers the security status command; the dump is still worth showing.
                        locks = try? await ISO15693Commands.blockSecurityStatus(iso15693, from: 0, to: last)
                    }
                    return MemoryReadResult(dump: memory, blockLocks: locks)
                }
                dump = result.dump
                if let locks = result.blockLocks {
                    lockedBlocks = Set(locks.indices.filter { locks[$0] })
                    lockStateKnown = true
                } else {
                    lockedBlocks = []
                    lockStateKnown = false
                }
                exportURL = writeExportFile(result.dump)
                Haptics.success()
            } catch {
                if NFCEditorError.map(error).isCancellation { return }
                Haptics.error()
                alert = AlertItem(error: error)
            }
        }
    }

    private func pageWritten(index: Int, bytes: Data) {
        guard var current = dump,
              let position = current.pages.firstIndex(where: { $0.index == index }) else { return }
        current.pages[position].bytes = bytes
        current.pages[position].readable = true
        dump = current
        exportURL = writeExportFile(current)
    }

    private func blockLocked(index: Int) {
        lockedBlocks.insert(index)
    }

    private func copyHex() {
        guard let dump else { return }
        UIPasteboard.general.string = dump.flatBytes.hexString(separator: " ")
        Haptics.tap()
    }

    /// ShareLink needs a file URL up front, so the .bin is written as soon as a dump arrives.
    private func writeExportFile(_ dump: MemoryDump) -> URL? {
        let rawName = (dump.chip?.name ?? "memory").lowercased()
        let safeName = String(rawName.map { $0.isLetter || $0.isNumber ? $0 : "-" })
        let stamp = Int(dump.readAt.timeIntervalSince1970)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(safeName)-\(stamp).bin")
        do {
            try dump.flatBytes.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }
}

private struct MemoryReadResult: Sendable {
    var dump: MemoryDump
    var blockLocks: [Bool]?
}

/// One monospaced line per page: "0x04  03 0B D1 01  ...." plus an optional caution and, on Type 5 tags, a lock marker.
private struct PageRow: View {
    let page: MemoryPage
    let pageSize: Int
    let warning: String?
    let locked: Bool?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 0) {
                Text(indexLabel)
                    .foregroundStyle(.secondary)
                Text("  " + hexLabel)
                    .foregroundStyle(page.readable ? Color.primary : Color.red)
                Text("  " + asciiLabel)
                    .foregroundStyle(.secondary)
                if locked == true {
                    Spacer(minLength: 8)
                    Image(systemName: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .accessibilityLabel("Locked")
                }
            }
            .font(.system(.callout, design: .monospaced))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            if !page.readable {
                Text("Not readable. The page may need a password or does not exist.")
                    .font(.caption)
                    .foregroundStyle(.red)
            } else if let warning {
                Text(warning)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }

    private var indexLabel: String {
        let raw = String(max(page.index, 0), radix: 16, uppercase: true)
        let padded = raw.count >= 2 ? raw : String(repeating: "0", count: 2 - raw.count) + raw
        return "0x" + padded
    }

    private var hexLabel: String {
        if page.readable && !page.bytes.isEmpty {
            return page.bytes.hexString(separator: " ")
        }
        return Array(repeating: "--", count: max(pageSize, 1)).joined(separator: " ")
    }

    private var asciiLabel: String {
        if page.readable && !page.bytes.isEmpty {
            return page.bytes.asciiPreview
        }
        return String(repeating: ".", count: max(pageSize, 1))
    }
}

/// Sheet that edits the bytes of one page and writes them back to the tag. On Type 5 tags it can also lock the block.
@MainActor
private struct PageEditorSheet: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var bytes: Data
    @State private var alert: AlertItem?
    @State private var showingLockConfirmation = false

    private let page: MemoryPage
    private let pageSize: Int
    private let warning: String?
    private let password: Data?
    private let isType5: Bool
    private let locked: Bool
    private let onWritten: (Int, Data) -> Void
    private let onLocked: (Int) -> Void

    init(
        page: MemoryPage,
        pageSize: Int,
        warning: String?,
        password: Data?,
        isType5: Bool,
        locked: Bool,
        onWritten: @escaping (Int, Data) -> Void,
        onLocked: @escaping (Int) -> Void
    ) {
        let size = max(pageSize, 1)
        var initial: Data = page.readable ? page.bytes : Data()
        if initial.count > size {
            initial = initial.prefix(size)
        }
        self.page = page
        self.pageSize = size
        self.warning = warning
        self.password = password
        self.isType5 = isType5
        self.locked = locked
        self.onWritten = onWritten
        self.onLocked = onLocked
        _bytes = State(initialValue: initial)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent(isType5 ? "Block" : "Page", value: "\(indexLabel) (\(page.index))")
                    if locked {
                        Label("Locked. This block can no longer be written.", systemImage: "lock.fill")
                            .foregroundStyle(.orange)
                    }
                    if page.readable && !page.bytes.isEmpty {
                        LabeledContent("On tag") {
                            Text(page.bytes.hexString(separator: " "))
                                .font(.system(.body, design: .monospaced))
                        }
                    }
                    HexTextField("New bytes", data: $bytes, byteCount: pageSize)
                    LabeledContent("ASCII") {
                        Text(bytes.isEmpty ? "-" : bytes.asciiPreview)
                            .font(.system(.body, design: .monospaced))
                    }
                } footer: {
                    if let warning {
                        Text(warning)
                            .foregroundStyle(.orange)
                    } else {
                        Text("Enter \(ByteFormatter.bytes(pageSize)) in hex.")
                    }
                }

                Section {
                    ScanButton(isType5 ? "Write block" : "Write page") {
                        write()
                    }
                    .disabled(bytes.count != pageSize || locked)
                } footer: {
                    Text(isType5 ? "Hold your iPhone near the same tag to write this block." : "Hold your iPhone near the same tag to write this page.")
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())

                if isType5 && !locked {
                    Section {
                        Button(role: .destructive) {
                            showingLockConfirmation = true
                        } label: {
                            Label("Lock block", systemImage: "lock")
                        }
                        .disabled(app.nfc.isBusy)
                    } footer: {
                        Text("Locking makes the block read only forever. Write the bytes you want first.")
                    }
                }
            }
            .navigationTitle(isType5 ? "Edit block" : "Edit page")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .confirmationDialog("Lock block \(page.index) for good?", isPresented: $showingLockConfirmation, titleVisibility: .visible) {
                Button("Lock block", role: .destructive) {
                    lockBlock()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The block keeps its current bytes and can never be written again.")
            }
            .alertItem($alert)
        }
    }

    private var indexLabel: String {
        let raw = String(max(page.index, 0), radix: 16, uppercase: true)
        let padded = raw.count >= 2 ? raw : String(repeating: "0", count: 2 - raw.count) + raw
        return "0x" + padded
    }

    private func write() {
        guard bytes.count == pageSize else {
            alert = AlertItem(error: NFCEditorError.invalidInput("Enter exactly \(ByteFormatter.bytes(pageSize))."))
            return
        }
        let index = page.index
        let data = bytes
        let key = password
        Task { @MainActor in
            do {
                try await app.nfc.run(
                    alertMessage: "Hold your iPhone near the tag.",
                    successMessage: "Page written."
                ) { session, tag in
                    try await TagOperations.writePage(session, tag, index: index, bytes: data, password: key)
                }
                Haptics.success()
                onWritten(index, data)
                dismiss()
            } catch {
                if NFCEditorError.map(error).isCancellation { return }
                Haptics.error()
                alert = AlertItem(error: error)
            }
        }
    }

    private func lockBlock() {
        let index = page.index
        Task { @MainActor in
            do {
                try await app.nfc.run(
                    alertMessage: "Hold your iPhone near the tag.",
                    successMessage: "Block locked."
                ) { session, tag in
                    try await TagOperations.type5LockBlocks(session, tag, blocks: [index])
                }
                Haptics.success()
                onLocked(index)
                dismiss()
            } catch {
                if NFCEditorError.map(error).isCancellation { return }
                Haptics.error()
                alert = AlertItem(error: error)
            }
        }
    }
}
