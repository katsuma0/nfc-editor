import Foundation
import SwiftUI
import CoreNFC

/// Sets or removes the 4-byte password on NTAG and Ultralight EV1 tags, and can lock the configuration for good.
@MainActor
struct PasswordToolView: View {
    private enum Mode: String, CaseIterable, Identifiable {
        case set = "Set"
        case remove = "Remove"
        case lockConfig = "Lock config"

        var id: String { rawValue }
    }

    @Environment(AppState.self) private var app
    @State private var mode: Mode = .set
    @State private var password = Data()
    @State private var pack = Data([0x00, 0x00])
    @State private var protectReads = false
    @State private var protectFromPage = 4
    @State private var authLimit = 0
    @State private var currentPassword = Data()
    @State private var passwordToRemove = Data()
    @State private var lockConfigPassword = Data()
    @State private var showingConfirmation = false
    @State private var showingLockConfigFirst = false
    @State private var showingLockConfigFinal = false
    @State private var alert: AlertItem?

    var body: some View {
        Form {
            Section {
                Picker("Mode", selection: $mode) {
                    ForEach(Mode.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .pickerStyle(.segmented)
            } footer: {
                Text("Works on NTAG213, NTAG215, NTAG216, NTAG210, NTAG212 and MIFARE Ultralight EV1 tags. Other chips refuse the commands.")
            }

            switch mode {
            case .set:
                setSections
            case .remove:
                removeSections
            case .lockConfig:
                lockConfigSections
            }
        }
        .navigationTitle("Password")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Set the password?", isPresented: $showingConfirmation, titleVisibility: .visible) {
            Button("Set password") {
                setPassword()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(confirmationMessage)
        }
        .confirmationDialog("Lock the configuration for good?", isPresented: $showingLockConfigFirst, titleVisibility: .visible) {
            Button("Continue", role: .destructive) {
                askFinalLockConfig()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The protected pages, the protection mode, the attempt limit and the counter and mirror settings of the tag you scan next can never be changed again.")
        }
        .alert("Are you sure?", isPresented: $showingLockConfigFinal) {
            Button("Lock configuration", role: .destructive) {
                lockConfiguration()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This is the last check. Locking the configuration cannot be undone by any app.")
        }
        .alertItem($alert)
    }

    // MARK: Set

    @ViewBuilder
    private var setSections: some View {
        Section {
            HexTextField("Password", data: $password, byteCount: 4)
            HexTextField("PACK", data: $pack, byteCount: 2)
            Button("Generate random password") {
                generatePassword()
            }
        } header: {
            Text("New password")
        } footer: {
            Text("The password is 4 bytes. The PACK is a 2-byte answer the tag sends back after a correct password; 00 00 is fine. Write both down. They cannot be read back from the tag.")
        }

        Section {
            Toggle("Also protect reads", isOn: $protectReads)
            // Page 230 is the last page of the NTAG216, the largest chip with a password; a higher AUTH0 protects nothing.
            Stepper("Protect from page \(protectFromPage)", value: $protectFromPage, in: 4...230)
            Picker("Wrong attempts allowed", selection: $authLimit) {
                Text("Unlimited").tag(0)
                ForEach(1...7, id: \.self) { limit in
                    Text("\(limit)").tag(limit)
                }
            }
        } header: {
            Text("Protection")
        } footer: {
            Text(protectionFooter)
        }

        Section {
            DisclosureGroup("Current password") {
                HexTextField("Current password", data: $currentPassword, byteCount: 4)
            }
        } footer: {
            Text("Only needed when the tag already has a password.")
        }

        Section {
            ScanButton("Set password") {
                confirmSetPassword()
            }
        } footer: {
            Text(attemptsWarning)
                .foregroundStyle(authLimit > 0 ? Color.red : Color.secondary)
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets())
    }

    private var protectionFooter: String {
        let access = protectReads ? "read or write" : "write"
        return "Pages \(protectFromPage) and up need the password to \(access). Page 4 is the first page of user memory. The configuration pages at the end are always included."
    }

    private var confirmationMessage: String {
        var message = "The tag you scan next will need \(password.hexString(separator: " ")) from page \(protectFromPage) on. Write the password down first; it cannot be read back from the tag."
        if authLimit > 0 {
            let attempts = authLimit == 1 ? "one wrong attempt" : "\(authLimit) wrong attempts"
            message += " After \(attempts) the tag stops accepting the password for good."
        }
        return message
    }

    private var attemptsWarning: String {
        "Wrong attempts allowed: with a limit set, the tag counts every wrong password and stops accepting the password for good once the limit is reached. The counter is never reset, so a few typos can lock the protected pages permanently. Leave it on Unlimited unless you really need it."
    }

    // MARK: Remove

    @ViewBuilder
    private var removeSections: some View {
        Section {
            HexTextField("Current password", data: $passwordToRemove, byteCount: 4)
        } header: {
            Text("Current password")
        } footer: {
            Text("Removing the password lets every page be read and written again, and clears the read protection and the attempt limit.")
        }

        Section {
            ScanButton("Remove password") {
                removePassword()
            }
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets())
    }

    // MARK: Lock config

    @ViewBuilder
    private var lockConfigSections: some View {
        Section {
            Label {
                Text("Sets CFGLCK, which locks the configuration pages for good. The protected pages, read protection, attempt limit, counter and mirror settings stay exactly as they are now. The password and PACK can still be changed.")
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
            }
            .foregroundStyle(.red)
        } footer: {
            Text("Set the password, counter and mirror the way you want them first. Lock the configuration last, when nobody should be able to switch the protection off.")
        }

        Section {
            HexTextField("Current password", data: $lockConfigPassword, byteCount: 4)
        } header: {
            Text("Current password")
        } footer: {
            Text("Only needed when the configuration pages are password protected. Leave it empty otherwise.")
        }

        Section {
            ScanButton("Lock configuration", role: .destructive) {
                confirmLockConfiguration()
            }
        } footer: {
            Text("You are asked twice before the scan starts.")
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets())
    }

    // MARK: Actions

    private func generatePassword() {
        var bytes: [UInt8] = []
        for _ in 0..<4 {
            bytes.append(UInt8.random(in: UInt8.min...UInt8.max))
        }
        password = Data(bytes)
        Haptics.tap()
    }

    private func validateSetInputs() -> Bool {
        guard password.count == 4 else {
            alert = AlertItem(error: NFCEditorError.invalidInput("Enter a 4-byte password."))
            return false
        }
        guard pack.count == 2 else {
            alert = AlertItem(error: NFCEditorError.invalidInput("Enter a 2-byte PACK, for example 00 00."))
            return false
        }
        guard currentPassword.isEmpty || currentPassword.count == 4 else {
            alert = AlertItem(error: NFCEditorError.invalidInput("The current password must be 4 bytes. Leave it empty if the tag has none."))
            return false
        }
        return true
    }

    private func confirmSetPassword() {
        guard validateSetInputs() else { return }
        showingConfirmation = true
    }

    private func setPassword() {
        guard validateSetInputs() else { return }
        let config = PasswordConfig(
            password: password,
            pack: pack,
            protectFromPage: protectFromPage,
            protectReads: protectReads,
            authLimit: authLimit,
            currentPassword: currentPassword.isEmpty ? nil : currentPassword
        )
        let passwordHex = password.hexString(separator: " ")
        let firstPage = protectFromPage
        Task { @MainActor in
            do {
                try await app.nfc.run(
                    alertMessage: "Hold your iPhone near the tag.",
                    successMessage: "Password set."
                ) { session, tag in
                    try await TagOperations.setPassword(session, tag, config: config)
                }
                Haptics.success()
                alert = AlertItem.success("The tag now asks for the password from page \(firstPage) on. Keep \(passwordHex) somewhere safe.")
            } catch {
                if NFCEditorError.map(error).isCancellation { return }
                Haptics.error()
                alert = AlertItem(error: error)
            }
        }
    }

    private func confirmLockConfiguration() {
        guard lockConfigPassword.isEmpty || lockConfigPassword.count == 4 else {
            alert = AlertItem(error: NFCEditorError.invalidInput("The current password must be 4 bytes. Leave it empty if the tag has none."))
            return
        }
        showingLockConfigFirst = true
    }

    /// The first dialog is still animating away, so the final check waits a moment before it shows.
    private func askFinalLockConfig() {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            showingLockConfigFinal = true
        }
    }

    private func lockConfiguration() {
        guard lockConfigPassword.isEmpty || lockConfigPassword.count == 4 else {
            alert = AlertItem(error: NFCEditorError.invalidInput("The current password must be 4 bytes. Leave it empty if the tag has none."))
            return
        }
        let key: Data? = lockConfigPassword.isEmpty ? nil : lockConfigPassword
        Task { @MainActor in
            do {
                try await app.nfc.run(
                    alertMessage: "Hold your iPhone near the tag.",
                    successMessage: "Configuration locked."
                ) { session, tag in
                    try await TagOperations.lockConfiguration(session, tag, password: key)
                }
                Haptics.success()
                alert = AlertItem.success("The configuration of this tag is now locked for good.")
            } catch {
                if NFCEditorError.map(error).isCancellation { return }
                Haptics.error()
                alert = AlertItem(error: error)
            }
        }
    }

    private func removePassword() {
        guard passwordToRemove.count == 4 else {
            alert = AlertItem(error: NFCEditorError.invalidInput("Enter the current 4-byte password."))
            return
        }
        let key = passwordToRemove
        Task { @MainActor in
            do {
                try await app.nfc.run(
                    alertMessage: "Hold your iPhone near the tag.",
                    successMessage: "Password removed."
                ) { session, tag in
                    try await TagOperations.removePassword(session, tag, currentPassword: key)
                }
                Haptics.success()
                alert = AlertItem.success("The password was removed. Every page can be read and written again.")
            } catch {
                if NFCEditorError.map(error).isCancellation { return }
                Haptics.error()
                alert = AlertItem(error: error)
            }
        }
    }
}
