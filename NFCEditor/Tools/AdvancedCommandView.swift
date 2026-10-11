import Foundation
import SwiftUI
import UIKit
import CoreNFC

/// Sends raw commands to a tag, one per line, and shows every response.
@MainActor
struct AdvancedCommandView: View {
    @Environment(AppState.self) private var app
    @State private var transport: RawTransport = .mifare
    @State private var commandText = ""
    @State private var results: [CommandResult] = []
    @State private var alert: AlertItem?

    var body: some View {
        List {
            transportSection
            commandSection
            sendSection
            resultsSection
            historySection
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Advanced commands")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        results = []
                    } label: {
                        Label("Clear results", systemImage: "xmark.circle")
                    }
                    .disabled(results.isEmpty)
                    Button(role: .destructive) {
                        app.settings.clearCommandHistory()
                    } label: {
                        Label("Clear history", systemImage: "trash")
                    }
                    .disabled(app.settings.commandHistory.isEmpty)
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
            }
        }
        .alertItem($alert)
    }

    // MARK: Sections

    private var transportSection: some View {
        Section {
            Picker("Transport", selection: $transport) {
                ForEach(RawTransport.allCases, id: \.self) { item in
                    Text(label(for: item)).tag(item)
                }
            }
            .pickerStyle(.segmented)
        } footer: {
            Text(footer(for: transport))
        }
    }

    private var commandSection: some View {
        Section {
            TextEditor(text: $commandText)
                .font(.system(.body, design: .monospaced))
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .frame(minHeight: 120)
            Menu {
                ForEach(presets(for: transport)) { preset in
                    Button(preset.name) {
                        insert(preset.hex)
                    }
                }
            } label: {
                Label("Insert a preset", systemImage: "plus.circle")
            }
            if !commandText.isEmpty {
                Button(role: .destructive) {
                    commandText = ""
                } label: {
                    Label("Clear commands", systemImage: "xmark.circle")
                }
            }
        } header: {
            Text("Commands")
        } footer: {
            Text("One command per line in hex. Spaces are optional. Lines starting with # are ignored.")
        }
    }

    private var sendSection: some View {
        Section {
            ScanButton("Send") {
                send()
            }
            .disabled(commandText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets())
    }

    @ViewBuilder
    private var resultsSection: some View {
        if !results.isEmpty {
            Section {
                ForEach(results) { result in
                    ResultRow(result: result)
                }
            } header: {
                Text("Results")
            }
        }
    }

    @ViewBuilder
    private var historySection: some View {
        if !app.settings.commandHistory.isEmpty {
            Section {
                ForEach(app.settings.commandHistory, id: \.self) { entry in
                    Button {
                        insert(entry)
                    } label: {
                        HStack {
                            Text(entry)
                                .font(.system(.callout, design: .monospaced))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Spacer()
                            Image(systemName: "plus.circle")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            app.settings.commandHistory.removeAll { $0 == entry }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            } header: {
                Text("History")
            } footer: {
                Text("Tap a command to add it to the editor.")
            }
        }
    }

    // MARK: Labels

    private func label(for transport: RawTransport) -> String {
        switch transport {
        case .mifare: return "MIFARE"
        case .apdu: return "APDU"
        case .iso15693: return "ISO 15693"
        case .feliCa: return "FeliCa"
        }
    }

    private func footer(for transport: RawTransport) -> String {
        switch transport {
        case .mifare:
            return "Native NTAG and Ultralight commands such as READ (30) and WRITE (A2). The CRC is added by iOS."
        case .apdu:
            return "ISO 7816 APDUs for DESFire, NTAG DNA and other Type 4 tags: CLA INS P1 P2 Lc data Le."
        case .iso15693:
            return "First byte is the request flags, second the command code, the rest are parameters. 02 means high data rate."
        case .feliCa:
            return "Command code followed by the 8-byte IDm and the parameters. Read the tag first to find its IDm. The length byte is added by iOS."
        }
    }

    private func presets(for transport: RawTransport) -> [Preset] {
        switch transport {
        case .mifare:
            return [
                Preset(name: "GET_VERSION", hex: "60"),
                Preset(name: "READ page 4", hex: "30 04"),
                Preset(name: "FAST_READ pages 4 to 7", hex: "3A 04 07"),
                Preset(name: "READ_SIG", hex: "3C 00"),
                Preset(name: "READ_CNT counter 2", hex: "39 02"),
                Preset(name: "PWD_AUTH FF FF FF FF", hex: "1B FF FF FF FF"),
            ]
        case .apdu:
            return [
                Preset(name: "DESFire GetVersion", hex: "90 60 00 00 00"),
                Preset(name: "DESFire continue (AF)", hex: "90 AF 00 00 00"),
                Preset(name: "Select NDEF app", hex: "00 A4 04 00 07 D2 76 00 00 85 01 01 00"),
                Preset(name: "Select CC file", hex: "00 A4 00 0C 02 E1 03"),
                Preset(name: "Select NDEF file", hex: "00 A4 00 0C 02 E1 04"),
                Preset(name: "Read binary 15 bytes", hex: "00 B0 00 00 0F"),
            ]
        case .iso15693:
            return [
                Preset(name: "Get system info", hex: "02 2B"),
                Preset(name: "Read block 0", hex: "02 20 00"),
                Preset(name: "Read block 1", hex: "02 20 01"),
                Preset(name: "Block security status 0 to 3", hex: "02 2C 00 03"),
            ]
        case .feliCa:
            return [
                Preset(name: "Request system code (add IDm)", hex: "0C"),
                Preset(name: "Request response (add IDm)", hex: "04"),
            ]
        }
    }

    // MARK: Actions

    private func insert(_ hex: String) {
        if commandText.isEmpty || commandText.hasSuffix("\n") {
            commandText += hex
        } else {
            commandText += "\n" + hex
        }
    }

    private func parseCommands() throws -> [RawCommand] {
        var commands: [RawCommand] = []
        let lines = commandText.components(separatedBy: CharacterSet.newlines)
        for (offset, rawLine) in lines.enumerated() {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") || line.hasPrefix("//") { continue }
            guard line.isValidHex, let bytes = Data(hexString: line) else {
                throw NFCEditorError.invalidInput("Line \(offset + 1) is not valid hex.")
            }
            commands.append(RawCommand(transport: transport, bytes: bytes))
        }
        return commands
    }

    private func send() {
        let commands: [RawCommand]
        do {
            commands = try parseCommands()
        } catch {
            alert = AlertItem(error: error)
            return
        }
        guard !commands.isEmpty else {
            alert = AlertItem(error: NFCEditorError.invalidInput("Enter at least one command."))
            return
        }
        // Added last to first so the history reads top to bottom in the order typed.
        for command in commands.reversed() {
            app.settings.addCommandToHistory(command.bytes.hexString(separator: " "))
        }
        let box = ResponseBox()
        results = []
        Task { @MainActor in
            do {
                let responses = try await app.nfc.run(
                    alertMessage: "Hold your iPhone near the tag.",
                    successMessage: "Commands sent."
                ) { session, tag in
                    try await RawBatch.send(commands, session: session, tag: tag, box: box)
                }
                results = rows(for: commands, responses: responses, failure: nil)
                Haptics.success()
            } catch {
                let mapped = NFCEditorError.map(error)
                if mapped.isCancellation { return }
                results = rows(for: commands, responses: box.snapshot(), failure: mapped.errorDescription ?? "Failed.")
                Haptics.error()
                alert = AlertItem(error: error)
            }
        }
    }

    private func rows(for commands: [RawCommand], responses: [RawResponse], failure: String?) -> [CommandResult] {
        var rows: [CommandResult] = []
        rows.reserveCapacity(commands.count)
        for (offset, command) in commands.enumerated() {
            var row = CommandResult(position: offset + 1, command: command.bytes, response: nil, failure: nil)
            if offset < responses.count {
                row.response = responses[offset]
            } else if offset == responses.count, let failure {
                row.failure = failure
            } else {
                row.failure = "Not sent."
            }
            rows.append(row)
        }
        return rows
    }
}

// MARK: - Supporting types

private struct Preset: Identifiable {
    let name: String
    let hex: String

    var id: String { name }
}

private struct CommandResult: Identifiable {
    let id = UUID()
    var position: Int
    var command: Data
    var response: RawResponse?
    var failure: String?
}

/// Collects responses while the session runs so the rows can still be shown when a later command fails.
private final class ResponseBox: @unchecked Sendable {
    private let lock = NSLock()
    private var responses: [RawResponse] = []

    func append(_ response: RawResponse) {
        lock.lock()
        responses.append(response)
        lock.unlock()
    }

    func snapshot() -> [RawResponse] {
        lock.lock()
        defer { lock.unlock() }
        return responses
    }
}

private enum RawBatch {
    /// Sends the commands one at a time so every response before a failure is kept.
    static func send(_ commands: [RawCommand], session: NFCTagReaderSession, tag: NFCTag, box: ResponseBox) async throws -> [RawResponse] {
        var responses: [RawResponse] = []
        for (position, command) in commands.enumerated() {
            let batch: [RawResponse]
            do {
                batch = try await TagOperations.sendRaw(session, tag, commands: [command])
            } catch {
                // Session level failures (cancel, timeout, tag lost) pass through unchanged so the view can stay silent on cancel.
                let mapped = NFCEditorError.map(error)
                guard case .commandFailed(let message) = mapped else { throw mapped }
                throw NFCEditorError.commandFailed("Command \(position + 1) failed: \(detail(of: message))")
            }
            guard let response = batch.first else {
                throw NFCEditorError.commandFailed("Command \(position + 1) returned nothing.")
            }
            box.append(response)
            responses.append(response)
        }
        return responses
    }

    /// sendRaw numbers a command sent on its own as 1, so that prefix is dropped before the real position is added.
    private static func detail(of message: String) -> String {
        let prefix = "Command 1 failed: "
        if message.hasPrefix(prefix) {
            return String(message.dropFirst(prefix.count))
        }
        return message
    }
}

@MainActor
private struct ResultRow: View {
    let result: CommandResult

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Command \(result.position)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(result.command.hexString(separator: " "))
                .font(.system(.callout, design: .monospaced))
            if let response = result.response {
                Text("Response")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(response.bytes.isEmpty ? "No data" : response.bytes.hexString(separator: " "))
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(response.bytes.isEmpty ? Color.secondary : Color.primary)
                HStack {
                    if let sw1 = response.sw1, let sw2 = response.sw2 {
                        Text("SW \(sw1.hex) \(sw2.hex), \(statusLabel(sw1, sw2))")
                    }
                    Spacer()
                    Text("\(response.elapsedMS) ms")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            } else if let failure = result.failure {
                Text(failure)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(.vertical, 2)
        .contextMenu {
            Button {
                UIPasteboard.general.string = result.command.hexString(separator: " ")
            } label: {
                Label("Copy command", systemImage: "doc.on.doc")
            }
            if let response = result.response, !response.bytes.isEmpty {
                Button {
                    UIPasteboard.general.string = response.bytes.hexString(separator: " ")
                } label: {
                    Label("Copy response", systemImage: "doc.on.doc")
                }
            }
        }
    }

    private func statusLabel(_ sw1: UInt8, _ sw2: UInt8) -> String {
        switch (sw1, sw2) {
        case (0x90, 0x00), (0x91, 0x00): return "OK"
        case (0x91, 0xAF): return "more data"
        case (0x6A, 0x82): return "file not found"
        case (0x6A, 0x86), (0x6B, 0x00): return "wrong parameters"
        case (0x69, 0x82): return "security status not satisfied"
        case (0x6D, 0x00): return "instruction not supported"
        case (0x6E, 0x00): return "class not supported"
        case (0x67, 0x00): return "wrong length"
        default: return "error"
        }
    }
}
