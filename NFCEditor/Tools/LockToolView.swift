import Foundation
import SwiftUI
import CoreNFC

/// Makes a tag read only, either forever with the lock bits or with only the NDEF read only flag.
/// Gated by an explicit acknowledgement and a confirmation.
@MainActor
struct LockToolView: View {
    private enum Mode: String, CaseIterable, Identifiable {
        case lockBits = "Lock bits"
        case ndefFlag = "NDEF flag only"

        var id: String { rawValue }
    }

    @Environment(AppState.self) private var app
    @State private var mode: Mode = .lockBits
    @State private var acknowledged = false
    @State private var showingConfirmation = false
    @State private var alert: AlertItem?

    var body: some View {
        Form {
            Section {
                Picker("Method", selection: $mode) {
                    ForEach(Mode.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .pickerStyle(.segmented)
            } footer: {
                Text(modeExplanation)
            }

            Section {
                Label {
                    Text(warningText)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                .foregroundStyle(.red)
            } footer: {
                Text("Write and verify the tag first, then read it back in the Read tab to check it holds exactly what you want.")
            }

            Section {
                Toggle(acknowledgementTitle, isOn: $acknowledged)
            }

            Section {
                ScanButton(buttonTitle, systemImage: "lock.fill", role: .destructive) {
                    showingConfirmation = true
                }
                .disabled(!acknowledged)
            } footer: {
                Text("Locking does not add a password. Use the Password tool for protection you can remove later.")
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
        }
        .navigationTitle("Lock tag")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: mode) { _, _ in
            // The acknowledgement covers one method; switching asks for it again.
            acknowledged = false
        }
        .confirmationDialog(confirmationTitle, isPresented: $showingConfirmation, titleVisibility: .visible) {
            Button(buttonTitle, role: .destructive) {
                lock()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(confirmationMessage)
        }
        .alertItem($alert)
    }

    // MARK: Text

    private var modeExplanation: String {
        switch mode {
        case .lockBits:
            return "Sets the lock bits of the chip. No app and no phone can change the tag again, not even with raw commands."
        case .ndefFlag:
            return "Only marks the tag as read only in its capability container. Phones treat it as read only and refuse to write records, but raw page writes, the memory editor and passwords still work. Works on Type 2 and Type 5 tags."
        }
    }

    private var warningText: String {
        switch mode {
        case .lockBits:
            return "Locking is permanent. The records stay readable, but the tag can never be written, erased or formatted again, by this app or any other."
        case .ndefFlag:
            return "On Type 2 tags the read only flag is permanent. It cannot be cleared, so phones will never write records to the tag again. On Type 5 tags only a raw write of block 0 in the memory editor clears it."
        }
    }

    private var acknowledgementTitle: String {
        switch mode {
        case .lockBits:
            return "I understand this cannot be undone"
        case .ndefFlag:
            return "I understand this cannot be undone on Type 2 tags"
        }
    }

    private var buttonTitle: String {
        switch mode {
        case .lockBits:
            return "Lock tag"
        case .ndefFlag:
            return "Set read only flag"
        }
    }

    private var confirmationTitle: String {
        switch mode {
        case .lockBits:
            return "Lock this tag permanently?"
        case .ndefFlag:
            return "Mark this tag read only?"
        }
    }

    private var confirmationMessage: String {
        switch mode {
        case .lockBits:
            return "The tag you scan next becomes read only forever."
        case .ndefFlag:
            return "Phones will treat the tag you scan next as read only. On a Type 2 tag this is permanent."
        }
    }

    // MARK: Actions

    private func lock() {
        let method = mode
        Task { @MainActor in
            do {
                switch method {
                case .lockBits:
                    try await app.nfc.run(
                        alertMessage: "Hold your iPhone near the tag.",
                        successMessage: "Tag locked."
                    ) { session, tag in
                        try await TagOperations.lock(session, tag)
                    }
                case .ndefFlag:
                    try await app.nfc.run(
                        alertMessage: "Hold your iPhone near the tag.",
                        successMessage: "Read only flag set."
                    ) { session, tag in
                        try await TagOperations.setNDEFReadOnlyFlag(session, tag)
                    }
                }
                // Each lock is a separate decision, so the next tag needs a fresh acknowledgement.
                acknowledged = false
                Haptics.success()
                switch method {
                case .lockBits:
                    alert = AlertItem.success("The tag is now read only.")
                case .ndefFlag:
                    alert = AlertItem.success("The tag is now marked read only. Phones will no longer write records to it.")
                }
            } catch {
                if NFCEditorError.map(error).isCancellation { return }
                Haptics.error()
                alert = AlertItem(error: error)
            }
        }
    }
}
