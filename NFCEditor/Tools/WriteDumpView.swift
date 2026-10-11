import Foundation
import SwiftUI
import UniformTypeIdentifiers
import CoreNFC

/// Writes a memory dump from a saved tag, pasted hex or a file back onto a tag, page by page.
@MainActor
struct WriteDumpView: View {
    private enum SourceKind: String, CaseIterable, Identifiable {
        case saved = "Saved tag"
        case pasted = "Paste hex"
        case file = "File"

        var id: String { rawValue }
    }

    private struct RangeKey: Equatable {
        var pageCount: Int
        var userRange: ClosedRange<Int>?
    }

    @Environment(AppState.self) private var app
    @State private var sourceKind: SourceKind = .saved
    @State private var selectedSavedID: UUID?
    @State private var pastedHex = ""
    @State private var importedData: Data?
    @State private var importedName = ""
    @State private var pageSize = 4
    @State private var fromPage = 4
    @State private var toPage = 4
    @State private var includeSystemPages = false
    @State private var password = Data()
    @State private var showingImporter = false
    @State private var showingConfirmation = false
    @State private var alert: AlertItem?

    var body: some View {
        Form {
            sourceSection
            if let dump = currentDump {
                rangeSection(dump)
                passwordSection
                writeSection
            }
        }
        .navigationTitle("Write dump")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.data, .item]) { result in
            handleImport(result)
        }
        .confirmationDialog(
            "Write the system pages too?",
            isPresented: $showingConfirmation,
            titleVisibility: .visible
        ) {
            Button("Write dump", role: .destructive) {
                write()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The lock bytes, capability container and configuration pages will be written as they are in the dump. Wrong values cannot be undone. The serial number pages are skipped because the tag does not accept writes to them.")
        }
        .onChange(of: rangeKey, initial: true) { _, _ in
            resetRange()
        }
        .onChange(of: fromPage) { _, newValue in
            if toPage < newValue { toPage = newValue }
        }
        .onChange(of: toPage) { _, newValue in
            if fromPage > newValue { fromPage = newValue }
        }
        .alertItem($alert)
    }

    // MARK: Source

    private var sourceSection: some View {
        Section {
            Picker("Source", selection: $sourceKind) {
                ForEach(SourceKind.allCases) { kind in
                    Text(kind.rawValue).tag(kind)
                }
            }
            .pickerStyle(.segmented)

            switch sourceKind {
            case .saved:
                savedSource
            case .pasted:
                pastedSource
            case .file:
                fileSource
            }
        } header: {
            Text("Source")
        } footer: {
            Text(sourceFooter)
        }
    }

    @ViewBuilder
    private var savedSource: some View {
        if savedWithDumps.isEmpty {
            Text("No saved tags have a memory dump. Scan a tag with full memory reading on, then save it from the tag details.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else {
            Picker("Saved tag", selection: $selectedSavedID) {
                Text("Choose a tag").tag(UUID?.none)
                ForEach(savedWithDumps) { item in
                    Text(item.name).tag(Optional(item.id))
                }
            }
            if let item = selectedSaved, let dump = item.tagInfo?.dump {
                LabeledContent("Chip", value: dump.chip?.name ?? item.tagInfo?.chip.name ?? "Unknown")
                LabeledContent("Pages", value: "\(pageWord(dump.pages.count)), \(ByteFormatter.bytes(dump.pageSize)) each")
            }
        }
    }

    @ViewBuilder
    private var pastedSource: some View {
        TextEditor(text: $pastedHex)
            .font(.system(.body, design: .monospaced))
            .textInputAutocapitalization(.characters)
            .autocorrectionDisabled()
            .frame(minHeight: 120)
        pageSizePicker
        if !pastedHex.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if let dump = currentDump {
                LabeledContent("Parsed", value: "\(ByteFormatter.bytes(dump.pages.count * dump.pageSize)), \(pageWord(dump.pages.count))")
            } else {
                Text("Not valid hex. Use an even number of hex digits.")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    @ViewBuilder
    private var fileSource: some View {
        Button {
            showingImporter = true
        } label: {
            Label(importedData == nil ? "Choose a file" : "Choose another file", systemImage: "doc")
        }
        if let data = importedData {
            LabeledContent("File", value: importedName)
            LabeledContent("Size", value: ByteFormatter.bytes(data.count))
        }
        pageSizePicker
    }

    private var pageSizePicker: some View {
        Picker("Bytes per page", selection: $pageSize) {
            Text("4").tag(4)
            Text("8").tag(8)
        }
    }

    private var sourceFooter: String {
        switch sourceKind {
        case .saved:
            return "Only saved tags that were scanned with full memory reading have a dump."
        case .pasted:
            return "Hex bytes with or without spaces, one page after another from page 0. NTAG and Ultralight tags use 4-byte pages."
        case .file:
            return "A .bin file is used as raw bytes from page 0. A text file with hex is decoded first. NTAG and Ultralight tags use 4-byte pages."
        }
    }

    // MARK: Range, password and write

    private func rangeSection(_ dump: MemoryDump) -> some View {
        let maxPage = max(dump.pages.count - 1, 0)
        return Section {
            Stepper("From page \(fromPage)", value: $fromPage, in: 0...maxPage)
            Stepper("To page \(toPage)", value: $toPage, in: 0...maxPage)
            LabeledContent("Selected", value: "\(pageWord(selectedCount)), \(ByteFormatter.bytes(selectedCount * dump.pageSize))")
            NavigationLink {
                DumpPreviewView(dump: dump, range: selectedRange)
            } label: {
                Label("Preview pages", systemImage: "list.bullet.rectangle")
            }
            Toggle("Include pages 0 to 3 and config pages", isOn: $includeSystemPages)
        } header: {
            Text("Pages")
        } footer: {
            if includeSystemPages {
                Text("Pages 0 to 3 hold the serial number, lock bits and capability container, and the last pages hold the configuration and password. Writing them can lock the tag for good or make it unreadable. Only turn this on when you know exactly what the bytes do.")
                    .foregroundStyle(.red)
            } else {
                Text("Only pages inside the user memory of the tag you hold are written. The serial number, lock bits, capability container and configuration pages are skipped even if they are selected.")
            }
        }
    }

    private var passwordSection: some View {
        Section {
            DisclosureGroup("Password") {
                HexTextField("Password", data: $password, byteCount: 4)
            }
        } footer: {
            Text("Only needed when the tag is password protected.")
        }
    }

    private var writeSection: some View {
        Section {
            ScanButton("Write dump") {
                if includeSystemPages {
                    showingConfirmation = true
                } else {
                    write()
                }
            }
            .disabled(selectedCount <= 0)
        } footer: {
            Text("The tag is written page by page. Keep it still until the checkmark appears.")
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets())
    }

    // MARK: Derived values

    private var savedWithDumps: [SavedItem] {
        app.store.items.filter { $0.tagInfo?.dump != nil }
    }

    private var selectedSaved: SavedItem? {
        guard let id = selectedSavedID else { return nil }
        return savedWithDumps.first { $0.id == id }
    }

    private var currentDump: MemoryDump? {
        switch sourceKind {
        case .saved:
            return selectedSaved?.tagInfo?.dump
        case .pasted:
            guard pastedHex.isValidHex, let data = Data(hexString: pastedHex), !data.isEmpty else { return nil }
            return MemoryDump(flatBytes: data, pageSize: pageSize, chip: nil)
        case .file:
            guard let data = importedData, !data.isEmpty else { return nil }
            return MemoryDump(flatBytes: data, pageSize: pageSize, chip: nil)
        }
    }

    private var rangeKey: RangeKey {
        RangeKey(pageCount: currentDump?.pages.count ?? 0, userRange: currentDump?.chip?.userPageRange)
    }

    private var selectedRange: ClosedRange<Int> {
        let lower = min(fromPage, toPage)
        let upper = max(fromPage, toPage)
        return lower...upper
    }

    private var selectedCount: Int {
        guard let dump = currentDump, !dump.pages.isEmpty else { return 0 }
        let last = dump.pages.count - 1
        let lower = max(selectedRange.lowerBound, 0)
        let upper = min(selectedRange.upperBound, last)
        guard lower <= upper else { return 0 }
        return upper - lower + 1
    }

    private func pageWord(_ count: Int) -> String {
        count == 1 ? "1 page" : "\(count) pages"
    }

    private func resetRange() {
        guard let dump = currentDump, !dump.pages.isEmpty else {
            fromPage = 4
            toPage = 4
            return
        }
        let last = dump.pages.count - 1
        if let user = dump.chip?.userPageRange {
            fromPage = min(max(user.lowerBound, 0), last)
            toPage = min(max(user.upperBound, 0), last)
        } else {
            fromPage = min(4, last)
            toPage = last
        }
        if toPage < fromPage {
            toPage = fromPage
        }
    }

    // MARK: Actions

    private func handleImport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            let accessed = url.startAccessingSecurityScopedResource()
            defer {
                if accessed { url.stopAccessingSecurityScopedResource() }
            }
            do {
                let data = try Data(contentsOf: url)
                guard !data.isEmpty else {
                    alert = AlertItem(error: NFCEditorError.invalidInput("The file has no bytes."))
                    return
                }
                importedData = WriteDumpView.flatBytes(from: data)
                importedName = url.lastPathComponent
                sourceKind = .file
            } catch {
                alert = AlertItem(error: NFCEditorError.failed("The file could not be read."))
            }
        case .failure(let error):
            if NFCEditorError.map(error).isCancellation { return }
            alert = AlertItem(error: error)
        }
    }

    /// A text file full of hex is decoded; anything else is taken as raw bytes.
    private static func flatBytes(from data: Data) -> Data {
        if data.count <= 65_536,
           let text = String(data: data, encoding: .utf8),
           text.isValidHex,
           let decoded = Data(hexString: text) {
            return decoded
        }
        return data
    }

    private func write() {
        guard let dump = currentDump, selectedCount > 0 else {
            alert = AlertItem(error: NFCEditorError.invalidInput("Choose a source with at least one page."))
            return
        }
        guard password.isEmpty || password.count == 4 else {
            alert = AlertItem(error: NFCEditorError.invalidInput("The password must be 4 bytes. Leave it empty if the tag has none."))
            return
        }
        let range = selectedRange
        let key: Data? = password.isEmpty ? nil : password
        let includeSystem = includeSystemPages
        Task { @MainActor in
            do {
                let written = try await app.nfc.run(
                    alertMessage: "Hold your iPhone near the tag.",
                    successMessage: "Dump written."
                ) { session, tag in
                    try await DumpWriter.write(dump, range: range, includeSystemPages: includeSystem, password: key, session: session, tag: tag)
                }
                Haptics.success()
                alert = AlertItem.success("Wrote \(pageWord(written)).")
            } catch {
                if NFCEditorError.map(error).isCancellation { return }
                Haptics.error()
                alert = AlertItem(error: error)
            }
        }
    }
}

