import Foundation
import SwiftUI
import UIKit
import CoreNFC

/// Reads and writes 16-byte blocks of a FeliCa service that needs no encryption, and checks which services a card has.
@MainActor
struct FeliCaToolView: View {
    @Environment(AppState.self) private var app
    @State private var serviceCode = Data([0x00, 0x0B])
    @State private var blockList = "0-13"
    @State private var readResult: FeliCaReadResult?
    @State private var writeBlock = 0
    @State private var writeData = Data()
    @State private var serviceList = "0009, 000B, 008B, 090F, 108F"
    @State private var serviceResult: FeliCaServiceResult?
    @State private var showingWriteConfirmation = false
    @State private var alert: AlertItem?

    private static let maxBlocks = 64
    private static let maxServices = 64
    /// FeliCa Lite-S keeps its system blocks (ID, MAC, MC and so on) from 0x80 up.
    private static let firstSystemBlock = 0x80

    var body: some View {
        Form {
            Section {
                HexTextField("Service code", data: $serviceCode, byteCount: 2)
                TextField("Blocks, for example 0-13", text: $blockList)
                    .keyboardType(.numbersAndPunctuation)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.body.monospaced())
            } header: {
                Text("Service")
            } footer: {
                Text("Service codes are written most significant byte first. 000B reads the user blocks of a FeliCa Lite-S card and 0009 reads and writes them. List blocks as numbers and ranges, such as 0-13 or 0, 4, 8-9.")
            }

            Section {
                ScanButton("Read blocks", systemImage: "magnifyingglass") {
                    read()
                }
            } footer: {
                Text("iPhone only finds FeliCa cards whose system code this app declares: 12FC (NDEF), FE00, 0003 and 8008. Services that need encryption cannot be read.")
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())

            if let readResult {
                readSection(readResult)
            }

            writeSections

            servicesSections
        }
        .navigationTitle("FeliCa")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Write a system block?", isPresented: $showingWriteConfirmation, titleVisibility: .visible) {
            Button("Write block", role: .destructive) {
                write()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Block \(writeBlock) is a system block on FeliCa Lite-S. Some values there, such as in the MC block, make the card read only for good.")
        }
        .alertItem($alert)
    }

    // MARK: Read

    private func readSection(_ result: FeliCaReadResult) -> some View {
        Section {
            ForEach(result.rows) { row in
                Button {
                    loadIntoWrite(row)
                } label: {
                    BlockRow(row: row)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button {
                        UIPasteboard.general.string = row.data.hexString()
                        Haptics.tap()
                    } label: {
                        Label("Copy hex", systemImage: "doc.on.doc")
                    }
                    Button {
                        loadIntoWrite(row)
                    } label: {
                        Label("Edit this block", systemImage: "square.and.pencil")
                    }
                }
            }
        } header: {
            Text("Service \(FeliCaToolView.codeLabel(result.serviceCode))")
        } footer: {
            Text("Read at \(result.readAt.formatted(date: .omitted, time: .shortened)). Tap a block to load it into the write section below.")
        }
    }

    // MARK: Write

    @ViewBuilder
    private var writeSections: some View {
        Section {
            Stepper("Block \(writeBlock)", value: $writeBlock, in: 0...255)
            HexTextField("Data", data: $writeData, byteCount: 16)
        } header: {
            Text("Write a block")
        } footer: {
            Text("Writes 16 bytes to one block of the service code above. Only services that allow writing without encryption accept it, such as 0009 on FeliCa Lite-S.")
        }

        Section {
            ScanButton("Write block", systemImage: "square.and.pencil") {
                requestWrite()
            }
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets())
    }

    // MARK: Services

    @ViewBuilder
    private var servicesSections: some View {
        Section {
            TextField("Service codes", text: $serviceList)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .font(.body.monospaced())
        } header: {
            Text("Check services")
        } footer: {
            Text("Four hex digits per service code, separated by commas or spaces.")
        }

        Section {
            ScanButton("Check services", systemImage: "list.bullet.rectangle") {
                checkServices()
            }
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets())

        if let serviceResult {
            Section {
                ForEach(serviceResult.services) { service in
                    LabeledContent {
                        Text(FeliCaToolView.statusLabel(service))
                            .foregroundStyle(service.isPresent ? Color.primary : Color.secondary)
                    } label: {
                        Text(FeliCaToolView.codeLabel(service.code))
                            .font(.body.monospaced())
                    }
                }
            } header: {
                Text("Services")
            } footer: {
                Text("Checked at \(serviceResult.checkedAt.formatted(date: .omitted, time: .shortened)). Found services can still need encryption to read.")
            }
        }
    }

    // MARK: Parsing

    private static func codeLabel(_ code: UInt16) -> String {
        code.hex
    }

    private static func statusLabel(_ service: FeliCaService) -> String {
        service.isPresent ? "Key version \(codeLabel(service.keyVersion))" : "Not found"
    }

    /// Parses "0-13", "0, 4, 8-9" or "0x80" into block numbers, keeping the order and dropping repeats.
    private static func parseBlocks(_ text: String) -> [Int]? {
        let separators = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ",;"))
        var blocks: [Int] = []
        var seen = Set<Int>()
        for token in text.components(separatedBy: separators) where !token.isEmpty {
            let bounds = token.split(separator: "-", omittingEmptySubsequences: false)
            let numbers: [Int]
            switch bounds.count {
            case 1:
                guard let value = number(String(bounds[0])) else { return nil }
                numbers = [value]
            case 2:
                guard let first = number(String(bounds[0])),
                      let last = number(String(bounds[1])),
                      first <= last,
                      last - first < maxBlocks else { return nil }
                numbers = Array(first...last)
            default:
                return nil
            }
            for value in numbers where !seen.contains(value) {
                seen.insert(value)
                blocks.append(value)
            }
        }
        return blocks
    }

    private static func number(_ text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let parsed: Int?
        if trimmed.hasPrefix("0x") || trimmed.hasPrefix("0X") {
            parsed = Int(trimmed.dropFirst(2), radix: 16)
        } else {
            parsed = Int(trimmed)
        }
        guard let value = parsed, (0...0xFFFF).contains(value) else { return nil }
        return value
    }

    private static func parseServiceCodes(_ text: String) -> [UInt16]? {
        let separators = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ",;"))
        var codes: [UInt16] = []
        for token in text.components(separatedBy: separators) where !token.isEmpty {
            let digits = token.normalizedHex
            guard digits.count == 4, let value = UInt16(digits, radix: 16) else { return nil }
            if !codes.contains(value) {
                codes.append(value)
            }
        }
        return codes
    }

    // MARK: Actions

    private func validServiceCode() -> UInt16? {
        guard serviceCode.count == 2, let code = serviceCode.uint16BE else {
            alert = AlertItem(error: NFCEditorError.invalidInput("Enter a 2-byte service code, for example 00 0B."))
            return nil
        }
        return code
    }

    private func read() {
        guard let code = validServiceCode() else { return }
        guard let blocks = FeliCaToolView.parseBlocks(blockList), !blocks.isEmpty else {
            alert = AlertItem(error: NFCEditorError.invalidInput("List the blocks as numbers or ranges, for example 0-13."))
            return
        }
        guard blocks.count <= FeliCaToolView.maxBlocks else {
            alert = AlertItem(error: NFCEditorError.invalidInput("Read at most \(FeliCaToolView.maxBlocks) blocks at a time."))
            return
        }
        Task { @MainActor in
            do {
                let data = try await app.nfc.run(
                    alertMessage: "Hold your iPhone near the card.",
                    successMessage: "Blocks read."
                ) { session, tag in
                    try await TagOperations.feliCaRead(session, tag, serviceCode: code, blocks: blocks)
                }
                let rows = zip(blocks, data).map { FeliCaBlockRow(block: $0.0, data: $0.1) }
                readResult = FeliCaReadResult(serviceCode: code, rows: rows, readAt: Date())
                Haptics.success()
            } catch {
                if NFCEditorError.map(error).isCancellation { return }
                Haptics.error()
                alert = AlertItem(error: error)
            }
        }
    }

    private func loadIntoWrite(_ row: FeliCaBlockRow) {
        guard row.block <= 255 else {
            alert = AlertItem(error: NFCEditorError.invalidInput("Blocks above 255 can only be written with Advanced commands."))
            return
        }
        writeBlock = row.block
        writeData = row.data.count == 16 ? row.data : Data(row.data.prefix(16))
        Haptics.tap()
    }

    private func requestWrite() {
        guard validServiceCode() != nil else { return }
        guard writeData.count == 16 else {
            alert = AlertItem(error: NFCEditorError.invalidInput("Enter exactly 16 bytes for the block."))
            return
        }
        if writeBlock >= FeliCaToolView.firstSystemBlock {
            showingWriteConfirmation = true
        } else {
            write()
        }
    }

    private func write() {
        guard let code = validServiceCode() else { return }
        guard writeData.count == 16 else {
            alert = AlertItem(error: NFCEditorError.invalidInput("Enter exactly 16 bytes for the block."))
            return
        }
        let block = writeBlock
        let data = writeData
        Task { @MainActor in
            do {
                try await app.nfc.run(
                    alertMessage: "Hold your iPhone near the card.",
                    successMessage: "Block written."
                ) { session, tag in
                    try await TagOperations.feliCaWrite(session, tag, serviceCode: code, block: block, data: data)
                }
                if var current = readResult, current.serviceCode == code,
                   let index = current.rows.firstIndex(where: { $0.block == block }) {
                    current.rows[index].data = data
                    readResult = current
                }
                Haptics.success()
                alert = AlertItem.success("Block \(block) of service \(FeliCaToolView.codeLabel(code)) was written.")
            } catch {
                if NFCEditorError.map(error).isCancellation { return }
                Haptics.error()
                alert = AlertItem(error: error)
            }
        }
    }

    private func checkServices() {
        guard let codes = FeliCaToolView.parseServiceCodes(serviceList), !codes.isEmpty else {
            alert = AlertItem(error: NFCEditorError.invalidInput("Enter service codes as four hex digits each, for example 000B, 090F."))
            return
        }
        guard codes.count <= FeliCaToolView.maxServices else {
            alert = AlertItem(error: NFCEditorError.invalidInput("Check at most \(FeliCaToolView.maxServices) service codes at a time."))
            return
        }
        Task { @MainActor in
            do {
                let versions = try await app.nfc.run(
                    alertMessage: "Hold your iPhone near the card.",
                    successMessage: "Services checked."
                ) { session, tag in
                    try await TagOperations.feliCaServices(session, tag, serviceCodes: codes)
                }
                let services = zip(codes, versions).map { FeliCaService(code: $0.0, keyVersion: $0.1) }
                serviceResult = FeliCaServiceResult(services: services, checkedAt: Date())
                Haptics.success()
            } catch {
                if NFCEditorError.map(error).isCancellation { return }
                Haptics.error()
                alert = AlertItem(error: error)
            }
        }
    }
}

