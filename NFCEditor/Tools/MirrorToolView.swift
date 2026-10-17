import Foundation
import SwiftUI
import CoreNFC

/// Writes a link that the NTAG completes with its own serial number, read counter, or both, every time it is read.
@MainActor
struct MirrorToolView: View {
    @Environment(AppState.self) private var app
    @State private var url = "https://example.com/tag?id={mirror}"
    @State private var kind: MirrorKind = .uid
    @State private var password = Data()
    @State private var currentSetting: MirrorReading?
    @State private var lastWritten: String?
    @State private var alert: AlertItem?

    private static let kinds: [MirrorKind] = [.uid, .counter, .both]
    private static let sampleUID = "04A2246A4F6B80"
    private static let sampleCounter = "00002A"

    var body: some View {
        Form {
            linkSection
            kindSection
            previewSection
            passwordSection
            writeSection
            if let lastWritten {
                Section {
                    Text(lastWritten)
                        .font(.footnote.monospaced())
                        .textSelection(.enabled)
                } header: {
                    Text("Last written")
                }
            }
            settingSection
            turnOffSection
        }
        .navigationTitle("Mirror")
        .navigationBarTitleDisplayMode(.inline)
        .alertItem($alert)
    }

    // MARK: Sections

    private var linkSection: some View {
        Section {
            TextField("https://example.com/tag?id={mirror}", text: $url)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.body.monospaced())
        } header: {
            Text("Link")
        } footer: {
            Text("Type {mirror} where the value should go. Without it, the value goes at the end of the link.")
        }
    }

    private var kindSection: some View {
        Section {
            Picker("Mirror", selection: $kind) {
                ForEach(MirrorToolView.kinds, id: \.self) { item in
                    Text(MirrorToolView.title(for: item)).tag(item)
                }
            }
        } footer: {
            Text(kindFooter)
        }
    }

    private var previewSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text("Written to the tag")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(preview.written)
                    .font(.footnote.monospaced())
                    .textSelection(.enabled)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("What a phone sees, for example")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(preview.example)
                    .font(.footnote.monospaced())
            }
        } header: {
            Text("Result")
        } footer: {
            Text("The zeros are placeholders. The chip swaps them for live values while it is read, so the stored link never changes.")
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
            ScanButton("Write mirrored URL") {
                write()
            }
        } footer: {
            Text("Works on NTAG 213, 215 and 216, including the F and TT models. The link replaces every record on the tag.")
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets())
    }

    @ViewBuilder
    private var settingSection: some View {
        if let currentSetting {
            Section {
                LabeledContent("Mirror", value: MirrorToolView.settingLabel(currentSetting.config))
                if currentSetting.config.kind != .none {
                    LabeledContent("Starts at", value: "Page \(currentSetting.config.page), byte \(currentSetting.config.byte)")
                }
            } header: {
                Text("Mirror setting")
            } footer: {
                Text("Read at \(currentSetting.readAt.formatted(date: .omitted, time: .shortened)).")
            }
        }
        Section {
            ScanButton("Read mirror setting") {
                readSetting()
            }
        } footer: {
            Text("Shows what the tag mirrors and where in its memory the value starts.")
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets())
    }

    private var turnOffSection: some View {
        Section {
            ScanButton("Turn mirror off") {
                turnOff()
            }
        } footer: {
            Text("The link stays on the tag with its placeholder zeros. Only the live values stop.")
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets())
    }

    // MARK: Derived values

    private var trimmedURL: String {
        url.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var preview: (written: String, example: String) {
        let written = NTAGMirror.mirroredURL(url: trimmedURL, kind: kind).fullURL
        let example = MirrorToolView.replacingMirror(in: trimmedURL, with: MirrorToolView.sampleValue(for: kind))
        return (written, example)
    }

    private var kindFooter: String {
        switch kind {
        case .uid, .none:
            return "The tag writes its 7-byte serial number as 14 hex digits."
        case .counter:
            return "The tag writes its read counter as 6 hex digits. The counter is switched on for you and goes up by one for each read."
        case .both:
            return "The tag writes its serial number, the letter x, then its read counter. The counter is switched on for you."
        }
    }

    private static func title(for kind: MirrorKind) -> String {
        switch kind {
        case .none: return "Off"
        case .uid: return "Serial number"
        case .counter: return "Read counter"
        case .both: return "Serial number and counter"
        }
    }

    private static func settingLabel(_ config: MirrorConfig) -> String {
        config.kind == .none ? "Off" : title(for: config.kind)
    }

    private static func sampleValue(for kind: MirrorKind) -> String {
        switch kind {
        case .none: return ""
        case .uid: return sampleUID
        case .counter: return sampleCounter
        case .both: return sampleUID + "x" + sampleCounter
        }
    }

    /// Same placement rule as NTAGMirror.mirroredURL, with a sample value instead of the zeros.
    private static func replacingMirror(in url: String, with value: String) -> String {
        if let range = url.range(of: "{mirror}") {
            return url.replacingCharacters(in: range, with: value)
        }
        return url + value
    }

    // MARK: Actions

    private func validatedURL() -> String? {
        let link = trimmedURL
        guard !link.isEmpty else {
            alert = AlertItem(error: NFCEditorError.invalidInput("Enter a link."))
            return nil
        }
        guard link.components(separatedBy: "{mirror}").count <= 2 else {
            alert = AlertItem(error: NFCEditorError.invalidInput("Use {mirror} only once."))
            return nil
        }
        let full = NTAGMirror.mirroredURL(url: link, kind: kind).fullURL
        guard let parsed = URL(string: full), parsed.scheme != nil else {
            alert = AlertItem(error: NFCEditorError.invalidInput("Enter a full link, for example https://example.com/tag?id={mirror}."))
            return nil
        }
        return link
    }

    private func write() {
        guard password.isEmpty || password.count == 4 else {
            alert = AlertItem(error: NFCEditorError.invalidInput("The password must be 4 bytes. Leave it empty if the tag has none."))
            return
        }
        guard let link = validatedURL() else { return }
        let mirrorKind = kind
        let key: Data? = password.count == 4 ? password : nil
        Task { @MainActor in
            do {
                let written = try await app.nfc.run(
                    alertMessage: "Hold your iPhone near the tag.",
                    successMessage: "Mirrored link written."
                ) { session, tag in
                    try await TagOperations.writeMirroredURL(session, tag, url: link, kind: mirrorKind, password: key)
                }
                lastWritten = written
                currentSetting = nil
                Haptics.success()
                alert = AlertItem.success("The tag now holds the link. Each read shows the \(MirrorToolView.valueName(for: mirrorKind)) in place of the zeros.")
            } catch {
                if NFCEditorError.map(error).isCancellation { return }
                Haptics.error()
                alert = AlertItem(error: error)
            }
        }
    }

    private static func valueName(for kind: MirrorKind) -> String {
        switch kind {
        case .none: return "link"
        case .uid: return "serial number"
        case .counter: return "read counter"
        case .both: return "serial number and read counter"
        }
    }

    private func readSetting() {
        Task { @MainActor in
            do {
                let config = try await app.nfc.run(
                    alertMessage: "Hold your iPhone near the tag.",
                    successMessage: "Mirror setting read."
                ) { session, tag in
                    try await TagOperations.readMirror(session, tag)
                }
                currentSetting = MirrorReading(config: config, readAt: Date())
                Haptics.success()
            } catch {
                if NFCEditorError.map(error).isCancellation { return }
                Haptics.error()
                alert = AlertItem(error: error)
            }
        }
    }

    private func turnOff() {
        guard password.isEmpty || password.count == 4 else {
            alert = AlertItem(error: NFCEditorError.invalidInput("The password must be 4 bytes. Leave it empty if the tag has none."))
            return
        }
        let key: Data? = password.count == 4 ? password : nil
        Task { @MainActor in
            do {
                try await app.nfc.run(
                    alertMessage: "Hold your iPhone near the tag.",
                    successMessage: "Mirror turned off."
                ) { session, tag in
                    try await TagOperations.disableMirror(session, tag, password: key)
                }
                if let current = currentSetting {
                    var config = current.config
                    config.kind = .none
                    currentSetting = MirrorReading(config: config, readAt: Date())
                }
                Haptics.success()
                alert = AlertItem.success("The mirror is off. The tag now returns the link exactly as stored.")
            } catch {
                if NFCEditorError.map(error).isCancellation { return }
                Haptics.error()
                alert = AlertItem(error: error)
            }
        }
    }
}

private struct MirrorReading: Hashable {
    var config: MirrorConfig
    var readAt: Date
}
