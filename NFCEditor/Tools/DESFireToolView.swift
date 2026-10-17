import Foundation
import SwiftUI
import CoreNFC

/// Reads a MIFARE DESFire card's overview, creates the NFC Forum NDEF application on it, or formats it.
@MainActor
struct DESFireToolView: View {
    @Environment(AppState.self) private var app
    @State private var reading: DESFireReading?
    @State private var masterKey = Data(repeating: 0x00, count: 8)
    @State private var ndefFileSize = 2048
    @State private var formatFirst = false
    @State private var showingCreateConfirmation = false
    @State private var showingFormatConfirmation = false
    @State private var showingFormatFinalConfirmation = false
    @State private var alert: AlertItem?

    private static let defaultKey = Data(repeating: 0x00, count: 8)
    private static let ndefApplicationID = Data([0x01, 0x00, 0x00])

    var body: some View {
        Form {
            Section {
                ScanButton("Read card", systemImage: "magnifyingglass") {
                    readCard()
                }
            } footer: {
                Text("Reads the version, the applications, the free memory and the master key settings. Most cards allow this without a key.")
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())

            if let reading {
                cardSection(reading)
                applicationsSection(reading.overview)
                keySettingsSection(reading.overview)
            }

            keySection
            ndefSections
            formatSection
        }
        .navigationTitle("DESFire card")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Create the NDEF application?", isPresented: $showingCreateConfirmation, titleVisibility: .visible) {
            Button(createButtonTitle, role: createButtonRole) {
                createNDEFApplication()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(createConfirmationMessage)
        }
        .confirmationDialog("Format this card?", isPresented: $showingFormatConfirmation, titleVisibility: .visible) {
            Button("Continue", role: .destructive) {
                askFinalFormatConfirmation()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Formatting deletes every application and file on the card, including any NDEF data.")
        }
        .alert("Erase everything on the card?", isPresented: $showingFormatFinalConfirmation) {
            Button("Format card", role: .destructive) {
                formatCard()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone. The card you scan next is wiped back to an empty card.")
        }
        .alertItem($alert)
    }

    // MARK: Overview

    private func cardSection(_ reading: DESFireReading) -> some View {
        let overview = reading.overview
        return Section {
            LabeledContent("Chip", value: reading.chipName)
            if let storage = reading.storageBytes {
                LabeledContent("Storage", value: ByteFormatter.bytes(storage))
            }
            LabeledContent("Free memory", value: overview.freeMemory.map { ByteFormatter.bytes($0) } ?? "Not reported")
            LabeledContent("NDEF application", value: overview.hasNDEFApplication ? "Yes" : "No")
            if let version = overview.version, !version.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Version")
                    Text(version.hexString(separator: " "))
                        .font(.footnote.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        } header: {
            Text("Card")
        } footer: {
            Text("Read at \(reading.readAt.formatted(date: .omitted, time: .shortened)). DESFire D40 cards do not report their free memory.")
        }
    }

    private func applicationsSection(_ overview: DESFireOverview) -> some View {
        Section {
            if overview.applications.isEmpty {
                Text("No applications")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(overview.applications, id: \.self) { aid in
                    LabeledContent {
                        Text(aid == DESFireToolView.ndefApplicationID ? "NDEF" : "")
                            .foregroundStyle(.secondary)
                    } label: {
                        Text(DESFireToolView.aidLabel(aid))
                            .font(.body.monospaced())
                    }
                }
            }
        } header: {
            Text(DESFireToolView.applicationsHeader(overview.applications.count))
        } footer: {
            Text("Application IDs are shown most significant byte first, the way datasheets write them. An empty list can also mean the card only lists its applications after authentication.")
        }
    }

    @ViewBuilder
    private func keySettingsSection(_ overview: DESFireOverview) -> some View {
        if let settings = overview.keySettings {
            Section {
                LabeledContent("Key settings", value: "0x" + settings.hex)
                if let maxKeys = overview.maxKeys {
                    LabeledContent("Master key type", value: DESFireToolView.keyType(maxKeys))
                }
                LabeledContent("Master key can change", value: DESFireToolView.yesNo(settings & 0x01 != 0))
                LabeledContent("List without key", value: DESFireToolView.yesNo(settings & 0x02 != 0))
                LabeledContent("Create without key", value: DESFireToolView.yesNo(settings & 0x04 != 0))
                LabeledContent("Settings can change", value: DESFireToolView.yesNo(settings & 0x08 != 0))
            } header: {
                Text("Master key")
            } footer: {
                if let maxKeys = overview.maxKeys, maxKeys & 0xC0 != 0 {
                    Text("The card master key type is \(DESFireToolView.keyType(maxKeys)). This app only authenticates with DES and 2K3DES keys, so formatting and creating the NDEF application will be refused.")
                        .foregroundStyle(.orange)
                } else {
                    Text("These settings belong to the card master key, the key that guards formatting and creating applications.")
                }
            }
        }
    }

    // MARK: Key and actions

    private var keySection: some View {
        Section {
            HexTextField("Master key", data: $masterKey)
            Button("Use default key") {
                masterKey = DESFireToolView.defaultKey
                Haptics.tap()
            }
        } header: {
            Text("Card master key")
        } footer: {
            Text("8 bytes for DES or 16 bytes for 2K3DES. A new card uses 8 zero bytes. The key is only used to authenticate; it is never changed.")
        }
    }

    @ViewBuilder
    private var ndefSections: some View {
        Section {
            Stepper("NDEF file \(ByteFormatter.bytes(ndefFileSize))", value: $ndefFileSize, in: 256...7000, step: 256)
            Toggle("Format first", isOn: $formatFirst)
        } header: {
            Text("NDEF application")
        } footer: {
            Text(ndefFooter)
        }

        Section {
            ScanButton("Create NDEF application", systemImage: "plus.rectangle.on.rectangle") {
                confirmCreate()
            }
        } footer: {
            Text("Afterwards the card works like any NDEF tag: write records to it in the Write tab.")
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets())
    }

    private var formatSection: some View {
        Section {
            ScanButton("Format card", systemImage: "trash", role: .destructive) {
                confirmFormat()
            }
        } header: {
            Text("Format")
        } footer: {
            Text("Formatting deletes every application and file on the card for good. It needs the card master key.")
                .foregroundStyle(.red)
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets())
    }

    // MARK: Derived values

    private var ndefFooter: String {
        var text = "Creates application 000001 with the NFC Forum name D2760000850101, a capability container file E103 and an NDEF file E104 of the chosen size, so phones see a normal NDEF tag."
        if formatFirst {
            text += " Format first deletes every application on the card before creating it."
        }
        if let free = reading?.overview.freeMemory {
            text += " The card reported \(ByteFormatter.bytes(free)) free."
            if ndefFileSize + 32 > free {
                text += " The NDEF file may not fit; choose a smaller size."
            }
        }
        return text
    }

    private var createButtonTitle: String {
        formatFirst ? "Format and create" : "Create application"
    }

    private var createButtonRole: ButtonRole? {
        formatFirst ? .destructive : nil
    }

    private var createConfirmationMessage: String {
        if formatFirst {
            return "The card you scan next is formatted first, which deletes every application on it, then gets an NDEF application with a \(ByteFormatter.bytes(ndefFileSize)) NDEF file."
        }
        return "The card you scan next gets an NDEF application with a \(ByteFormatter.bytes(ndefFileSize)) NDEF file. Existing applications stay."
    }

    private static func applicationsHeader(_ count: Int) -> String {
        count == 1 ? "1 application" : "\(count) applications"
    }

    /// DESFire sends application IDs least significant byte first.
    private static func aidLabel(_ aid: Data) -> String {
        Data(aid.reversed()).hexString()
    }

    private static func keyType(_ maxKeys: UInt8) -> String {
        switch maxKeys & 0xC0 {
        case 0x40: return "3K3DES"
        case 0x80: return "AES"
        default: return "DES or 2K3DES"
        }
    }

    private static func yesNo(_ value: Bool) -> String {
        value ? "Yes" : "No"
    }

    // MARK: Actions

    private func validKey() -> Data? {
        guard masterKey.count == 8 || masterKey.count == 16 else {
            alert = AlertItem(error: NFCEditorError.invalidInput("The master key must be 8 or 16 bytes."))
            return nil
        }
        return masterKey
    }

    private func readCard() {
        Task { @MainActor in
            do {
                let overview = try await app.nfc.run(
                    alertMessage: "Hold your iPhone near the card.",
                    successMessage: "Card read."
                ) { session, tag in
                    try await TagOperations.desfireOverview(session, tag)
                }
                reading = DESFireReading(overview: overview, readAt: Date())
                Haptics.success()
            } catch {
                if NFCEditorError.map(error).isCancellation { return }
                Haptics.error()
                alert = AlertItem(error: error)
            }
        }
    }

    private func confirmCreate() {
        guard validKey() != nil else { return }
        showingCreateConfirmation = true
    }

    private func createNDEFApplication() {
        guard let key = validKey() else { return }
        let size = ndefFileSize
        let format = formatFirst
        Task { @MainActor in
            do {
                try await app.nfc.run(
                    alertMessage: "Hold your iPhone near the card.",
                    successMessage: "NDEF application created."
                ) { session, tag in
                    try await TagOperations.desfireCreateNDEFApplication(session, tag, masterKey: key, formatFirst: format, ndefFileSize: size)
                }
                reading = nil
                formatFirst = false
                Haptics.success()
                alert = AlertItem.success("The card now has an NDEF application with a \(ByteFormatter.bytes(size)) NDEF file. Write records to it in the Write tab.")
            } catch {
                if NFCEditorError.map(error).isCancellation { return }
                Haptics.error()
                alert = AlertItem(error: error)
            }
        }
    }

    private func confirmFormat() {
        guard validKey() != nil else { return }
        showingFormatConfirmation = true
    }

    /// The second question waits for the first dialog to finish closing, or UIKit drops it.
    private func askFinalFormatConfirmation() {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            showingFormatFinalConfirmation = true
        }
    }

    private func formatCard() {
        guard let key = validKey() else { return }
        Task { @MainActor in
            do {
                try await app.nfc.run(
                    alertMessage: "Hold your iPhone near the card.",
                    successMessage: "Card formatted."
                ) { session, tag in
                    try await TagOperations.desfireFormat(session, tag, masterKey: key)
                }
                reading = nil
                Haptics.success()
                alert = AlertItem.success("The card is empty. Create the NDEF application to use it as an NDEF tag again.")
            } catch {
                if NFCEditorError.map(error).isCancellation { return }
                Haptics.error()
                alert = AlertItem(error: error)
            }
        }
    }
}

private struct DESFireReading: Hashable {
    var overview: DESFireOverview
    var readAt: Date

    var chipSpec: ChipSpec? {
        guard let version = overview.version, version.count >= 7 else { return nil }
        return ChipIdentifier.fromDESFireVersion(hardware: Data(version.prefix(7)))
    }

    var chipName: String {
        chipSpec?.name ?? "MIFARE DESFire"
    }

    var storageBytes: Int? {
        chipSpec?.userMemoryBytes
    }
}
