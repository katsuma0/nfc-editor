import Foundation
import SwiftUI
import CoreNFC

/// Sets or removes the 4-byte password on NTAG and Ultralight EV1 tags.
@MainActor
struct PasswordToolView: View {
    private enum Mode: String, CaseIterable, Identifiable {
        case set = "Set"
        case remove = "Remove"

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
    @State private var showingConfirmation = false
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
            Stepper("Protect from page \(protectFromPage)", value: $protectFromPage, in: 4...255)
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