/// One block as two monospaced lines of 8 bytes plus its ASCII, so it fits a phone screen.
private struct BlockRow: View {
    let row: FeliCaBlockRow

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(hexLines)
                .font(.footnote.monospaced())
            Text(row.data.asciiPreview)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }

    private var title: String {
        let raw = String(row.block, radix: 16, uppercase: true)
        return "Block \(row.block) (0x\(raw.count >= 2 ? raw : "0" + raw))"
    }

    private var hexLines: String {
        let first = Data(row.data.prefix(8)).hexString(separator: " ")
        let second = Data(row.data.dropFirst(8)).hexString(separator: " ")
        return second.isEmpty ? first : first + "\n" + second
    }
}

private struct FeliCaBlockRow: Hashable, Identifiable {
    var block: Int
    var data: Data

    var id: Int { block }
}

private struct FeliCaReadResult: Hashable {
    var serviceCode: UInt16
    var rows: [FeliCaBlockRow]
    var readAt: Date
}

private struct FeliCaService: Hashable, Identifiable {
    var code: UInt16
    var keyVersion: UInt16

    var id: UInt16 { code }
    var isPresent: Bool { keyVersion != 0xFFFF }
}

private struct FeliCaServiceResult: Hashable {
    var services: [FeliCaService]
    var checkedAt: Date
}
