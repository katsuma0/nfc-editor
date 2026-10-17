import Foundation
import SwiftUI
import CoreNFC

/// Tests, changes and removes the 16-byte 3DES key of a MIFARE Ultralight C tag.
@MainActor
struct UltralightCToolView: View {
    @Environment(AppState.self) private var app
    @State private var currentKey = UltralightC.defaultKey
    @State private var newKey = Data()
    @State private var firstPage = 4
    @State private var writeOnly = true
    @State private var showingConfirmation = false
    @State private var alert: AlertItem?

    /// AUTH0 at 0x30 (48) points past the last page, so the protected range is 3 to 47.
    private static let protectablePages = 3...47

    var body: some View {
        Form {
            Section {
                HexTextField("Key", data: $currentKey, byteCount: 16)
                LabeledContent("As text") {
                    Text(UltralightCToolView.textPreview(currentKey))
                        .font(.body.monospaced())
                }
                Button("Use default key") {
                    currentKey = UltralightC.defaultKey
                    Haptics.tap()
                }
            } header: {
                Text("Current key")
            } footer: {
                Text("New Ultralight C tags ship with BREAKMEIFYOUCAN! as their key. The key can never be read back from a tag, so keep a copy of any key you set.")
            }

            Section {
                ScanButton("Test key") {
                    testKey()
                }
            } footer: {
                Text("Runs the 3DES handshake with the current key. Nothing on the tag changes.")
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())

            Section {
                HexTextField("New key", data: $newKey, byteCount: 16)
                LabeledContent("As text") {
                    Text(UltralightCToolView.textPreview(newKey))
                        .font(.body.monospaced())
                }
                Button("Generate random key") {
                    generateKey()
                }
                Button("Use default key") {
                    newKey = UltralightC.defaultKey
                    Haptics.tap()
                }
            } header: {
                Text("New key")
            } footer: {
                Text("16 bytes. Write the new key down before you set it. Without it, the protected pages are out of reach for good.")
            }

            Section {
                Stepper("Protect from page \(firstPage)", value: $firstPage, in: UltralightCToolView.protectablePages)
                Toggle("Only protect writes", isOn: $writeOnly)
            } header: {
                Text("Protection")
            } footer: {
                Text(protectionFooter)
            }

            Section {
                ScanButton("Set key and protection") {
                    confirmSetKey()
                }
            } footer: {
                Text("Authenticates with the current key, writes the new key, then sets the first protected page.")
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())

            Section {
                ScanButton("Remove protection") {
                    removeProtection()
                }
            } footer: {
                Text("Authenticates with the current key and opens every page again. The key itself stays on the tag.")
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
        }
        .navigationTitle("Ultralight C key")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Set a new key?", isPresented: $showingConfirmation, titleVisibility: .visible) {
            Button("Set key", role: .destructive) {
                setKey()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(confirmationMessage)
        }
        .alertItem($alert)
    }

    // MARK: Derived values

    private var protectionFooter: String {
        let access = writeOnly ? "Writing" : "Reading and writing"
        let hex = String(firstPage, radix: 16, uppercase: true)
        return "\(access) pages \(firstPage) (0x\(hex.count >= 2 ? hex : "0" + hex)) and up needs the key. User memory starts at page 4; the key and settings sit at pages 42 to 47. Turn off \"Only protect writes\" and phones can no longer read the records without the key."
    }

    private var confirmationMessage: String {
        let access = writeOnly ? "write" : "read or write"
        return "The tag you scan next will need the new key to \(access) pages \(firstPage) and up. The key can never be read back from the tag."
    }

    /// Many keys are typed as text, like the default one, so the ASCII view helps check them.
    private static func textPreview(_ key: Data) -> String {
        guard !key.isEmpty else { return "-" }
        return key.asciiPreview
    }

    // MARK: Actions

    private func generateKey() {
        var bytes: [UInt8] = []
        for _ in 0..<16 {
            bytes.append(UInt8.random(in: UInt8.min...UInt8.max))
        }
        newKey = Data(bytes)
        Haptics.tap()
    }

    private func validCurrentKey() -> Data? {
        guard currentKey.count == 16 else {
            alert = AlertItem(error: NFCEditorError.invalidInput("Enter the current 16-byte key."))
            return nil
        }
        return currentKey
    }

    private func testKey() {
        guard let key = validCurrentKey() else { return }
        Task { @MainActor in
            do {
                try await app.nfc.run(
                    alertMessage: "Hold your iPhone near the tag.",
                    successMessage: "Key accepted."
                ) { session, tag in
                    try await TagOperations.ultralightCAuthenticate(session, tag, key: key)
                }
                Haptics.success()
                alert = AlertItem.success("The tag accepted the key.")
            } catch {
                if NFCEditorError.map(error).isCancellation { return }
                Haptics.error()
                alert = AlertItem(error: error)
            }
        }
    }

    private func confirmSetKey() {
        guard validCurrentKey() != nil else { return }
        guard newKey.count == 16 else {
            alert = AlertItem(error: NFCEditorError.invalidInput("Enter a new 16-byte key."))
            return
        }
        showingConfirmation = true
    }

    private func setKey() {
        guard let current = validCurrentKey() else { return }
        guard newKey.count == 16 else {
            alert = AlertItem(error: NFCEditorError.invalidInput("Enter a new 16-byte key."))
            return
        }
        let key = newKey
        let page = firstPage
        let onlyWrites = writeOnly
        Task { @MainActor in
            do {
                try await app.nfc.run(
                    alertMessage: "Hold your iPhone near the tag.",
                    successMessage: "Key set."
                ) { session, tag in
                    try await TagOperations.ultralightCSetKey(session, tag, currentKey: current, newKey: key, firstPage: page, writeOnly: onlyWrites)
                }
                // The tag now answers to the new key, so it becomes the one to test and remove with.
                currentKey = key
                newKey = Data()
                Haptics.success()
                alert = AlertItem.success("The new key is set and pages \(page) and up are protected. The current key field now holds the new key.")
            } catch {
                if NFCEditorError.map(error).isCancellation { return }
                Haptics.error()
                alert = AlertItem(error: error)
            }
        }
    }

    private func removeProtection() {
        guard let key = validCurrentKey() else { return }
        Task { @MainActor in
            do {
                try await app.nfc.run(
                    alertMessage: "Hold your iPhone near the tag.",
                    successMessage: "Protection removed."
                ) { session, tag in
                    try await TagOperations.ultralightCRemoveProtection(session, tag, key: key)
                }
                Haptics.success()
                alert = AlertItem.success("Every page can be read and written without the key again.")
            } catch {
                if NFCEditorError.map(error).isCancellation { return }
                Haptics.error()
                alert = AlertItem(error: error)
            }
        }
    }
}
