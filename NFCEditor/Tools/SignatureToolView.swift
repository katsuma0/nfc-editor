import Foundation
import SwiftUI
import UIKit
import CoreNFC

/// Reads the 32-byte NXP originality signature from NTAG 21x and Ultralight EV1 chips.
@MainActor
struct SignatureToolView: View {
    @Environment(AppState.self) private var app
    @State private var lastRead: SignatureResult?
    @State private var copied = false
    @State private var alert: AlertItem?

    var body: some View {
        Form {
            Section {
                ScanButton("Read signature") {
                    read()
                }
            } footer: {
                Text("NXP signs every NTAG 213, 215, 216 and MIFARE Ultralight EV1 chip with a 32-byte originality signature tied to its serial number. It helps tell a genuine NXP chip from a clone.")
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())

            if let lastRead {
                Section {
                    LabeledContent("Chip", value: lastRead.chipName)
                    LabeledContent("Serial number") {
                        Text(lastRead.uid.hexString(separator: ":"))
                            .font(.body.monospaced())
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Signature")
                        Text(lastRead.signature.hexString(separator: " "))
                            .font(.footnote.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    Button {
                        copy(lastRead.signature)
                    } label: {
                        Label(copyTitle, systemImage: copyImage)
                    }
                } header: {
                    Text("Signature")
                } footer: {
                    Text("Read at \(lastRead.readAt.formatted(date: .omitted, time: .shortened)). Verify it against NXP's public key with the NXP TagInfo app. The check needs the serial number as well as the signature.")
                }
            }
        }
        .navigationTitle("Signature")
        .navigationBarTitleDisplayMode(.inline)
        .alertItem($alert)
    }

    private var copyTitle: String {
        copied ? "Copied" : "Copy signature"
    }

    private var copyImage: String {
        copied ? "checkmark" : "doc.on.doc"
    }

    // MARK: Actions

    private func read() {
        Task { @MainActor in
            do {
                let result = try await app.nfc.run(
                    alertMessage: "Hold your iPhone near the tag.",
                    successMessage: "Signature read."
                ) { session, tag -> SignatureResult in
                    let (spec, uid) = try await TagOperations.identify(session, tag)
                    let signature = try await TagOperations.readSignature(session, tag)
                    return SignatureResult(chipName: spec.name, uid: uid, signature: signature, readAt: Date())
                }
                lastRead = result
                copied = false
                Haptics.success()
            } catch {
                if NFCEditorError.map(error).isCancellation { return }
                Haptics.error()
                alert = AlertItem(error: error)
            }
        }
    }

    private func copy(_ signature: Data) {
        UIPasteboard.general.string = signature.hexString()
        Haptics.tap()
        copied = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            copied = false
        }
    }
}

private struct SignatureResult: Hashable, Sendable {
    var chipName: String
    var uid: Data
    var signature: Data
    var readAt: Date
}
