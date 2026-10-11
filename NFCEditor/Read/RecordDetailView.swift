import Foundation
import SwiftUI
import UIKit

/// One record in full: parsed fields, the actions it offers and the raw bytes behind it.
struct RecordDetailView: View {
    @Environment(AppState.self) private var app
    @Environment(\.openURL) private var openURL
    @State private var alert: AlertItem?
    @State private var vcardURL: URL?
    @State private var isJoiningWiFi = false

    private let record: NDEFRecord
    private let summary: RecordSummary

    private static let hexPreviewLimit = 1024

    init(record: NDEFRecord) {
        self.record = record
        self.summary = RecordParsers.parse(record)
    }

    var body: some View {
        List {
            headerSection
            if !summary.fields.isEmpty {
                detailsSection
            }
            if !summary.actions.isEmpty {
                actionsSection
            }
            technicalSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle(summary.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        app.sendToWrite(records: [record])
                    } label: {
                        Label("Edit in Write tab", systemImage: "square.and.pencil")
                    }
                    Button {
                        copy(record.payload.hexString(separator: " "))
                    } label: {
                        Label("Copy payload as hex", systemImage: "doc.on.doc")
                    }
                    .disabled(record.payload.isEmpty)
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
            }
        }
        .onAppear {
            prepareVCardFile()
        }
        .alertItem($alert)
    }

    // MARK: Sections

    private var headerSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Label(summary.title, systemImage: summary.systemImage)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                Text(summary.detail.isEmpty ? "No content" : summary.detail)
                    .font(.body)
                    .textSelection(.enabled)
            }
            .padding(.vertical, 4)
        }
    }

    private var detailsSection: some View {
        Section("Details") {
            // Two fields can share a label (two phone numbers, say), so rows are keyed by position.
            ForEach(Array(summary.fields.enumerated()), id: \.offset) { entry in
                LabeledContent {
                    Text(entry.element.value)
                        .multilineTextAlignment(.trailing)
                        .textSelection(.enabled)
                } label: {
                    Label(entry.element.label, systemImage: entry.element.systemImage)
                }
            }
        }
    }

    private var actionsSection: some View {
        Section("Actions") {
            ForEach(Array(summary.actions.enumerated()), id: \.offset) { entry in
                actionRow(entry.element)
            }
        }
    }

    private var technicalSection: some View {
        Section("Technical") {
            row("Type name format", value: "\(record.tnf.label) (\(record.tnf.rawValue))", systemImage: "number")
            row("Type", value: describe(record.type), systemImage: "tag")
            row("ID", value: describe(record.identifier), systemImage: "tag")
            row("Payload size", value: ByteFormatter.bytes(record.payload.count), systemImage: "externaldrive")
            row("Record size", value: ByteFormatter.bytes(record.encodedSize), systemImage: "externaldrive")
            VStack(alignment: .leading, spacing: 6) {
                Label("Payload", systemImage: "doc.text")
                Text(payloadHexDump)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                if record.payload.count > RecordDetailView.hexPreviewLimit {
                    Text("Showing the first \(RecordDetailView.hexPreviewLimit) bytes.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
            if let text = payloadText {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Payload as text", systemImage: "textformat")
                    Text(text)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                .padding(.vertical, 4)
            }
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

    @ViewBuilder
    private func actionRow(_ action: RecordAction) -> some View {
        switch action {
        case .openURL(let url):
            Button {
                openURL(url)
            } label: {
                Label(openTitle(for: url), systemImage: openImage(for: url))
            }
        case .copy(let text):
            Button {
                copy(text)
            } label: {
                Label(copyTitle(for: text), systemImage: "doc.on.doc")
            }
        case .joinWiFi(let credential):
            Button {
                joinWiFi(credential)
            } label: {
                Label("Join network", systemImage: "wifi")
            }
            .disabled(isJoiningWiFi)
        case .shareVCard:
            if let url = vcardURL {
                ShareLink(item: url) {
                    Label("Share contact", systemImage: "person.crop.circle.badge.plus")
                }
            } else {
                Label("Share contact", systemImage: "person.crop.circle.badge.plus")
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Derived text

    private var payloadHexDump: String {
        if record.payload.isEmpty {
            return "Empty"
        }
        return RecordDetailView.hexLines(record.payload.prefix(RecordDetailView.hexPreviewLimit))
    }

    private var payloadText: String? {
        RecordDetailView.printableText(record.payload)
    }

    private func describe(_ data: Data) -> String {
        if data.isEmpty {
            return "None"
        }
        return RecordDetailView.printableText(data) ?? data.hexString(separator: " ")
    }

    private func openTitle(for url: URL) -> String {
        switch (url.scheme ?? "").lowercased() {
        case "tel":
            return "Call"
        case "mailto":
            return "Send email"
        case "sms", "smsto", "mms", "mmsto":
            return "Send message"
        case "geo", "maps":
            return "Open in Maps"
        case "http", "https":
            if RecordDetailView.isMapsURL(url) {
                return "Open in Maps"
            }
            if (url.host() ?? "").lowercased().hasSuffix("play.google.com") {
                return "Open in Google Play"
            }
            return "Open link"
        default:
            return "Open"
        }
    }

    private func openImage(for url: URL) -> String {
        switch (url.scheme ?? "").lowercased() {
        case "tel":
            return "phone"
        case "mailto":
            return "envelope"
        case "sms", "smsto", "mms", "mmsto":
            return "message"
        case "geo", "maps":
            return "map"
        case "http", "https":
            return RecordDetailView.isMapsURL(url) ? "map" : "safari"
        default:
            return "arrow.up.right.square"
        }
    }

    private func copyTitle(for text: String) -> String {
        if let field = summary.fields.first(where: { $0.value == text }) {
            return "Copy \(field.label.lowercased())"
        }
        if text == summary.detail {
            return "Copy \(detailNoun)"
        }
        return "Copy"
    }

    private var detailNoun: String {
        switch summary.kind {
        case .text: return "text"
        case .url, .customURI, .smartPoster, .social: return "link"
        case .email: return "email address"
        case .phone, .sms: return "phone number"
        case .geo: return "coordinates"
        case .address: return "address"
        case .wifi: return "network name"
        case .bluetooth: return "address"
        case .contact: return "name"
        case .app: return "package name"
        case .customMIME, .external: return "type"
        case .raw, .empty, .unknown: return "payload"
        }
    }

    // MARK: Actions

    @MainActor
    private func copy(_ text: String) {
        UIPasteboard.general.string = text
        Haptics.tap()
    }

    @MainActor
    private func joinWiFi(_ credential: WiFiCredential) {
        isJoiningWiFi = true
        Task { @MainActor in
            defer { isJoiningWiFi = false }
            do {
                try await WiFiJoiner.join(credential)
                Haptics.success()
                alert = AlertItem.success("Connected to \(credential.ssid).")
            } catch {
                if NFCEditorError.map(error).isCancellation { return }
                Haptics.error()
                alert = AlertItem(error: error)
            }
        }
    }

    /// ShareLink needs a file URL up front, so the .vcf is written as soon as the screen appears.
    private func prepareVCardFile() {
        guard vcardURL == nil else { return }
        for action in summary.actions {
            guard case .shareVCard(let card) = action else { continue }
            vcardURL = RecordDetailView.writeVCardFile(card)
            return
        }
    }

    // MARK: Helpers

    private static func writeVCardFile(_ card: VCard) -> URL? {
        var name = card.fullName
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        if name.isEmpty {
            name = "Contact"
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(name)
            .appendingPathExtension("vcf")
        do {
            try Data(card.encode().utf8).write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    private static func isMapsURL(_ url: URL) -> Bool {
        let host = (url.host() ?? "").lowercased()
        if host.hasSuffix("maps.apple.com") || host == "maps.app.goo.gl" || host.hasPrefix("maps.google") {
            return true
        }
        return host.contains("google.") && url.path().hasPrefix("/maps")
    }

    private static func printableText(_ data: Data) -> String? {
        guard !data.isEmpty, let decoded = String(data: data, encoding: .utf8) else { return nil }
        let printable = decoded.unicodeScalars.allSatisfy { scalar in
            let code = scalar.value
            if code == 0x09 || code == 0x0A || code == 0x0D { return true }
            return code >= 0x20 && code != 0x7F
        }
        return printable ? decoded : nil
    }

    /// Offset, eight bytes of hex and the printable ASCII, one line per eight bytes.
    private static func hexLines(_ data: Data, bytesPerLine: Int = 8) -> String {
        let bytes = [UInt8](data)
        var lines: [String] = []
        lines.reserveCapacity((bytes.count + bytesPerLine - 1) / bytesPerLine)
        var offset = 0
        while offset < bytes.count {
            let end = min(offset + bytesPerLine, bytes.count)
            let chunk = Array(bytes[offset..<end])
            var hex = chunk.map { $0.hex }.joined(separator: " ")
            if chunk.count < bytesPerLine {
                hex += String(repeating: "   ", count: bytesPerLine - chunk.count)
            }
            let label = UInt16(truncatingIfNeeded: offset).hex
            lines.append("\(label): \(hex)  \(Data(chunk).asciiPreview)")
            offset = end
        }
        return lines.joined(separator: "\n")
    }
}