// MARK: - Supporting types

private enum DumpWriter {
    /// Narrows the range to the user memory of the tag being held, or to every writable page when system pages were asked for.
    static func write(_ dump: MemoryDump, range: ClosedRange<Int>, includeSystemPages: Bool, password: Data?, session: NFCTagReaderSession, tag: NFCTag) async throws -> Int {
        let (spec, _) = try await TagOperations.identify(session, tag)
        let isType5 = spec.nfcForumType == 5
        let isType2 = !isType5 && spec.pageSize == 4
        var lower = range.lowerBound
        var upper = range.upperBound
        if includeSystemPages {
            // Pages 0 and 1 hold the serial number and refuse every write, which would stop the whole dump at page 0.
            if isType2 {
                lower = max(lower, 2)
            }
            guard lower <= upper else {
                throw NFCEditorError.invalidInput("Pages 0 and 1 hold the serial number and cannot be written. Select pages from 2 up.")
            }
        } else if let user = spec.userPageRange {
            // Block 0 of a Type 5 tag is its capability container, so it stays with the system pages.
            let first = isType5 ? max(user.lowerBound, 1) : user.lowerBound
            lower = max(lower, first)
            upper = min(upper, user.upperBound)
            guard lower <= upper else {
                throw NFCEditorError.invalidInput("Pages \(range.lowerBound) to \(range.upperBound) are outside the user memory of \(spec.name), which is pages \(first) to \(user.upperBound).")
            }
        } else if isType2 || isType5 {
            // Unknown chip: at least keep the serial number, lock bits and capability container untouched.
            lower = max(lower, isType5 ? 1 : 4)
            guard lower <= upper else {
                throw NFCEditorError.invalidInput("Pages below \(lower) are skipped. Select a page from \(lower) up, or turn on the system pages option.")
            }
        }
        return try await TagOperations.writeDump(session, tag, dump: dump, range: lower...upper, password: password)
    }
}

/// Monospaced hex dump of the pages that are about to be written.
private struct DumpPreviewView: View {
    let dump: MemoryDump
    let range: ClosedRange<Int>

    var body: some View {
        ScrollView([.vertical, .horizontal]) {
            Text(text)
                .font(.system(.footnote, design: .monospaced))
                .textSelection(.enabled)
                .padding()
        }
        .navigationTitle("Preview")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var text: String {
        let pages = dump.pages.filter { range.contains($0.index) }
        guard let first = pages.first else { return "No pages in the selected range." }
        var data = Data()
        data.reserveCapacity(pages.count * dump.pageSize)
        for page in pages {
            var chunk: Data = page.readable ? page.bytes.prefix(dump.pageSize) : Data()
            if chunk.count < dump.pageSize {
                chunk.append(Data(repeating: 0, count: dump.pageSize - chunk.count))
            }
            data.append(chunk)
        }
        return ByteFormatter.hexDump(data, pageSize: dump.pageSize, startIndex: first.index)
    }
}
